# pluto — quiet EC fan curve (MSI GS60 2QE)

Host-specific, **human-run, root-required**. pluto's stock EC fan curve spins the
CPU blower at ~3300 RPM permanently whenever the machine is awake. This replaces
the low end of that curve so the fan is **fully off at idle**, leaving load
behaviour untouched.

Not a deploy fragment: per [`CLAUDE.md`](../CLAUDE.md) root steps stay human-run,
and this needs Secure Boot disabled in firmware first. Promoting it to a
pluto-scoped fragment (precedent: `08_offload_home.zsh`) remains an open question.

## Why these numbers (measured 2026-09-10, not guessed)

- The blower has a **hard minimum sustainable speed of ~2990 RPM**. Duty 10 %,
  22 % and 30 % all yield exactly 2987 RPM. Only duty **0** stops it. There is no
  quiet-but-spinning mode — do not linearly extrapolate RPM from duty.
  Measured: `0→0, 10→2987, 30→2987, 60→3621, 90→5370` RPM.
- **Idle needs no airflow at all.** With the fan off for 5 min the package held
  48–57 °C (brief 65 °C spikes under container load), never near the 80 °C abort.
  The stock 48 % floor at 47 °C was spinning for no thermal reason.
- Load is deliberately left at stock: 90 °C → 76 % → ~4600 RPM, which plateaus at
  **89–90 °C under 8-thread stress-ng — identical to the stock curve.**

| | temps (°C) | duties (%) |
|---|---|---|
| Stock | 47 60 70 80 90 95 105 | 48 55 62 69 76 84 91 |
| Quiet (applied) | 47 60 **82 86** 90 95 105 | **0 0 30 55** 76 84 91 |

Entry 2 at 75 °C caused audible on/off cycling on container temp spikes; **82 °C
is the deadband that stopped it.** The EC's control temperature is *not* the
coretemp package reading — at 49 °C package it selected the 60–70 °C entry, i.e.
it runs 10–20 °C hotter or heavily hysteretic. **Tune by watching which entry
goes live at `0x71`, never by CPU temp.**

## Prerequisite: Secure Boot must be OFF

Secure Boot forces kernel lockdown `[integrity]`, which refuses the module
parameter: `Lockdown: modprobe: unsafe module parameters is restricted`. Without
it the EC is read-only and this cannot work.

It is a firmware setting and survives an OS reinstall, but a **fully drained
battery resets firmware NVRAM and turns Secure Boot back on** — that is how it
got re-enabled before. Verify with `mokutil --sb-state`.

To get into firmware setup: **tap `Delete` at power-on** (`F2` fallback, `F11` is
the boot menu). `systemctl reboot --firmware-setup` **does not work** — this AMI
firmware advertises `BOOT_TO_FW_UI` in `OsIndicationsSupported` but returns EIO
when asked to create `OsIndications`. Secure Boot lives under the Security tab.

## Rebuild after an OS reinstall

The EC map is hardware, so it is unaffected by reinstalling or moving to a
different disk. Only these OS-side files are lost. Run all of this as root.

