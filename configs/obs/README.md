# OBS two-track audio recording

Reproducible OBS Studio setup for **two-track recording**:

| Track | Source | OBS object |
|-------|--------|-----------|
| **1 — Mic** | default audio input | `Mic/Aux` global device (`coreaudio_input_capture`), `mixers=1` |
| **2 — Desktop** | all system/app audio | `Desktop Audio` source (`sck_audio_capture`, ScreenCaptureKit, `type=0`), `mixers=2` |

Recording output is **Advanced** mode with `RecTracks=3` (records tracks 1 and 2
as separate tracks in one file). Files land in `~/Movies`.

## How to record (quick start)

1. Open **OBS** (`open -a OBS`). It comes up on the `TwoTrack` profile + scene
   collection already selected.
2. In the **Audio Mixer** panel, confirm both meters react: **Mic/Aux** when you
   talk, **Desktop Audio** when something plays. If a meter is dead, see
   [macOS permissions](#macos-permissions) below.
3. Click **Start Recording** (Controls panel, bottom-right). Click **Stop
   Recording** when done.
4. The file lands in `~/Movies` (e.g. `2026-07-04 15-30-00.mov`) as **one video
   file with two separate audio tracks** — track 1 mic, track 2 desktop.

Pull the tracks apart later in any editor, or with ffmpeg:

```sh
# mic only (track 1) and desktop only (track 2) to separate files
ffmpeg -i "$f" -map 0:a:0 mic.wav
ffmpeg -i "$f" -map 0:a:1 desktop.wav
```

Tip: set a Start/Stop Recording hotkey in **Settings → Hotkeys** so you don't
have to click. The preview being black is normal (see [Note on video](#note-on-video)).

## Opt-in

This is **not** installed by default. `scripts/deploy.d/77_obs.zsh` only acts on
macOS hosts whose short hostname is listed in [`hosts.conf`](hosts.conf).

To enable on a machine: add its `scutil --get LocalHostName` (or `hostname -s`)
to `hosts.conf` and run `deploy.zsh`. That installs the `obs` Homebrew cask and
seeds the config below.

## Files

- `scenes/TwoTrack.json` — scene collection (mic routing + desktop-audio source).
- `profiles/TwoTrack/basic.ini` — profile (Advanced output, 2 record tracks,
  track names Mic/Desktop). The record path is stored as `@HOME@/Movies` and the
  seeder substitutes the real home directory.

## Seeding is copy-if-absent (never a symlink)

OBS continuously **writes back** to its scene/profile files (window state, UUIDs,
absolute paths), so these are *not* symlinked like read-only configs such as
`aerospace.toml`. `scripts/configure-obs.py` copies the templates into
`~/Library/Application Support/obs-studio/` **only when the `TwoTrack` profile /
scene collection are absent**, then points `user.ini` at them (only when OBS is
not running). An existing `TwoTrack` config is left untouched — edit it in OBS
and, if you want to capture the changes, copy the files back into this directory
by hand.

## macOS permissions

The desktop-audio source needs **Screen Recording** permission (System Settings →
Privacy & Security → Screen & System Audio Recording) and the mic needs
**Microphone** permission. macOS prompts on first use; Sequoia re-prompts for
screen recording periodically. If Track 2 goes silent, re-approve OBS there.

## Note on video

Both sources are audio-only, so the recording's video canvas is black (stock OBS
always produces a video container). Add a **macOS Screen Capture** (Display
Capture) source if you also want the screen — and mute its audio or leave it on
no tracks to avoid doubling desktop audio.
