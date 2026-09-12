# Plan — ceres acoustic + thermal characterisation

2026-09-10. Measure how loud ceres gets as CPU load and temperature rise,
using the A19 Bluetooth mic (setup: [`handover-a19-mic-testing.md`](handover-a19-mic-testing.md)),
and in the same run decide whether ceres's cooling is *broken* or merely
*configured loud*.

Two questions, deliberately kept apart:

- **Q1 (acoustic)** — how much does measured noise rise from idle to maximum
  sustained load, and is the rise broadband or tonal?
- **Q2 (thermal health)** — is ceres's die-to-air thermal path within spec for
  an i5-8500 in an OptiPlex 7060 Micro, or is there a contact/TIM/dust fault?

They are separate because a box can be perfectly cooled and still deafening
(aggressive fan curve), or quiet and thermally sick (throttling instead of
spinning up). The recon below already suggests ceres is the first kind.

## 0. What recon already established (2026-09-10, before any load)

| Fact | Value | Source |
|---|---|---|
| CPU | i5-8500, 6C/6T, 800–4100 MHz, `intel_pstate`/`powersave` | `lscpu` |
| Power limits | PL1 **65 W** (long_term), PL2 **103 W** (short_term) | `/sys/class/powercap/intel-rapl:0/constraint_*` |
| Tjmax / high | 100 °C crit, 82 °C high | `coretemp` |
| Fan | `dell_smm` `fan1_input`, **max 7100 RPM** | `/sys/class/hwmon/hwmon3` |
| Fan at idle | **2030 RPM, pinned** — did not move while pkg swung 34→41 °C | 5×1 s samples |
| Throttling, 20 d uptime | core 41×/134 ms; **package 819×/3651 ms total** | `/sys/devices/system/cpu/cpu0/thermal_throttle/` |
| Package idle temp | 34–41 °C | `coretemp temp1_input` |
| RAPL energy counter | root-only by default; **unlocked 2026-09-10**, `sudo -n` works here | §6 H1 (done) |
| Headset | connected, profile already `headset-head-unit` | `pactl list cards` |
| numpy | available on demand via `uv run --with numpy` (2.5.3) | verified |

Two conclusions to carry into the run:

1. **3.6 seconds of throttling in 20 days is not a thermal fault.** Whatever
   is wrong, it is not "the CPU is cooking".
2. **A fan that ignores a 7 °C package swing is on a floor, not a curve.**
   The prime suspect for the constant noise is a BIOS thermal profile, which
   no amount of paste-reseating will fix. §7.3 tests this directly and is the
   cheapest high-value rung in the whole plan — run it even if nothing else
   gets run.

## 0.5 First measurements — 2026-09-10, 65 W load probe

A 70 s probe (20 s idle → 35 s six-thread AVX2 matmul → cooldown) was run
before committing to the full ladder. RAPL was unlocked first (H1 — plain
`sudo` works non-interactively from an agent shell on ceres, so H1 is **done**,
not pending).

| t (s) | fan RPM | pkg °C | pkg W |
|---|---|---|---|
| 0–18 (idle) | **2031** | 35 | **1.3** |
| 21 | 2030 | 57 | 54.7 |
| 27 | 2033 | 65 | 62.4 |
| 36 | 2034 | 72 | 61.6 |
| 42 | 2042 | 75 | 65.6 |
| 45 | **2195** | 77 | 65.5 |
| 51 | 2524 | 80 | 65.8 |
| 55 (load ends) | 2691 | 79 | 25.5 |

Four results, none of which needed the microphone:

1. **The idle fan floor is confirmed and it is stark.** ceres idles at
   **1.3 W package power** and 35 °C, and spins its fan at 2031 RPM — 29 % of
   the 7100 RPM maximum. There is essentially nothing to cool. No thermal
   control loop produces that; it is a floor.
2. **The fan ignores temperature until ~75 °C.** RPM stayed within 12 of 2031
   as the package went 35 → 75 °C, and only began ramping past 75 °C. So the
   curve is not merely floored, it is *flat then late*: no proportional region
   at all across a 40 °C span.
3. **The load is a genuine power virus.** Package power pinned at 65.5–65.8 W
   — exactly PL1. The numpy/OpenBLAS rung saturates the package power limit,
   which is what the ladder needs, and confirms no install of `stress-ng` is
   required.