```bash
# 1. module: allow EC writes, and load it at boot
echo "options ec_sys write_support=1" > /etc/modprobe.d/ec_sys.conf
echo "ec_sys"                        > /etc/modules-load.d/ec_sys.conf

# 2. the curve tool
cat > /usr/local/sbin/msi-fan-curve <<'SCRIPT'
#!/bin/bash
# msi-fan-curve - quiet zero-RPM-idle EC fan curve for the MSI GS60 2QE (pluto).
# Requires Secure Boot OFF (kernel lockdown blocks ec_sys write_support=1).
set -eu
IO=/sys/kernel/debug/ec/ec0/io
TEMPS_QUIET="47 60 82 86 90 95 105"; DUTY_QUIET="0 0 30 55 76 84 91"
TEMPS_STOCK="47 60 70 80 90 95 105"; DUTY_STOCK="48 55 62 69 76 84 91"
ecset(){ printf "\\x$(printf "%02x" "$2")" | dd of="$IO" bs=1 seek="$1" count=1 conv=notrunc 2>/dev/null; }
ecget(){ dd if="$IO" bs=1 skip="$1" count=1 2>/dev/null | od -A n -t u1 | tr -d " "; }
# hwmon numbering is not stable across installs - find coretemp by name
pkgtemp(){ for h in /sys/class/hwmon/hwmon*; do
             if [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ]; then
               echo $(( $(cat "$h/temp1_input")/1000 )); return
             fi
           done; echo 0; }
write_curve(){
  i=0; for v in $1; do ecset $((0x6a+i)) "$v"; i=$((i+1)); done
  i=0; for v in $2; do ecset $((0x72+i)) "$v"; i=$((i+1)); done
}
[ -w "$IO" ] || { echo "EC not writable (Secure Boot on, or ec_sys lacks write_support=1)" >&2; exit 1; }
case "${1:-apply}" in
  apply)   write_curve "$TEMPS_QUIET" "$DUTY_QUIET"; echo "quiet curve applied" ;;
  restore) write_curve "$TEMPS_STOCK" "$DUTY_STOCK"; echo "stock curve restored" ;;
  show)
    a=$(dd if="$IO" bs=1 skip=204 count=2 2>/dev/null | od -A n -t u1); set -- $a
    r=$(($1*256+$2)); rp=0; [ "$r" -gt 0 ] && rp=$((478000/r))
    echo -n "temps:  "; dd if="$IO" bs=1 skip=$((0x6a)) count=7 2>/dev/null | od -A n -t u1
    echo -n "duties: "; dd if="$IO" bs=1 skip=$((0x72)) count=7 2>/dev/null | od -A n -t u1
    echo "live: duty=$(ecget $((0x71)))% rpm=${rp} pkg=$(pkgtemp)C" ;;
  *) echo "usage: msi-fan-curve [apply|restore|show]" >&2; exit 2 ;;
esac
SCRIPT
chmod +x /usr/local/sbin/msi-fan-curve

# 3. apply at boot
cat > /etc/systemd/system/msi-fan-curve.service <<'UNIT'
[Unit]
Description=MSI GS60 quiet fan curve (EC)
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/modprobe ec_sys write_support=1
ExecStart=/usr/local/sbin/msi-fan-curve apply

[Install]
WantedBy=multi-user.target
UNIT

# 4. reapply on resume (EC state is volatile)
cat > /usr/lib/systemd/system-sleep/msi-fan-curve <<'HOOK'
#!/bin/sh
[ "$1" = "post" ] && /usr/local/sbin/msi-fan-curve apply
exit 0
HOOK
chmod +x /usr/lib/systemd/system-sleep/msi-fan-curve

systemctl daemon-reload && systemctl enable --now msi-fan-curve.service
```

## Verify

```bash
mokutil --sb-state                 # must say: SecureBoot disabled
msi-fan-curve show                 # duties 0 0 30 55 76 84 91; at idle rpm=0
```

Full cold-path test without rebooting — the unit must reload the module itself:

```bash
rmmod ec_sys && systemctl restart msi-fan-curve.service && msi-fan-curve show
```

Load check (fan should reach ~4600 RPM and hold 89–90 °C, not higher):

```bash
stress-ng --cpu 8 --timeout 120 & while sleep 15; do msi-fan-curve show | tail -1; done
```

## Revert

`msi-fan-curve restore` puts the stock curve back. A full power-off also resets
the EC to firmware defaults (= stock), so nothing here is permanent. To remove
entirely: `systemctl disable --now msi-fan-curve.service` and delete the four
files above.

## EC map reference

`/sys/kernel/debug/ec/ec0/io`, requires `ec_sys write_support=1`:

| Offset | Meaning |
|---|---|
| `0x6a`–`0x70` | CPU curve temperature thresholds (7 bytes) |
| `0x72`–`0x78` | CPU curve duty percentages (7 bytes) |
| `0x71` | live CPU fan duty % (read this to see which entry the EC picked) |
| `0xcc`–`0xcd` | CPU fan tach, big-endian; **RPM = 478000 / raw** |
| `0xce`–`0xcf` | GPU fan tach, same formula (reads 0 at idle — GPU fan is off) |
| `0x98` | cooler boost |

Writes land immediately and the EC honours them within ~1 s.

## Gotchas

- **Do not flash the BIOS.** Mainline `msi-ec` refuses to bind (`Unable to find a
  valid firmware version!`) because the whitelist is compiled into the *kernel
  driver*, not the laptop firmware — flashing cannot fix that and risks shifting
  every offset above. Use `ec_sys` instead. `msi-ec` also exposes no module
  parameters in the Ubuntu build, so there is no force-config path.
- hwmon numbering is **not** stable across installs; the script above finds
  `coretemp` by name rather than hardcoding `hwmon3`.
- Wake-on-LAN does not work on this machine — it needs a physical power-on.

## Stock EC dump (baseline, 2026-09-10)

Re-readable at any time on a freshly powered machine with
`dd if=/sys/kernel/debug/ec/ec0/io bs=256 count=1 | od -A x -t x1`.

```
000020 00 00 00 00 00 00 00 00 00 00 00 80 c0 06 00 0b
000030 03 03 01 05 50 0a 05 00 cc 10 6a 2c ae 01 80 00
000060 00 00 00 00 00 00 00 00 33 00 2f 3c 46 50 5a 5f   <- 0x6a: 47 60 70 80 90 95
000070 69 37 30 37 3e 45 4c 54 5b 00 03 05 05 05 05 03   <- 0x70: 105, 0x72: 48 55 62 69 76 84 91
```
