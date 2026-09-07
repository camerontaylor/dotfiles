#!/usr/bin/env python3
"""Quota pacing cues from the CodexBar collector, delivered via ntfy.

Pacing model (Cameron's, 2026-09-06). For each window let

    r_u = 100 - used%        usage remaining
    r_t = time remaining as a % of the window   ("pro rata remaining", prr)

    relevance = (r_t - r_u) / r_t

    relevance >  +0.25  ->  HOT    burning faster than schedule
    relevance <  -0.25  ->  WASTE  burning slower than schedule
    otherwise           ->  on pace, cue suppressed

Normalising by r_t makes the band tighten as the window closes, which is the
intent: near the reset, a small absolute gap is a large proportional one.

Cue points, evaluated only at a crossing and only once per window instance:

  weekly windows (>= 1 day)
      usage   50% / 75% / 90% used        -> report only if HOT
      time    50% remaining / 1 day left  -> report only if WASTE

  short windows (5h)
      usage   80% used                    -> report only if HOT
      One cue only: 5h windows reset ~4.8x/day and under-using one is normal.
      80% is chosen so it fires while ~27%+ of the window still remains
      (r_u=20 < 0.75*r_t requires r_t > 26.7%) -- enough room to finish a task
      or route work to another provider -- and stays silent when 80% used
      simply reflects good pacing near the reset.

Absent data is treated as unknown, never as zero: a window missing usedPercent
or resetsAt is skipped, not reported at 0%.

Two liveness alarms ride along (state-tracked, one alert per episode):

  * a provider+window pair that was seen before but has been absent from
    /usage for MISS_LIMIT consecutive polls -> "window missing" (the usual
    cause is credential expiry, which silently removes the window);
  * the /usage endpoint itself unreachable for MISS_LIMIT consecutive polls
    -> "collector unreachable" (a collector problem, not credential expiry;
    individual windows are NOT marked missing while the endpoint is down).

Both send a default-priority all-clear when the thing comes back.
"""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from xml.sax.saxutils import escape

# Plain /usage honours the enabled-provider set in ~/.config/codexbar/config.json.
# ?provider=all yields the same windows but makes the collector consider all 69
# registered providers, most of which have no credentials here.
USAGE_URL = os.environ.get("CODEXBAR_URL", "http://127.0.0.1:8791/usage")
NTFY_URL = os.environ.get("NTFY_URL", "http://127.0.0.1:2586")
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "quota")
STATE = pathlib.Path(os.environ.get(
    "CUE_STATE", os.path.expanduser("~/.local/state/codexbar-alerts/state.json")))

BAND = 0.25
USAGE_CUES_LONG = [50.0, 75.0, 90.0]
USAGE_CUES_SHORT = [80.0]
TIME_CUE_FRACTIONS = [50.0]        # % of window remaining
TIME_CUE_MINUTES = [24 * 60]       # absolute minutes remaining
LONG_WINDOW_MINUTES = 1440         # >= 1 day counts as a "weekly" window
# Consecutive polls a window (or the collector) must be absent before the
# liveness alarm fires: 3 polls at the 10-minute timer cadence ~= 30 minutes,
# which tolerates one-off collector hiccups.
MISS_LIMIT = 3

CLICK_URL = "https://usage.wedrifid.dev/"

# Notification card image (design memo: hart docs/research/
# 2026-09-06-quota-cue-ntfy-images.md). Provider hues are nudged from the
# CodexBar app palette until the dataviz validator passes on the dark surface;
# a new provider needs a validated hue here, otherwise it falls back to gray.
PROVIDER_COLOR = {
    "codex": "#3399bd",
    "claude": "#cd7f52",
    "zai": "#dd3d85",
}
_C = dict(surface="#1a1a19", ink="#ffffff", ink2="#c3c2b7", muted="#898781",
          track="#2c2c2a", hot="#d03b3b", slack="#3987e5")


def human(minutes):
    if minutes is None:
        return "?"
    if minutes < 90:
        return f"{minutes:.0f}m"
    if minutes < 48 * 60:
        return f"{minutes / 60:.1f}h"
    return f"{minutes / 1440:.1f}d"


def parse_reset(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone.utc)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def iter_windows(payload):
    """Yield (provider, label, window-dict-or-None) for every slot in the payload."""
    for entry in payload:
        provider = entry.get("provider") or "?"
        usage = entry.get("usage") or {}
        yield provider, "5h", usage.get("primary")
        yield provider, "weekly", usage.get("secondary")
        for extra in usage.get("extraRateWindows") or []:
            yield (provider, extra.get("title") or extra.get("id") or "extra",
                   extra.get("window"))


