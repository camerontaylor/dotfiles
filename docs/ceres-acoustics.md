# ceres: noise, heat and the 65 W wall

Measured 2026-09-10. Method and instrument notes:
[`plans/handover-ceres-acoustic-thermal.md`](../plans/handover-ceres-acoustic-thermal.md).

Question: ceres is loud under load — is that a cooling fault, or is the box
merely configured badly? Answer: **both.** The cooling fault was a dust-clogged
heatsink, fixed the same evening (see the post-clean re-test). The
configuration half — running a 65 W part flat out for work that has no
deadline — is still there, and a power cap addresses it.

## Summary

- **Before cleaning**, at 65 W ceres ran the fan at **96–98 % of maximum**
  (6,800 of 7,100 RPM) and still sat at **91–96 °C in an 18–20 °C room**,
  θ ≈ 1.1–1.25 °C/W, with no cooling headroom — the response to more heat was
  throttling. **After cleaning**: 5,025 RPM, 86 °C, zero throttling.
  Everything below the post-clean section describes the *dusty* state.
- **Capping package power to 25 W makes ceres as quiet as idle** — at the room
  noise floor — while retaining **69 % of full compute** and running 1.8× more
  efficiently. 45 W keeps 88.5 % of compute and is 10 dB(A) quieter than stock.
- The NVMe upgrade is **not** implicated. Fan speed tracks CPU temperature
  (r = +0.82) and ignores drive temperature entirely.
- **It was dust.** Cleaning the heatsink dropped full-load fan speed from 6,781
  to 5,025 RPM at identical power and eliminated throttling — see the post-clean
  re-test below.

## The load ladder

Ambient 19 °C. Package power from `intel-rapl`, fan RPM from `dell_smm`.

| rung | pkg W | pkg °C mean/max | fan RPM mean/max | θ °C/W | throttle events |
|---|---|---|---|---|---|
| idle | 1.6 | 34 / 49 | 2,057 / 2,061 | — | 0 |
| matmul 1 thread | 21.2 | 77 / 85 | 2,639 / 3,006 | 2.73 | 0 |
| matmul 2 threads | 35.5 | 85 / 87 | 4,277 / 4,603 | 1.85 | 0 |
| matmul 4 threads | 63.5 | **96 / 99** | 6,742 / 6,949 | 1.21 | **1,202** |
| matmul 6 threads | 64.9 | 91 / 96 | 6,781 / 6,931 | 1.11 | 14 |
| shell busy loop 6× | 64.9 | 93 / 98 | 6,741 / 6,949 | 1.14 | — |
| AES-NI 6 threads | 60.8 | 89 / 91 | 6,588 / 6,940 | 1.16 | — |

Three things fall out.

**There is no quiet way to be busy.** Every all-core workload — AVX2 matmul,
AES-NI, and a do-nothing shell loop — landed within 4 W of each other at
61–65 W, within 4 °C at 89–93 °C, with the fan at 96–98 %. The governor takes
any all-core load to maximum turbo, so "CPU busy" is degenerate with "65 W" and
therefore with "maximum fan". This is why fan noise is such a reliable load
indicator on this box — and it is exactly what a power cap breaks.

**Four threads run hotter than six** — 96 °C vs 91 °C at identical power, and
1,202 throttle events vs 14. Package temperature is the hottest *core*; six
threads drop the clock to 3,506 MHz and spread the same 65 W over six cores at
lower voltage instead of concentrating it in four at 3,825 MHz.

**Even one busy core is audible.** A single thread — 21 W — already means
77 °C and 2,639 RPM.

### Throttling in context

ceres accumulated 819 package-throttle events in the 20 days of uptime before
this run. **The 4-thread rung alone added 1,202 in about two minutes.** The
low historical count means nothing had pushed the box hard, not that it copes.

## Noise vs fan speed

From the cooldown sweep — fan spinning down from 6,900 to 2,030 RPM with the
CPU idle, so nothing else varies. Neptune's built-in mic at ~2 m; levels are
dBFS, **relative only** (see "What these numbers are not").