4. **The thermal path looks broadly healthy.** 35 → 57 °C within the first few
   seconds is the expected die-to-cold-plate step for a 64 W application, and
   the subsequent rise to 80 °C decelerated (75 → 77 → 79 → 80) rather than
   plateauing early. Rough steady-state resistance, assuming ~24 °C ambient
   and extrapolating: **θ ≈ 0.9–1.0 °C/W** — the top of the healthy band for
   this chassis class, not the >1.3 °C/W that indicates a fault. Confirm with a
   full-length S4 rung and a real ambient reading (H2).

**Read together, these say the noise complaint is a fan-curve problem, not a
cooling problem.** ceres is loud at idle because it is *configured* to spin at
2030 RPM while dissipating 1.3 W. H4 (the BIOS Thermal Management setting) is
now the highest-value remaining step, and it may be the entire fix.

## 0.6 The A19 headset is disqualified as an instrument

**Do not run the acoustic ladder with the A19.** Three tests, all negative:

| Test | Result |
|---|---|
| 1 kHz tone + loud speech from neptune | nothing above the floor — **but void**, see below |
| Fan ramp 2031 → 2772 RPM during the load probe | recorded level *fell* from −86.7 to −89.8 dBFS |
| Same, under CVSD instead of mSBC | identical dead floor (peak 5–15) |

The middle row is the decisive one. A 36 % fan-speed increase is plainly
audible to a human and must raise a microphone's level. The A19's level went
**down**. That is the signature of a noise gate / noise suppressor: the DSP
characterises steady broadband noise and subtracts it. HFP headset firmware
does this deliberately, and steady fan noise is precisely the thing it is
built to remove. The floor sat at peak 5–6 of 32768 (≈ −75 dBFS) with the
spectrum showing only 2000/4000/6000 Hz mSBC subband artifacts — codec noise,
not room sound.

This is consistent with the baselines in the mic handover rather than
contradicting them: a finger *tap* read 6794 because a transient passes a
noise gate. Steady noise does not. **A tap test therefore cannot qualify a mic
for this experiment** — the qualifying test is the fan-ramp test above.

Two process notes from the same session, both worth keeping:

- **Trap 1 is real and continuous capture defeats it.** The profile held
  `headset-head-unit` for the whole 53 s capture, and reverted to `a2dp-sink`
  once capture stopped. Verify the profile *during* capture; before or after
  tells you nothing.
- **The first smoke test was void for an unrelated reason: neptune's default
  output device is a pair of JBL Endurance Peak 4 earbuds.** The tone was
  played into earbuds in a case. Any use of neptune as a room sound source
  must first re-route its output to Built-in Output and confirm it by name —
  `system_profiler SPAudioDataType` and look for which device carries
  `Default Output Device: Yes`.

### Replacement instruments, best first

| Option | Pros | Cons / gating |
|---|---|---|
| **Android phone SPL meter app**, placed at a marked spot by ceres | direct dB(A), no gate, cheap, the number the complaint is actually about | not scriptable — a human reads it at each rung; pick an app that reports dB(A) and, if offered, disables audio processing |
| **Android phone recording an unprocessed WAV** | full spectrum, enables the blade-pass analysis (§4.3) | needs an app using the `UNPROCESSED`/`VOICE_RECOGNITION` source; many recorders apply NS and will fail the same way the A19 did |
| **neptune's built-in microphone**, 2 m away | 48 kHz, scriptable over ssh, repeatable, no Bluetooth | needs a recorder (`brew install ffmpeg`) and a one-time TCC mic approval at neptune's console; captures neptune's own fan too |
| USB measurement mic on ceres | best data | none on hand |

**Whichever is chosen, qualify it with the fan-ramp test before the full run:**
20 s idle, 35 s six-thread matmul, and confirm the recorded level *rises* as
`fan1_input` rises. Roughly 15 minutes to run, and it is the only test that
distinguishes a usable mic from a gated one.

## 0.7 The BIOS has no fan-profile setting — H4 is void

**You do not need to plug in a keyboard and monitor.** The Dell BIOS settings
are readable from Linux at runtime: `dell_wmi_sysman` is loaded and exposes
all 114 of this board's BIOS attributes under
`/sys/class/firmware-attributes/dell-wmi-sysman/attributes/`.

Enumerated 2026-09-10 on BIOS 1.24.0, OptiPlex 7060. Searching for
`fan|therm|acoust|cool|noise|perf` returns exactly **one** attribute:

| Attribute | current | default | possible |
|---|---|---|---|
| `FanCtrlOvrd` (Fan Control Override) | Disabled | Disabled | Disabled;Enabled |
| `DustFilter` | Disabled | Disabled | Disabled;15days;…;180days |
| `SpeedShift` / `TurboMode` / `CStatesCtrl` | Enabled | Enabled | — |

`FanCtrlOvrd` is a diagnostic that forces the fan to 100 %, not a curve
selector — and it is Disabled, consistent with the observed 2030 RPM rather
than 7100. `DustFilter` (which on some Dell firmware raises fan speed) is also
Disabled. Everything relevant sits at factory default.

**So the "someone set Ultra Performance" hypothesis is dead.** Thermal
Management / Fan Speed Control is a Latitude and Precision BIOS feature; the
OptiPlex 7060 desktop firmware does not expose a fan profile at all, in setup
or over WMI. There is no setting to change.

That leaves these explanations for a 2030 RPM floor at 1.3 W:

1. **The firmware floor simply is ~2030 RPM** for this chassis — a small
   blower held at a constant baseline. If so, the only fixes are physical:
   a quieter fan, or decoupling/relocating the box.
2. **BIOS 1.24.0 is not the latest.** Dell shipped later 7060 BIOS revisions
   and fan-behaviour changes are common in their release notes. Checking
   whether a newer BIOS alters the floor is cheap and is the one remaining
   software lever. `fwupdmgr` may be able to do it without a USB stick.
3. **Dust, or a worn bearing.** Fan noise at a *given* RPM is not a constant:
   a dust-loaded impeller or a worn sleeve bearing is markedly louder at the
   same 2030 RPM through turbulence and imbalance. This fits "crazy loud for
   what it is" better than anything else on the list, and it is a physical
   inspection, not a measurement (H3).
4. **The fan is tracking a non-CPU sensor.** `dell_smm` temp1–3 and the NVMe
   (32–40 °C) are candidates. The ladder's telemetry logs all of them, so if
   RPM correlates with NVMe rather than package temperature, the run will show
   it.

### Optional test: is the floor policy or hardware?

Writing `1` to `/sys/class/hwmon/hwmon3/pwm1_enable` and then `0` to `pwm1`
switches `dell_smm_hwmon` to manual control. If the fan then drops below
2030 RPM, the floor is firmware policy; if the write is refused or the RPM
does not move, it is a hardware/firmware minimum. Harmless at 1.3 W idle for a
30-second test, restoring `pwm1_enable=2` afterwards.

Not run here — the agent's permission classifier blocks hardware fan writes,
correctly. This is a human step if you want the answer, and note that
`dell_smm_hwmon` sometimes needs its `force=1` module parameter for fan
control on non-laptop models, which means reloading the module on a box with
running services.

## 0.8 Working instrument: neptune's built-in mic via a LaunchAgent

Solved 2026-09-10. The obstacle and the fix are both worth keeping, because
the failure mode is silent.

**An ssh-spawned process cannot reach the microphone on macOS.** `ffmpeg` run
over ssh enumerates the devices happily, exits 0, and writes a valid 510 KB
WAV in which **every sample is zero**. TCC denies the capture without an
error, and no prompt can appear because the ssh session has no GUI context.
This is the same class of trap as the A2DP silence trap and the headset noise
gate: a plausible file that passes every superficial check.

**The fix is a LaunchAgent in the Aqua session**, matching the precedent of
the codexbar collector and `smb-mount` agents already on neptune:

- `~/.local/bin/micrec` — reads `~/.micrec/request` (`"<seconds> <outpath>"`),
  records, writes the exit status to `~/.micrec/done`.
- `~/Library/LaunchAgents/com.github.ctaylor.micrec.plist` — `WatchPaths` on
  `~/.micrec/request`, `RunAtLoad` false. Bootstrap into `gui/$(id -u)`, not
  `system/`: the GUI domain is what gives the job a TCC identity.
- Trigger from ceres with
  `ssh neptune 'echo "300 ~/.micrec/out.wav" > ~/.micrec/request'`.

Verified: first triggered run returned peak 1179, rms 35.9, 55 % non-zero —
real room audio, versus the all-zero file the ssh route produced.

Two details that will bite if changed:

- **Address the device by name, `-i ":Built-in Microphone"`, never by index.**
  Enumeration on neptune returns `[0] JBL Endurance Peak 4`,
  `[1] Microsoft Teams Audio`, `[2] Built-in Microphone` — and those indices
  shift when the JBL earbuds connect or disconnect. An index would silently
  record the wrong microphone.