def present_pairs(payload):
    """provider|label pairs the collector reported at all, however incomplete.

    Deliberately looser than windows(): a window that exists but is briefly
    unusable (mid-reset, a missing field) is still *present*. Credential
    expiry removes the window object entirely -- that is the absence the
    liveness alarm watches for.
    """
    return {f"{provider}|{label}"
            for provider, label, win in iter_windows(payload) if win}


def windows(payload, now):
    """Yield one dict per usable rate window across all providers."""
    for provider, label, win in iter_windows(payload):
        if not win:
            continue
        used = win.get("usedPercent")
        span = win.get("windowMinutes")
        reset = parse_reset(win.get("resetsAt"))
        if used is None or not span or reset is None:
            continue  # absent != zero
        left_min = (reset - now).total_seconds() / 60
        if left_min <= 0:
            continue
        r_t = max(0.0, min(100.0, 100.0 * left_min / span))
        if r_t <= 0.5:
            continue  # too close to reset for the ratio to mean anything
        r_u = 100.0 - used
        yield dict(provider=provider, label=label, used=used, span=span,
                   reset=reset, left_min=left_min, r_t=r_t, r_u=r_u,
                   relevance=(r_t - r_u) / r_t,
                   key=f"{provider}|{label}|{reset.isoformat()}")


def verdict(w):
    if w["relevance"] > BAND:
        return "hot"
    if w["relevance"] < -BAND:
        return "waste"
    return "onpace"


def due_cues(w):
    """Cue ids whose crossing condition is met, with an urgency rank.

    Rank matters because several cues can come due at once -- on a first run,
    or after downtime, a window at 95% has already crossed 50/75/90. Sending
    all three says the same thing three times, so the caller sends only the
    highest-ranked and silently retires the rest.
    """
    out = []
    long_window = w["span"] >= LONG_WINDOW_MINUTES
    for pct in (USAGE_CUES_LONG if long_window else USAGE_CUES_SHORT):
        if w["used"] >= pct:
            out.append((f"used{pct:g}", "hot", pct))
    if long_window:
        for frac in TIME_CUE_FRACTIONS:
            if w["r_t"] <= frac:
                # tighter deadline -> higher rank
                out.append((f"tleft{frac:g}pct", "waste", 100.0 - frac))
        for mins in TIME_CUE_MINUTES:
            if w["left_min"] <= mins:
                out.append((f"tleft{mins}min", "waste",
                            100.0 - 100.0 * mins / w["span"]))
    return out


def projection_line(w, kind):
    if w["r_t"] >= 99.5:
        return None
    proj = w["used"] / ((100.0 - w["r_t"]) / 100.0)
    if kind == "hot":
        exhaust = w["left_min"] * (w["r_u"] / w["r_t"]) if w["r_t"] else 0
        return (f"At this rate you run out in {human(exhaust)} — "
                f"{human(w['left_min'] - exhaust)} before reset.")
    return (f"At this rate you finish at {min(proj, 100):.0f}% — "
            f"leaving {max(0.0, 100 - proj):.0f}% unused.")


def compose(w, cue, kind):
    head = "burning hot" if kind == "hot" else "under-using"
    # HTTP header values are latin-1; ntfy reads the title from a header, so
    # keep it ASCII. The body is sent as UTF-8 bytes and may use any character.
    title = f"{w['provider']} {w['label']} - {head}".encode("ascii", "replace").decode()
    lines = [
        f"{w['used']:.0f}% used · {human(w['left_min'])} left ({w['r_t']:.0f}% of window)",
        f"{w['r_u']:.0f}% quota left vs {w['r_t']:.0f}% pro rata "
        f"({w['r_u'] / w['r_t']:.2f}x)",
    ]
    proj = projection_line(w, kind)
    if proj is not None:
        lines.append(proj)
    lines.append(f"cue: {cue}")
    return title, "\n".join(lines)


