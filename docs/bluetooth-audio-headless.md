# Bluetooth audio on a headless box

Pairing a Bluetooth headset to a box with no seat (ceres, makemake, pluto)
succeeds, and then every *connect* fails. The cause is not the radio and not
the pairing keys — it is that WirePlumber never registers an A2DP endpoint
with BlueZ when nobody is logged in at a console.

Written up 2026-09-10 after pairing a headset to ceres for microphone noise
testing. **Nothing here is deployed.** Headless boxes have no ongoing need for
headset support, so this is a recipe to apply by hand and then revert — not a
`configs/` entry and not a deploy fragment.

## The symptom

`bluetoothctl pair` reports success and the device shows `Paired: yes`,
`Bonded: yes`, `Trusted: yes`, with a correct SDP profile list (Audio Sink,
Handsfree, AVRCP). Then:

```
$ bluetoothctl connect 7B:FA:DC:A1:66:C9
Failed to connect: org.bluez.Error.Failed br-connection-unknown
```

`br-connection-unknown` reads like a link-layer failure — out of range, wrong
address, device asleep. It is none of those. The real error is one layer up,
and only `bluetoothd` logs it:

```
$ journalctl -u bluetooth --since -3min
bluetoothd: a2dp-sink profile connect failed for 7B:FA:DC:A1:66:C9:
            Protocol not available
```

**Always check the `bluetooth` unit's journal before believing the
`bluetoothctl` error string.** BlueZ collapses profile-layer failures into a
generic connection error at the D-Bus boundary.

## Why it happens

BlueZ does not encode audio. It exposes `org.bluez.Media1` and waits for a
userspace daemon — WirePlumber, via PipeWire's `libspa-bluez5` plugin — to
call `RegisterEndpoint` and advertise "I can be an A2DP source". With no
endpoint registered, every A2DP connect fails with `Protocol not available`.

WirePlumber gates that registration behind **logind seat monitoring**. From
the stock `/usr/share/wireplumber/wireplumber.conf`:

```
{
  type = virtual, provides = monitor.bluez.seat-monitoring,
  requires = [ support.logind ]
}
```

The intent is desktop-correct: on a multi-user machine only the person
physically at the console should own the Bluetooth audio hardware. On a
headless box it means the monitor never loads at all. Confirm with:

```
$ loginctl list-sessions --no-legend | awk '{print $1}' | \
    xargs -I{} loginctl show-session {} -p Seat -p Remote -p State
```

On ceres every session is `Seat=` (empty) and `Remote=yes` — SSH only, no
seat — so the gate never opens.

Two tells that point at this rather than at the radio:

- `wpctl status` lists the ALSA card but has **no Bluetooth section**. ALSA's
  monitor has no seat gate; bluez's does. Divergent activation rules inside
  one daemon.
- WirePlumber's journal contains **no bluez lines at all** — not even errors.
  A component that is gated off never runs, so it never complains.

## The fix

Drop the seat gate for the `main` profile:

```sh
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cat > ~/.config/wireplumber/wireplumber.conf.d/50-bluez-headless.conf <<'CONF'
wireplumber.profiles = {
  main = {
    monitor.bluez.seat-monitoring = disabled
  }
}
CONF
systemctl --user restart wireplumber
```

Then connect. `bluetoothctl` needs no changes — the pairing from before the
fix stays valid, since only the endpoint was ever missing.

Verify with `wpctl status`: a `[bluez5]` device, a sink, and (for a headset)
a `bluez_input.<MAC>` source all appear, and PipeWire reports
`api.bluez5.profile = "a2dp-sink"`.

To revert, delete the drop-in and restart WirePlumber again.

## Pairing itself, non-interactively

`bluetoothctl` is an interactive REPL, which is awkward from a script or an
agent shell. Two things make it scriptable:

- It reads its REPL commands from stdin, so `printf 'cmd\n' | bluetoothctl`
  works without a PTY.
- Pairing must happen **while a scan is active**. BlueZ drops non-bonded
  devices from its object tree shortly after discovery stops, so a later
  `bluetoothctl info <MAC>` returns "not available" and `pair` has nothing to
  target. Keep scan, pair and trust in one session:

```sh
{ printf 'agent on\ndefault-agent\nscan on\n'; sleep 12
  printf 'pair <MAC>\n';  sleep 20
  printf 'trust <MAC>\n'; sleep 3
  printf 'scan off\nquit\n'; } | bluetoothctl
```

`trust` is not redundant with `pair`: pairing exchanges keys, trusting
authorises the device to reconnect later without a prompt. Omitting it is the
usual reason a headset pairs fine but will not come back after a power cycle.

To tell a headset apart from the phones and beacons a scan picks up, look for
`Icon: audio-headset` — BlueZ derives it from the class-of-device bits
(`0x240404` = Audio service, Audio/Video major, Wearable Headset minor). A
device advertising only over LE shows no `Class` and no `Icon` at all; if that
is all you see, the headset was not in pairing mode during the scan window.

## Getting the microphone (the A2DP/HFP trade-off)

Connecting a headset is not enough to get a microphone. Classic Bluetooth
carries one profile at a time over a single link, so a headset is *either*
high-fidelity stereo playback *or* duplex with a mic — never both. Check what
the card actually offers:

```
$ pactl list cards | grep -A6 'Profiles:'
a2dp-sink:             High Fidelity Playback (A2DP Sink, codec SBC)
                       (sinks: 1, sources: 0, ...)
headset-head-unit:     Headset Head Unit (HSP/HFP, codec MSBC)
                       (sinks: 1, sources: 1, ...)
headset-head-unit-cvsd: Headset Head Unit (HSP/HFP, codec CVSD)
                       (sinks: 1, sources: 1, ...)
```

Note `sources: 0` on `a2dp-sink` — the default profile has **no capture
device**. Switch to HFP to get one:

```sh
pactl set-card-profile bluez_card.<MAC_WITH_UNDERSCORES> headset-head-unit
```

Prefer `headset-head-unit` (**mSBC**, wideband 16 kHz) over
`headset-head-unit-cvsd` (**CVSD**, narrowband 8 kHz) for anything acoustic —
CVSD discards everything above roughly 4 kHz. The cost is that playback drops
to narrowband mono for as long as the mic is in use.

One caveat when hunting for the capture device: with the A2DP profile active,
`wpctl status` may still show a `bluez_input.<MAC>` entry under **Filters**.
That is a loopback artifact, not a usable source — trust the profile's
`sources:` count, not the presence of that name.

### Verifying capture rather than trusting it

A dead HFP link and a live one in a quiet room look identical in `wpctl`.
Record and measure:

```sh
pw-record --target bluez_input.<MAC> --rate 16000 --channels 1 \
          --format s16 /tmp/mic.wav
```

Then check the level (`audioop` was removed in Python 3.13, so compute it
directly):

```python
import wave, array, math
w = wave.open('/tmp/mic.wav'); n = w.getnframes()
a = array.array('h'); a.frombytes(w.readframes(n))
print(max(abs(x) for x in a))   # 32768 = full scale
```

Interpreting the result:

| Peak | Meaning |
|---|---|
| exactly 0, all samples zero | stream never opened — profile or SCO link problem |
| ~25 (≈ −62 dBFS), ~50% non-zero | link is live, carrying dither; room was just quiet |
| >300 | real acoustic signal |

The middle row is the one that misleads: non-zero dither proves the SCO link
and the codec are working even when the recording sounds like nothing. Confirm
with a deliberate noise (speak, or tap the mic) and a per-second peak profile
rather than a single overall RMS, which a long silence will average away.