| fan RPM | L_A (dBFS) |
|---|---|
| 2,045 (idle floor) | −99.5 |
| 3,336 | −96.4 |
| 4,900 | −92.3 |
| 6,924 | −73.4 |

**24.7 dB(A) between idle and full fan.** The fit is
`L_A = 42.3·log10(RPM)`, close to the ~50 canonical for broadband fan noise —
so there is no anomalous resonance in the noise law itself.

Spectrally, the fan's contribution at full speed is **+24 to +32 dB across
125–500 Hz**, tapering to +5 dB by 3 kHz — a low-frequency roar, not a whine.

Caveat: the cooldown points disagree with the steady-state PL1 points below by
5–9 dB at comparable RPM. The cooldown captures span a rapidly decelerating
fan, so their RPM pairing is smeared. **Trust the PL1 table for absolute
comparisons and this one only for the shape.**

## The power cap — the actionable result

Six-thread AVX2 matmul, 5 minutes per cap, throughput measured directly.

| PL1 | GFLOPS | % of full | pkg °C | fan RPM | L_A dBFS | GFLOPS/W |
|---|---|---|---|---|---|---|
| **65 W** (default) | 221.1 | 100 % | 91.9 | 6,800 | −77.4 | 3.40 |
| **45 W** | 195.7 | 88.5 % | 85.3 | 4,564 | −87.6 | 4.35 |
| 35 W | 167.6 | 75.8 % | 83.0 | 3,526 | −87.9 | 4.80 |
| **25 W** | 153.5 | 69.4 % | 77.5 | 2,701 | −99.9 | 6.15 |
| 15 W | 108.9 | 49.3 % | 68.3 | 2,049 | −99.8 | 7.28 |

- **25 W is acoustically indistinguishable from idle** (−99.9 vs −99.5 dBFS)
  and keeps 69 % of compute at 1.8× the efficiency.
- **45 W is the "still fast" option**: 88.5 % of compute, 10 dB(A) quieter.
- **35 W is dominated** — 12.7 % slower than 45 W for 0.3 dB. Skip it.
- Only the 65 W rung throttled at all.

**This is the worst case.** Matmul saturates the power limit continuously; for
compilation, I/O and general service load — which rarely hold all six cores at
maximum turbo — a given cap costs proportionally less than the table shows.

### Applying a cap

    # temporary, resets at reboot
    sudo sh -c 'echo 25000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw'

For persistence this wants a small systemd unit re-applying it at boot — a
host-specific quirk, so a host-scoped fragment plus a manifest entry per the
repo's placement rules. Not yet written.

## What was ruled out

**The BIOS.** All 114 attributes were read from Linux via `dell-wmi-sysman`
(`/sys/class/firmware-attributes/dell-wmi-sysman/attributes/`) — no console
trip needed. This board exposes **no fan-profile setting at all**; Thermal
Management is a Latitude/Precision feature, not an OptiPlex 7060 one.
`FanCtrlOvrd` and `DustFilter` are both Disabled, everything at factory
default. BIOS 1.24.0.

**The NVMe upgrade.** Fan RPM correlates with `dell_smm` temp1 (the CPU
sensor) at **r = +0.82** and with NVMe temperature at **−0.22**. The decisive
evidence came from the read-storm rung: after the storm stopped, the CPU fell
to 2 W and the fan returned to its 2,042 RPM floor **while the drive was at its
hottest of the whole run** (56.9 °C, 13 °C above baseline). Drive temperature
does not enter the fan table. The drive also never got hot — peak 61.9 °C on
its controller sensor against an 83.8 °C warning threshold.

*But:* saturating the NVMe costs **43 W of CPU** (memory bandwidth and
interrupt work) and drives the fan to ~4,500 RPM. Heavy file serving does make
ceres loud — via CPU, not via the drive.

**The idle fan floor**, as an explanation for the complaint. ceres idles at
1.3 W and pins the fan at 2,030 RPM — which looks pathological, and the fan
ignores CPU temperature entirely from 35 °C to 75 °C before responding. But at
2,045 RPM the measured level is −99.5 dBFS, i.e. the room floor. The floor is
odd; it is not what anyone is hearing.