- **The head of the first capture is truncated** (1.39 s of a requested 6 s)
  while the device is authorised. Discard the first few seconds of any
  recording, and take duration from the WAV header rather than from `-t`.

### The qualifier every candidate mic must pass

Both rejected instruments produced files that looked fine. The only test that
separates a working mic from a convincing fake is whether its level tracks
something independently controlled:

> Record while the CPU goes idle → six-thread matmul → idle, and confirm the
> recorded level rises and falls **with `fan1_input`**.

A tap test does not qualify a mic — a transient passes a noise gate that
steady fan noise does not.

## 1. Instrumentation

Three streams, one clock. Everything lands in `~/scratch/ceres-acoustic/RUN/`.

| Stream | Tool | Rate |
|---|---|---|
| Telemetry (temps, RPM, freq, power, throttle) | `sample.py` (§2) | 5 Hz first 30 s of each rung, 1 Hz after |
| Audio | `pw-record` → 16 kHz mono s16 WAV | continuous |
| Rung marks | `marks.csv` written by the driver | per transition |

**Record audio continuously for the whole session, not per rung.** Trap 1 in
the mic handover — WirePlumber restores `a2dp-sink` whenever no capture stream
is active — means every gap is a chance to silently fall back into the
silence-producing profile. A single unbroken capture stream keeps the profile
pinned for free. Rung boundaries come from `marks.csv` timestamps in analysis.

Guard the one risk that creates (a mid-run Bluetooth dropout kills everything)
with a supervisor loop that restarts `pw-record` into `audio-NNN.wav` and
re-asserts the profile if it ever exits.

## 2. Telemetry sampler

`sample.py` — pure stdlib, no root needed except for the optional RAPL column.

```python
#!/usr/bin/env python3
"""1 Hz (5 Hz burst) CSV telemetry for ceres thermal/acoustic runs."""
import time, sys, glob, os

HW = "/sys/class/hwmon"
def hw(name):
    for d in glob.glob(HW + "/hwmon*"):
        if open(d + "/name").read().strip() == name:
            return d
    return None

CORE, SMM, ACPI, NVME = hw("coretemp"), hw("dell_smm"), hw("acpitz"), hw("nvme")
RAPL = "/sys/class/powercap/intel-rapl:0/energy_uj"
RAPL_MAX = "/sys/class/powercap/intel-rapl:0/max_energy_range_uj"
CPUS = sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq"))
THROT = "/sys/devices/system/cpu/cpu0/thermal_throttle/"

def rd(p, d=""):
    try:
        return open(p).read().strip()
    except OSError:
        return d

def rapl_ok():
    return rd(RAPL) != ""

cols = (["wall", "mono", "pkg_c"] + ["core%d_c" % i for i in range(6)]
        + ["fan_rpm", "smm1_c", "smm2_c", "smm3_c", "acpi_c", "nvme_c"]
        + ["cpu%d_khz" % i for i in range(len(CPUS))]
        + ["pkg_w", "core_throt", "pkg_throt", "pkg_throt_ms", "load1"])
print(",".join(cols), flush=True)

emax = int(rd(RAPL_MAX, "0") or 0)
prev_e, prev_t = None, None
t0 = time.monotonic()
while True:
    now, mono = time.time(), time.monotonic()
    # RAPL is a wrapping microjoule accumulator; differentiate it into watts.
    w = ""
    if rapl_ok():
        e = int(rd(RAPL, "0"))
        if prev_e is not None:
            de = e - prev_e
            if de < 0 and emax:
                de += emax            # counter wrapped
            dt = mono - prev_t
            if dt > 0:
                w = "%.2f" % (de / 1e6 / dt)
        prev_e, prev_t = e, mono
    row = [("%.3f" % now), ("%.3f" % (mono - t0)),
           rd(CORE + "/temp1_input", "0")]
    row += [rd(CORE + "/temp%d_input" % (i + 2), "0") for i in range(6)]
    row += [rd(SMM + "/fan1_input"), rd(SMM + "/temp1_input"),
            rd(SMM + "/temp2_input"), rd(SMM + "/temp3_input"),
            rd(ACPI + "/temp1_input"), rd(NVME + "/temp1_input")]
    row += [rd(p) for p in CPUS]
    row += [w, rd(THROT + "core_throttle_count"),
            rd(THROT + "package_throttle_count"),
            rd(THROT + "package_throttle_total_time_ms"),
            rd("/proc/loadavg").split()[0]]
    print(",".join(row), flush=True)
    # 5 Hz for the first 30 s of the process (the transient), 1 Hz after.
    time.sleep(0.2 if mono - t0 < 30 else 1.0)
```

