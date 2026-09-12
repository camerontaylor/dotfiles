# Handover — A19 Bluetooth mic on ceres

2026-09-10. Everything needed to get a **microphone signal** from the A19
headset on ceres, and nothing else. Background and diagnosis:
[`docs/bluetooth-audio-headless.md`](../docs/bluetooth-audio-headless.md).

Purpose: mic noise-testing experiments. This is a temporary setup — see
§5 to tear it down.

## 1. Constants

| | |
|---|---|
| Host | **ceres** (run there; agent sessions already are) |
| MAC | `7B:FA:DC:A1:66:C9` |
| Card | `bluez_card.7B_FA_DC_A1_66_C9` |
| Source | `bluez_input.7B:FA:DC:A1:66:C9` |
| Needed profile | `headset-head-unit` (HFP, mSBC, wideband 16 kHz) |

Already done and persistent: device is **paired, bonded and trusted**; the
WirePlumber drop-in `~/.config/wireplumber/wireplumber.conf.d/50-bluez-headless.conf`
exists (without it there is no Bluetooth audio on this box at all).

## 2. Two traps — read before recording

**Trap 1: the profile silently reverts to `a2dp-sink`.** WirePlumber's policy
restores A2DP whenever no capture stream is active, so a profile you set in
one command may be gone by the next. **Set it at the start of every recording,
and re-check it after any `wireplumber` restart or headset reconnect.**

**Trap 2: `bluez_input` exists and records happily under A2DP — and produces
pure silence.** `a2dp-sink` has `sources: 0`, but the name still shows up in
`pactl list sources short`, and `pw-record` against it exits 0 and writes a
valid WAV full of dither. This is the failure that eats an experiment session.

So `pactl list sources | grep bluez` is **not** a readiness check. The only
trustworthy check is the active profile:

```sh
pactl list cards | sed -n '/bluez_card/,/^$/p' | grep 'Active Profile'
# must print: Active Profile: headset-head-unit
```

## 3. Get a signal

```sh
export XDG_RUNTIME_DIR=/run/user/1000        # required; wpctl/pactl fail without it

# 1. connect if needed (Trusted=yes, but cheap headsets sleep)
bluetoothctl info 7B:FA:DC:A1:66:C9 | grep Connected
bluetoothctl connect 7B:FA:DC:A1:66:C9

# 2. switch to the mic-bearing profile  -- EVERY TIME
pactl set-card-profile bluez_card.7B_FA_DC_A1_66_C9 headset-head-unit

# 3. confirm it took (Trap 1)
pactl list cards | sed -n '/bluez_card/,/^$/p' | grep 'Active Profile'

# 4. record -- --target is mandatory, the default source is the built-in card
pw-record --target bluez_input.7B:FA:DC:A1:66:C9 \
          --rate 16000 --channels 1 --format s16 /tmp/mic.wav
```

`pw-record` runs until interrupted; background it and `kill -INT` for a fixed
duration. Note it may overrun a `timeout` value, so measure duration from the
file, not from the wall clock.

## 4. Confirm it is real, not silence

`audioop` was removed in Python 3.13 — compute the level directly:

```python
import wave, array, math
w = wave.open('/tmp/mic.wav'); n, sr = w.getnframes(), w.getframerate()
a = array.array('h'); a.frombytes(w.readframes(n))
print("dur", n/sr, "peak", max(abs(x) for x in a),
      "rms", math.sqrt(sum(float(x)*x for x in a)/len(a)))
# per-second peaks -- a single burst is invisible in an overall RMS
print([max((abs(x) for x in a[s*sr:(s+1)*sr]), default=0) for s in range(n//sr)])
```

| Peak (of 32768) | Meaning |
|---|---|
| exactly 0 | stream never opened — profile/SCO problem |
| ~25, ~50% non-zero | link live, room quiet. **Not a failure** — this is the A2DP-trap signature too, so check the profile |
| > 300 | real acoustic signal |

Verified baselines from setup: quiet room peak **25** (−62 dBFS); a deliberate
tap peak **6794** (−13.7 dBFS). Mic gain is 100% / 0 dB, unmuted.

## 5. Teardown when experiments are done

```sh
rm ~/.config/wireplumber/wireplumber.conf.d/50-bluez-headless.conf
systemctl --user restart wireplumber
bluetoothctl remove 7B:FA:DC:A1:66:C9
```

Nothing was committed to the repo except the docs file; no deploy fragment,
no `configs/` entry. Headless boxes get no ongoing headset support by design.