def card_svg(provider, kind, rows, footer):
    """Mini CodexBar provider card: every window as a thin brand-hue bar, the
    cue verdict layered on (chip, per-bar pace tick at elapsed%, status dot +
    full saturation + projection extension on the trigger row)."""
    W, H, MX = 1024, 512, 64
    font = "DejaVu Sans, sans-serif"
    color = PROVIDER_COLOR.get(provider, _C["muted"])
    status = _C["hot"] if kind == "hot" else _C["slack"]
    chip_label, chip_w = ("HOT", 118) if kind == "hot" else ("SLACK", 148)

    n = min(len(rows), 3)
    footer_y = 176 + (n - 1) * 108 + 102
    dy = max((H - footer_y) // 2, 0)

    a = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
         f'viewBox="0 0 {W} {H}">',
         f'<rect width="{W}" height="{H}" fill="{_C["surface"]}"/>',
         f'<g transform="translate(0,{dy})">',
         f'<circle cx="{MX+20}" cy="76" r="20" fill="{color}"/>',
         f'<text x="{MX+62}" y="92" font-family="{font}" font-size="48" '
         f'font-weight="bold" fill="{_C["ink"]}">{escape(provider)}</text>',
         f'<rect x="{W-MX-chip_w}" y="50" rx="18" width="{chip_w}" height="46" fill="{status}"/>',
         f'<text x="{W-MX-chip_w/2}" y="82" text-anchor="middle" font-family="{font}" '
         f'font-size="28" font-weight="bold" fill="{_C["surface"]}">{chip_label}</text>']

    bar_w = W - 2 * MX
    x = lambda pct: MX + bar_w * min(max(pct, 0.0), 100.0) / 100.0
    row_y = 176
    for r in rows[:3]:
        trig, used, elapsed = r["trigger"], r["used"], 100.0 - r["r_t"]
        lx = MX
        if trig:
            a.append(f'<circle cx="{MX+9}" cy="{row_y-11}" r="9" fill="{status}"/>')
            lx = MX + 32
        weight = ' font-weight="bold"' if trig else ""
        a.append(f'<text x="{lx}" y="{row_y}" font-family="{font}" '
                 f'font-size="{36 if trig else 34}"{weight} '
                 f'fill="{_C["ink"] if trig else _C["ink2"]}">'
                 f'{escape(r["label"])} · {used:.0f}% used</text>')
        a.append(f'<text x="{W-MX}" y="{row_y}" text-anchor="end" font-family="{font}" '
                 f'font-size="30" fill="{_C["muted"]}">resets in {human(r["left_min"])}</text>')
        by, bh = row_y + 18, 22
        a.append(f'<rect x="{MX}" y="{by}" rx="11" width="{bar_w}" height="{bh}" fill="{_C["track"]}"/>')
        if trig and elapsed > 0.5:
            proj = min(used / (elapsed / 100.0), 100.0)
            if proj > used:
                rx_ext = 11 if proj >= 99.5 else 0
                a.append(f'<rect x="{x(used)}" y="{by}" rx="{rx_ext}" '
                         f'width="{x(proj)-x(used)}" height="{bh}" '
                         f'fill="{color}" fill-opacity="0.32"/>')
                if rx_ext:
                    a.append(f'<rect x="{x(used)}" y="{by}" width="12" height="{bh}" '
                             f'fill="{color}" fill-opacity="0.32"/>')
        if used > 0:
            op = "1" if trig else "0.55"
            uw = max(x(used) - MX, 16)
            a.append(f'<rect x="{MX}" y="{by}" rx="11" width="{uw}" height="{bh}" '
                     f'fill="{color}" fill-opacity="{op}"/>')
            if uw > 22:
                a.append(f'<rect x="{MX+uw-11}" y="{by}" width="11" height="{bh}" '
                         f'fill="{color}" fill-opacity="{op}"/>')
        tx = x(elapsed)
        a.append(f'<rect x="{tx-2}" y="{by-8}" width="4" height="{bh+16}" fill="{_C["ink"]}"/>')
        row_y += 108

    if footer:
        a.append(f'<text x="{MX}" y="{footer_y}" font-family="{font}" '
                 f'font-size="33" fill="{_C["ink2"]}">{escape(footer)}</text>')
    a.append('</g></svg>')
    return "".join(a)


def render_card(provider, kind, rows, footer):
    """SVG -> PNG bytes via rsvg-convert; None on any failure (the cue must
    never be lost to its picture). Temp files live in the state dir -- the
    only writable path under the unit's sandbox -- and double as a debugging
    artifact for the last rendered card."""
    try:
        svg = STATE.parent / "last-cue.svg"
        png = STATE.parent / "last-cue.png"
        STATE.parent.mkdir(parents=True, exist_ok=True)
        svg.write_text(card_svg(provider, kind, rows, footer))
        subprocess.run(["rsvg-convert", "-o", str(png), str(svg)],
                       check=True, timeout=30, capture_output=True)
        return png.read_bytes()
    except Exception as exc:  # noqa: BLE001
        print(f"card render failed (sending text-only): {exc}", file=sys.stderr)
        return None