Note the millidegree units: `coretemp`/`dell_smm` report `41000` for 41 °C.
Divide in analysis, not in the sampler — keep the raw values on disk.

The transient burst matters for §7.2: a 1 Hz sampler cannot resolve a die-to-
heatsink step, and that step is the single clearest fingerprint of a bad
thermal-interface contact.

## 3. Load ladder

`stress-ng` is **not installed** and installing it needs sudo. It is not
needed: everything below runs from what is already on the box.

The key design point is that **"100% CPU" is not one thing**. A shell busy
loop pegs all six cores at 100% utilisation and draws maybe half the power of
an AVX2 FMA loop doing the same nominal 100%. Power — not utilisation — is
what the heatsink and therefore the fan actually respond to. So the ladder
sweeps *power*, and includes one rung that deliberately decouples the two.

| Rung | Load | Threads | Duration | Purpose |
|---|---|---|---|---|
| S0 | idle, quiesced | 0 | 10 min | baseline + fan-floor probe (§7.3) |
| S1 | numpy matmul | 1 | 6 min | low power |
| S2 | numpy matmul | 2 | 6 min | |
| S3 | numpy matmul | 4 | 6 min | |
| S4 | numpy matmul | 6 | 8 min | **max power** (AVX2/FMA, ≈PL1) |
| S5 | shell busy loop | 6 | 6 min | 100% util, *low* power — the decoupler |
| S6 | `openssl speed` AES-NI | 6 | 6 min | mid power, different unit mix |
| S7 | numpy matmul | 6 | 6 min | repeat of S4 — drift/hysteresis check |
| S8 | idle | 0 | 15 min | cooldown curve → thermal time constant |

~70 min plus settling. Droppable if time is short: S2, S6, S7. **Not**
droppable: S0, S4, S5, S8.

Insert a 3-minute settle between rungs (load off, telemetry and audio still
running) so each rung starts from a comparable state and the decay between
rungs is itself usable data.

**Ascending order is a confounder** — the chassis soaks heat cumulatively, so
S4 starts warmer than S1 did. S7 (a literal repeat of S4 at the end of the
run) is the control that measures how large that drift is. If S7 and S4 differ
by more than ~2 °C steady-state, re-run the ladder in descending order.

### Load generators

```sh
# AVX2 / FMA power virus via OpenBLAS. N = thread count, D = seconds.
run_matmul() {  # run_matmul N D
  OMP_NUM_THREADS=$1 OPENBLAS_NUM_THREADS=$1 MKL_NUM_THREADS=$1 \
  uv run --quiet --with numpy python - "$2" <<'PY'
import numpy as np, sys, time
n = 2048
a = np.random.rand(n, n); b = np.random.rand(n, n)
end = time.time() + float(sys.argv[1])
while time.time() < end:
    c = a @ b
PY
}

# 100% utilisation, low power. One pinned busy loop per core.
run_busy() {  # run_busy N D
  pids=""
  i=0
  while [ "$i" -lt "$1" ]; do
    taskset -c "$i" sh -c 'while :; do :; done' &
    pids="$pids $!"
    i=$((i+1))
  done
  sleep "$2"
  kill $pids 2>/dev/null
}

# AES-NI, mid power.
run_aes() { openssl speed -multi "$1" -seconds "$2" -evp aes-256-gcm >/dev/null 2>&1; }
```

`(( i++ ))` is deliberately avoided in `run_busy` — under `set -e` the
arithmetic evaluates to the counter's *old* value, so the first increment
returns 0 and aborts the script. See the shell foot-gun table in `CLAUDE.md`.

Verify each rung actually landed: `run_matmul 6` should show `load1` climbing
to ~6 and `pkg_w` near 65 in the CSV. A rung that silently did nothing is the
classic way to get a beautifully plotted meaningless result.

## 4. Making the microphone trustworthy

This is the part most likely to quietly ruin the experiment, so it gets its
own controls.

### 4.1 The threat: the headset is not a measurement instrument

