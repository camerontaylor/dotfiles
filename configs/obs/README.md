# OBS two-track audio recording

Reproducible OBS Studio setup for **two-track recording**:

| Track | Source | OBS object |
|-------|--------|-----------|
| **1 — Mic** | default audio input | `Mic/Aux` global device (`coreaudio_input_capture`), `mixers=1` |
| **2 — Desktop** | all system/app audio | `Desktop Audio` source (`sck_audio_capture`, ScreenCaptureKit, `type=0`), `mixers=2` |

Recording output is **Advanced** mode with `RecTracks=3` (records tracks 1 and 2
as separate tracks in one file). Files land in `~/Movies`.

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