## Unresolved: degraded, or marginal by design?

Evidence is genuinely mixed and no conclusion is drawn here.

- **Load step:** +24.7 °C within one second of applying 65 W ≈ 0.38 °C/W for
  the die-to-coldplate path. High side, not damning.
- **Cooldown:** 69 → 53 °C in 30 s with the fan still at 5,023 RPM. Fast,
  arguing against a badly clogged fin stack — but most of that is the die
  relaxing into the heatsink, not the heatsink dumping to air, so it doesn't
  settle it either.
- **Steady state:** 65 W, fan at 96 %, 91 °C in a 19 °C room.

A 1L chassis with a 65 W part is marginal by construction, so "always was this
way" is a live hypothesis. **The honest reference is ceres itself:** clean and
repaste, then re-run the ladder and compare. That is ~20 minutes now the
scripts exist, and the before/after would be unambiguous.

An untried test: writing `1` to `hwmon/pwm1_enable` then `0` to `pwm1` puts
`dell_smm_hwmon` in manual mode. If the fan then drops below 2,030 RPM the
floor is firmware policy rather than a hardware minimum. May need the driver's
`force=1` parameter, which means reloading a module on a box running services.

## What these numbers are not

**dBFS, not dB SPL.** No calibrated sound level meter was used, so all levels
are relative. Differences between rows are meaningful; the absolute values are
not, and must not be quoted as loudness figures.

Neptune's built-in microphone sat ~2 m away and hears its own fan too. That
contribution is constant across rungs and cancels in the differences.

## Instrument notes (three traps, all silent)

Each of these produces a plausible file that passes every superficial check.

1. **A Bluetooth headset mic is useless for steady noise.** The A19's level
   *fell* 3 dB as ceres's fan went 2,031 → 2,772 RPM: HFP firmware runs noise
   suppression, and steady fan noise is exactly what it removes. A tap test
   does not qualify a mic — a transient passes a gate that broadband does not.
2. **An ssh-spawned process cannot reach a microphone on macOS.** TCC denies it
   silently: `ffmpeg` exits 0 and writes a full-length WAV of pure zeros. Fix
   is a LaunchAgent in the Aqua session (`com.github.ctaylor.micrec`), which
   has a TCC identity and can prompt.
3. **CoreAudio's declared sample rate can be a lie.** With the JBL earbuds
   connected, neptune's built-in mic advertised 48 kHz and delivered ~7,700 —
   so the WAV header claimed a duration six times the true one and every
   timeline looked compressed. Each capture now keeps its own ffmpeg log; the
   true rate is frames ÷ the reported elapsed time. The rate is not stable
   between captures, so **tone identification is unreliable** and no
   blade-pass frequency is claimed here.

Also: address avfoundation devices by **name**, never index — indices shift
when the earbuds connect. And check neptune's default *output* device before
using it as a sound source; it defaults to the earbuds, which voided one test.

## Repro

Scripts in `~/scratch/ceres-acoustic/` (scratch, not deployed):
`sampler.py`, `ladder.sh`, `nvme_rung.sh`, `pl1_sweep.sh`, `capture_loop.sh`,
`analyse_sweep.py`. Raw data under `run-20260910-191814/`.

One bug to fix before re-running: `openssl speed -seconds N` applies **per
block size**, so the AES rung ran 25 minutes instead of 5.

## Post-clean re-test — 2026-09-10 23:09 (it was dust)

Heatsink and fan cleaned (no repaste). Same 6-thread AVX2 rung, same 64.9 W.