The A19 is a cheap Bluetooth headset running HFP/mSBC. Such devices routinely
apply, in the headset DSP and invisibly:

- **AGC** — gain rises when the room is quiet and falls when it is loud, which
  compresses exactly the idle-to-load difference we are trying to measure;
- **Noise suppression / a noise gate** — steady broadband fan noise is
  *precisely* what these are designed to remove;
- **A band-limited response** — HFP is roughly 50 Hz–7 kHz even at 16 kHz
  wideband, so the fan's shaft rate (34–118 Hz) may be attenuated.

A run that ignores this can produce the result "load barely changes the noise"
purely as an artifact of AGC. Three controls:

### 4.2 Control A — the calibration burst

At the **end of each rung**, before the load stops, play a fixed 1 kHz tone
from a phone at a fixed, marked position and volume for 5 seconds. Log the
time in `marks.csv`.

The tone level as recorded is a per-rung measurement of the mic's *current
gain*. If the tone reads the same dBFS in S0 and S4, there is no AGC and raw
levels are comparable. If the tone level falls as the fan gets louder, that
difference is the AGC gain reduction, and every rung's fan level gets it added
back before comparison.

A burst rather than a continuous tone: continuous would contaminate the
broadband measurement for the whole rung.

### 4.3 Control B — the blade-pass frequency

We know the fan RPM exactly, every second. A centrifugal fan radiates a strong
tone at

    f_BPF = (RPM / 60) x blade_count

with harmonics. At 2030 RPM and a typical 9-blade impeller that is ~305 Hz; at
7100 RPM, ~1065 Hz — both comfortably inside the HFP passband.

So: take the spectrum of the S0 recording, find the dominant low peak, divide
by (RPM/60), and check that it lands on an integer. That integer is the blade
count. Then verify at every other rung that the peak has moved to exactly
`blade_count x RPM/60` for that rung's measured RPM.

If the peak tracks RPM, **the mic is provably hearing this specific fan** —
not the neighbouring boxes, not the room, not codec noise. That converts the
whole acoustic dataset from suggestive to attributable, and it costs nothing
but analysis.

### 4.4 Control C — absolute level, if available

A phone SPL-meter app is ±3 dB absolute but reliable in *relative* terms.
Taking a spot reading at S0, S4 and S5, at the same marked position as the
headset, anchors dBFS to approximate dB(A) SPL and independently cross-checks
the AGC finding. Without it, report dBFS deltas relative to idle only, and say
so explicitly — an uncalibrated mic cannot produce absolute dB SPL and any
number claiming otherwise is fabricated.

### 4.5 Physical setup rules

- Mark the headset's position and orientation with tape; **do not move it
  once the run starts** — nor at any point during the calibration bursts.
- Place it at a fixed distance (30 cm suggested) from ceres's exhaust vent,
  off the desk surface if possible (a hard surface adds a reflection notch).
- The office has other boxes with fans (makemake, neptune, eris). They are in
  every recording. Keep them at constant, idle load throughout, and record a
  60 s "ceres powered down or fully idle" reference if practical. Control B is
  the real defence here: their fans run at different RPM, so their tones sit
  at different frequencies and are separable.
- Battery: the headset must be charged; a mid-run low-battery beep or gain
  change is a plausible failure. Check level before starting.
- Verify every 10 minutes that the recording is still live and non-silent
  (per-second peak check from §4 of the mic handover). A stalled capture that
  is discovered at the end costs the whole session.

## 5. Analysis

Slice the WAV by `marks.csv`, discarding the first and last 30 s of each rung
(transients and the calibration burst).

Per rung, compute:

| Metric | Why |
|---|---|
| L_eq, unweighted (dBFS) | raw energy |
| L_A, A-weighted (dBFS) | correlates with perceived loudness; implement the IEC 61672 A-curve analytically in the frequency domain — no scipy needed |
| L10 / L50 / L90 | L90 is the steady fan floor with transients removed |
| 1/3-octave band levels, 25 Hz–8 kHz | *where* the noise is |
| BPF tone level and tone-to-noise ratio | see below |
| BPF frequency vs `blade_count x RPM/60` | Control B validation |
| Calibration-burst level | Control A gain correction |

Paired with the telemetry means (steady-state window only):
mean/max package temp, per-core spread, mean fan RPM, mean package watts, mean
frequency, throttle-count delta.

Plots worth producing:

1. **fan RPM vs package watts** — the actual fan curve, empirically.
2. **package temp vs package watts** — the thermal-resistance line (§7.1).
3. **L_A vs fan RPM** — fit `L = a + b log10(RPM)`. Broadband fan noise
   normally follows b ~ 50. A markedly steeper fit means something resonates.
4. **L_A vs package watts** — the answer to the question as asked.
5. Spectrogram of the whole session with RPM overlaid — the single most
   informative picture, and it makes Control B visible at a glance.

**Report tone-to-noise ratio, not just dB.** Perceived annoyance is dominated
by tonality: a 300 Hz whine at 45 dB is far more irritating than 50 dB of
broadband hiss. "Crazy loud for what it is" is much more often a tonality
complaint than a level complaint, and the fix differs — a tonal problem can be
a resonance, a mount, or an obstructed vent, none of which show up in a
single dB number.

## 6. Human-gated steps

Everything below needs a human; the agent cannot do them.

| # | Step | Why it matters |
|---|---|---|
| H1 | `sudo chmod a+r /sys/class/powercap/intel-rapl:0/energy_uj` | **Highest value single step.** Without package watts, Q2 is unanswerable — there is no thermal resistance without a numerator. Non-persistent (resets at reboot), which suits a temporary experiment. |
| H2 | Measure and record room ambient air temperature | `acpitz` (27.8 °C at idle) is a board sensor, not ambient, and using it inflates the thermal-resistance figure. A cheap thermometer near the intake is enough. |
| H3 | Look at the box: vents clear? standing in free air? visible dust in the heatsink fins? | Answers half of Q2 for free before any measurement. |
| ~~H4~~ | ~~Reboot to BIOS and read the fan profile~~ | **Void — see §0.7.** All BIOS attributes were read from Linux via `dell-wmi-sysman`; this board exposes no fan-profile setting and everything is at default. No console trip needed. |
| H5 | Phone with a tone generator and, ideally, an SPL app | Controls A and C (§4.2, §4.4). |
| H6 | Quiesce background load | See §8. |

H1 and H2 are prerequisites for §7.1. H4 may make the rest moot — if the
answer is "someone set Ultra Performance", the fix is one BIOS toggle.

## 7. Q2 — is the cooling actually faulty?

Three independent tests. They do not depend on each other, so a failure to run
one does not invalidate the others.

### 7.1 Steady-state thermal resistance

    theta = (T_package_steady - T_ambient) / P_package

taken at S4 (max sustained power, temperature flat). Rough expectations for an
i5-8500 under the stock OptiPlex Micro cooler:

| theta | Reading |
|---|---|
| 0.7–1.0 °C/W | healthy for this chassis class |
| 1.0–1.3 °C/W | marginal — dust, or aged TIM |
| > 1.3 °C/W | genuine fault: bad mount, pumped-out paste, blocked fins |

Concretely: at 65 W and 22 °C ambient, healthy lands the package around
68–87 °C. If S4 sits near 95 °C and starts throttling, theta is bad. If S4
settles in the seventies with the fan screaming at 5000+ RPM, the thermal path
is *fine* and the fan curve is simply aggressive — which is the outcome the
recon data points toward.

Requires H1 and H2.

### 7.2 Transient step response — the contact test

This is the test that most directly probes the *interface* rather than the
whole path, and it needs no power measurement at all.

At the S3→S4 transition, with the sampler in its 5 Hz burst, fit the package
temperature to a two-term rise:

    T(t) = T_inf - A1 exp(-t/tau1) - A2 exp(-t/tau2)

- **Healthy**: the fast term is small (a few °C; die-to-IHS-to-cold-plate is
  low resistance) and the rise is dominated by `tau2` of roughly 60–180 s as
  the heatsink mass soaks.
- **Bad contact or pumped-out TIM**: a large near-instant jump — 15–25 °C
  inside the first second or two — because the die is thermally isolated from
  a heatsink that is still cold, followed by a comparatively flat plateau.

The shape is diagnostic even though the absolute numbers are not. It is why
the sampler bursts at 5 Hz: at 1 Hz the fast term is one sample wide and
unfittable.

The S8 cooldown gives the same time constant from the other direction, from a
known starting point, with no load and no power measurement — a free
cross-check on `tau2`.

### 7.3 The fan-floor probe

During S0 and S8, with the box genuinely quiesced, watch whether `fan_rpm`
ever leaves 2030.

- **It never does** → the fan has a floor. The constant office noise is a
  configuration choice (H4), not heat, and no thermal repair will change it.
  This is currently the leading hypothesis and the recon supports it.