def publish(title, body, prio, tags, dry, image=None):
    if dry:
        note = f"  [+ card image, {len(image)} bytes]" if image else ""
        print(f"--- [{prio}] {title}{note}\n{body}\n")
        return True
    if image is not None:
        # PUT the PNG as the body; message text and metadata travel as
        # URL-encoded query params (headers are latin-1 -- the em-dash trap).
        params = urllib.parse.urlencode({
            "title": title, "message": body, "priority": prio,
            "tags": tags, "click": CLICK_URL})
        req = urllib.request.Request(
            f"{NTFY_URL}/{NTFY_TOPIC}?{params}", data=image, method="PUT",
            headers={"X-Filename": "quota-cue.png",
                     "Content-Type": "image/png"})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status < 300:
                    return True
        except Exception as exc:  # noqa: BLE001
            print(f"ntfy image publish failed, falling back to text: {exc}",
                  file=sys.stderr)
    req = urllib.request.Request(
        f"{NTFY_URL}/{NTFY_TOPIC}", data=body.encode(),
        headers={"Title": title, "Priority": prio, "Tags": tags,
                 "Click": CLICK_URL})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status < 300
    except Exception as exc:  # noqa: BLE001
        print(f"ntfy publish failed: {exc}", file=sys.stderr)
        return False


def load_state():
    raw = {}
    if STATE.exists():
        try:
            raw = json.loads(STATE.read_text())
        except ValueError:
            raw = {}
    if "cues" not in raw:
        raw = {"cues": raw}  # v1 layout: a flat {slot-key: timestamp} map
    raw.setdefault("cues", {})
    raw.setdefault("presence", {})
    raw.setdefault("collector", {"misses": 0, "alerted": False})
    return raw


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=1, sort_keys=True))


def refresh_cue_slots(cues, rows, now):
    """Re-key stored cue slots onto each live window's current resetsAt, then
    drop only slots whose window instance has actually reset.

    Collectors jitter resetsAt by whole seconds between polls (codex weekly
    drifted 07:01:48 -> 07:01:49 mid-instance on 2026-09-06). An exact-match
    key treats every jitter as a brand-new window, which both evicted the old
    slot and dodged the dedup check -- a cue then re-fires every run the reset
    drifts. Two resets of the same provider|label less than a quarter of the
    window span apart are the same instance; successive real instances are a
    full span apart.
    """
    for w in rows:
        for k in list(cues):
            parts = k.split("|")
            if (len(parts) != 4 or parts[0] != w["provider"]
                    or parts[1] != w["label"]):
                continue
            old = parse_reset(parts[2])
            if old is None or parts[2] == w["reset"].isoformat():
                continue
            if abs((old - w["reset"]).total_seconds()) < w["span"] * 60 / 4:
                cues[f"{w['key']}|{parts[3]}"] = cues.pop(k)
    out = {}
    for k, v in cues.items():
        parts = k.split("|")
        reset = parse_reset(parts[2]) if len(parts) == 4 else None
        if reset is not None and reset > now:
            out[k] = v
    return out