| metric | before | **after** | change |
|---|---|---|---|
| package temp mean / max | 91.3 / 96 °C | **86.1 / 91 °C** | −5.2 °C |
| fan mean / max | 6,781 / 6,931 rpm | **5,025 / 5,207 rpm** | **−1,756 rpm** |
| fan as % of 7,100 max | 96 % | **71 %** | 25 pts headroom recovered |
| θ (19 °C ambient) | 1.11 °C/W | **1.03 °C/W** | −7 % |
| throttle events in rung | 14 | **0** | eliminated |
| all-core clock | 3,506 MHz | 3,537 MHz | +31 MHz |
| idle fan / temp | 2,057 rpm / 34.4 °C | 1,911 rpm / 32.7 °C | −146 rpm |

**The cooler now does the same job with 26 % less airflow.** Improving θ while
*reducing* airflow means the fin-to-air path improved — the signature of
removing dust. Estimated ~7–8 dB(A) quieter at full load, interpolated from the
fan-speed/level curve above (not re-measured acoustically).

**The paste is fine.** The first-second load step — die-to-coldplate coupling,
which thermal interface material governs — is unchanged within sampling noise
(+19.9 to +26.9 °C, vs +24.7 °C before). The interface did not change; the heat
rejection did. This resolves the "degraded or marginal by design" question left
open above: **it was dust.**

Caveats: run was ~3 h later and idle package temp was 1.7 °C lower, so some of
the 5.2 °C is a cooler room; the box had rebooted 90 s earlier so background
load differed. Neither affects the RPM result, which is the robust one.

Note the 2,030 RPM "idle floor" was not a fixed floor — post-clean idle is
1,911 RPM. Also `energy_uj` reverts to root-only across a reboot; re-run
`sudo chmod a+r` before any repeat measurement.

Method: `~/scratch/ceres-acoustic/quicktest.sh`, data in `postclean-*/`.

## How much of disk-I/O CPU cost is zstd?

Measured 2026-09-10 on the same box. Root is `compress=zstd:3`; the control is
a `chattr +C` directory, where NOCOW disables compression entirely. 6 GiB per
arm from a tmpfs source (so the source read costs nothing), `sync` inside the
timing window, page cache dropped between arms. Energy from `intel-rapl`,
reported above the measured 1.7 W idle floor.

"Compressible" is 1 GiB of ceres's own XML (1.62× under zstd:3 — realistic for
text, not an artificial extreme); "random" is `/dev/urandom`.

| operation | data | total J/GiB | other work | **zstd** | zstd share |
|---|---|---|---|---|---|
| write | compressible | 21.6 | 7.6 | **14.0** | **65 %** |
| write | random | 9.7 | 8.8 | 0.9 | ~10 % |
| read | compressible | 9.1 | 4.0 | **5.1** | **56 %** |
| read | random | 5.2 | 4.2 | 1.0 | ~19 % |

**On compressible data zstd is the majority of the cost** — about two-thirds of
write CPU and just over half of read CPU. Everything else (checksums, the block
layer, btrfs metadata, the copy itself) is the remainder.

**On incompressible data the tax is ≲1 J/GiB.** btrfs samples the leading
blocks, sees the data will not compress, and abandons the attempt. Note the
random-read arm shows the same ~1 J/GiB difference even though `compsize`
confirms that file was stored *uncompressed* — nothing there to decompress. So
~1 J/GiB is the resolution floor of this method (COW vs NOCOW metadata
differences and run-to-run scatter), and the honest reading of both random rows
is "at or below what this can resolve", not a real 10–19 % cost.

Two consequences for ceres specifically:

- **Its bulk write traffic is largely incompressible** — Samba downloads,
  immich JPEGs, restic packs — so it pays almost no zstd tax and gains almost
  nothing. The traffic where zstd costs 65 % is the smaller share: logs,
  clickhouse, source trees.
- **Compression trades CPU energy for wall-clock and write endurance.** The
  compressed write finished *faster* (3.53 s vs 5.01 s) despite burning more
  CPU, because it pushed only 62 % as many bytes to the drive. On a box that is
  thermally saturated that is the wrong direction for noise and the right one
  for the SSD.

Caveat: arms ran 2.3–5.0 s each. The compressible splits are far larger than
the scatter; the random ones are not.

Method: `~/scratch/ceres-acoustic/ziptest.sh`.