- **It drops toward zero when the box is truly cold** → 2030 RPM at 37 °C is a
  *response* to something, and the next question is which sensor the BIOS is
  reacting to. Watch `nvme_c` in particular: the NVMe sits at 32–40 °C, and
  some Dell firmware ties the chassis fan to drive temperature. If RPM tracks
  NVMe temp rather than CPU temp, that is the answer, and it also explains why
  the fan ignores CPU swings.

### 7.4 On comparing with neptune

Neptune has the same i5-8500 and is quiet — but it is a 2019 iMac, with
roughly an order of magnitude more heatsink volume and a large slow fan. **A
loudness comparison between them is not evidence of a fault in ceres**; a 1L
Micro moving 65 W must spin a small fan fast, and small-and-fast is loud for
unavoidable geometric reasons. Expect ceres to lose that comparison even in
perfect health.

The comparison that *is* fair is `theta` (§7.1) and the step response (§7.2),
both of which normalise out chassis size. Running the same numpy matmul load
on neptune and capturing die temperature, package power and fan RPM
(`sudo powermetrics --samplers smc,cpu_power` on macOS) yields a genuine
apples-to-apples thermal-resistance number for the identical silicon. That is
worth doing, and it is the only form in which the neptune comparison carries
information.

## 8. Confounders and controls

| Confounder | Control |
|---|---|
| Background load — `clickhouse-server`, `llama-server`, Paseo daemon, other agent sessions, Samba, syncthing all seen running during recon | Stop or pause what can be stopped (H6); record what cannot. `llama-server` in particular can spike to full load and silently corrupt a rung. Cross-check every rung against the `load1` column. |
| Cumulative chassis heat soak across the ladder | S7 repeats S4; if they diverge >2 °C, re-run descending |
| Other boxes' fans in the recording | Keep them at constant idle; rely on Control B (§4.3) to attribute tones by frequency |
| AGC / noise suppression in the headset | Control A (§4.2) |
| Mic or box moved mid-run | Tape marks; note any disturbance in `marks.csv` |
| Bluetooth dropout | Supervisor restarts capture; periodic liveness check |
| WirePlumber reverting to `a2dp-sink` (silent WAV) | Continuous capture keeps the stream alive; re-assert profile on any restart; verify the active profile, never `pactl list sources` |
| Ambient room temperature drifting over 70 min | Record ambient at start and end (H2); a >2 °C drift needs noting in the theta calculation |
| `pw-record` overrunning `timeout` | Take duration from the WAV header, not the wall clock |

## 9. Deliverables

- `~/scratch/ceres-acoustic/RUN/` — raw CSV, WAVs, marks. **Not** committed;
  the WAVs are ~170 MB and are room recordings.
- `docs/ceres-acoustics.md` — findings: the empirical fan curve, the noise-vs-
  load numbers with their calibration caveats, the theta figure, the verdict
  on Q2, and the recommended action.
- Scripts stay in the scratch directory for now, matching the precedent set by
  the mic setup: nothing about this experiment gets deployed. If the sampler
  proves reusable it can be promoted to `scripts/` later — at which point the
  shell parts must pass the dual-shell gate (`scripts/tests/shell-syntax-gate.sh`)
  and the bash 3.2 floor. Writing the sampler in Python sidesteps that
  entirely, which is part of why it is Python.

## 10. Teardown

- Revert H1 if the box is not rebooted: `sudo chmod 400 /sys/class/powercap/intel-rapl:0/energy_uj`
- Restart anything stopped for H6.
- Mic teardown per §5 of [`handover-a19-mic-testing.md`](handover-a19-mic-testing.md).
- Delete the WAVs once the analysis numbers are extracted.

## 11. Order of execution

1. H3, H4, H2 — the cheap physical/BIOS observations, *before* any measuring.
   H4 alone may answer the question.
2. H1, H6 — enable power measurement, quiesce the box.
3. §7.3 fan-floor probe (10 min idle). If the fan is on a floor, that is the
   headline result and the ladder becomes supporting evidence rather than the
   main event.
4. Mic setup and a 60 s smoke recording; verify non-silence *and* run Control B
   on it to establish blade count before committing to a 70-minute run.
5. Full ladder (§3) with continuous capture.
6. Analysis (§5), then §7.1 and §7.2.
7. Optional neptune counterpart run (§7.4).