def ascii_title(text):
    # HTTP header values are latin-1; keep titles pure ASCII (see compose()).
    return text.encode("ascii", "replace").decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print cues, send nothing, do not record state")
    ap.add_argument("--from-file", help="read a usage payload from disk instead of the collector")
    ap.add_argument("--show", action="store_true", help="print the pacing table for every window and exit")
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    # --from-file without an explicit CUE_STATE would let fixture data clobber
    # the real dedup/presence state; treat that combination as read-only.
    protect_state = bool(args.from_file) and "CUE_STATE" not in os.environ
    write_state = not args.dry_run and not protect_state

    state = load_state()

    if args.from_file:
        payload = json.load(open(args.from_file))
    else:
        try:
            with urllib.request.urlopen(USAGE_URL, timeout=120) as r:
                payload = json.load(r)
        except Exception as exc:  # noqa: BLE001
            # A dead endpoint is a collector problem, not credential expiry:
            # count it separately and leave per-window presence untouched.
            col = state["collector"]
            col["misses"] = col.get("misses", 0) + 1
            print(f"usage fetch failed ({col['misses']} consecutive): {exc}",
                  file=sys.stderr)
            if col["misses"] >= MISS_LIMIT and not col.get("alerted"):
                body = (f"{USAGE_URL} unreachable for {col['misses']} "
                        f"consecutive polls (10-minute cadence). Collector "
                        f"problem, not credential expiry - check "
                        f"`systemctl --user status codexbar-serve`.")
                if publish("codexbar collector unreachable", body,
                           "high", "rotating_light", args.dry_run):
                    col["alerted"] = True
            if write_state:
                save_state(state)
            return 1

    rows = list(windows(payload, now))

    if args.show:
        print(f"{'provider/window':<26}{'used':>6}{'r_u':>7}{'r_t':>7}{'relev':>8}  verdict")
        for w in sorted(rows, key=lambda x: -x["relevance"]):
            print(f"{w['provider'] + '/' + w['label']:<26}{w['used']:>6.1f}"
                  f"{w['r_u']:>7.1f}{w['r_t']:>7.1f}{w['relevance']:>+8.0%}  {verdict(w)}")
        return 0

    # The collector answered: close any unreachable episode. Fixture runs say
    # nothing about the live collector, so they leave the counter alone.
    if not args.from_file:
        col = state["collector"]
        if col.get("alerted"):
            publish("codexbar collector back", f"{USAGE_URL} reachable again.",
                    "default", "white_check_mark", args.dry_run)
        state["collector"] = {"misses": 0, "alerted": False}

    # Liveness: previously-seen provider|window pairs that have vanished from
    # /usage. The usual cause is credential expiry (docs/llm-quota.md, Gaps).
    seen = present_pairs(payload)
    presence = state["presence"]
    for pair in sorted(seen):
        rec = presence.get(pair) or {}
        if rec.get("alerted"):
            provider, label = pair.split("|", 1)
            publish(ascii_title(f"{provider} {label} - window back"),
                    f"{provider} {label} is reported by {USAGE_URL} again.",
                    "default", "white_check_mark", args.dry_run)
        presence[pair] = {"last_seen": now.isoformat(), "misses": 0,
                          "alerted": False}
    for pair, rec in sorted(presence.items()):
        if pair in seen:
            continue
        rec["misses"] = rec.get("misses", 0) + 1
        if rec["misses"] >= MISS_LIMIT and not rec.get("alerted"):
            provider, label = pair.split("|", 1)
            body = (f"Absent from {USAGE_URL} for {rec['misses']} consecutive "
                    f"polls (>=30 min at the 10-minute cadence); last seen "
                    f"{rec.get('last_seen', '?')}.\n"
                    f"Likeliest cause: expired {provider} credentials - the "
                    f"collector cannot refresh them (re-login via the "
                    f"provider CLI). Check `codexbar --provider {provider} "
                    f"--format json`; config env: ~/.local/state/codexbar/env")
            if publish(ascii_title(f"{provider} {label} - window missing"),
                       body, "high", "rotating_light", args.dry_run):
                rec["alerted"] = True

    cues = refresh_cue_slots(state["cues"], rows, now)
    state["cues"] = cues

    sent = 0
    for w in rows:
        v = verdict(w)
        # crossings that match the pacing verdict and have not been reported
        pending = [(cue, rank) for cue, wants, rank in due_cues(w)
                   if wants == v and not cues.get(f"{w['key']}|{cue}")]
        if not pending:
            continue
        pending.sort(key=lambda c: -c[1])
        loudest = pending[0][0]
        title, body = compose(w, loudest, v)
        card_rows = [dict(r, trigger=(r["key"] == w["key"]))
                     for r in rows if r["provider"] == w["provider"]]
        image = render_card(w["provider"], v, card_rows, projection_line(w, v))
        if publish(title, body, "high" if v == "hot" else "default",
                   "fire" if v == "hot" else "leaves", args.dry_run,
                   image=image):
            sent += 1
            # retire every co-due cue, so the quieter ones cannot fire later
            for cue, _ in pending:
                cues[f"{w['key']}|{cue}"] = now.isoformat()

    if write_state:
        save_state(state)
    elif protect_state and not args.dry_run:
        print("state not written: --from-file without a CUE_STATE override")
    print(f"{len(rows)} windows, {sent} cue(s) {'would be ' if args.dry_run else ''}sent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
