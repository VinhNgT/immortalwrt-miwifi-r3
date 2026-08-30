# Mi Router 3 — device runbook: recovery, testing, flashing

For **this** unit (SN 12937/20170494). Everything here was established
by direct on-device inspection and live serial sessions (2026-08-30/31),
not from wikis. Background and research history: [docs/PORT-NOTES.md](docs/PORT-NOTES.md).

## Standing facts

- Bootloader (mtd0): **stock Ralink U-Boot 1.1.3 (Apr 15 2016)**,
  uImage-wrapped. Never modified — and the doctrine below never
  modifies it.
- U-Boot env is already ideal: `uart_en=1`, `boot_wait=on`,
  `bootdelay=5`, `ipaddr=192.168.1.1`, `serverip=192.168.1.3`.
  `flag_boot_rootfs=1` → boots the `kernel` slot (mtd8).
- mtd0 is read-only under Linux (DTS `read-only`) — by design, keep it.
- Kernel slots: mtd7 `kernel_stock` holds the stock 2.6.36 kernel —
  CRC-valid but its rootfs is gone; **not a fallback**. mtd8 `kernel`
  is the live slot.
- The stock bootloader has **no USB and no web recovery**. Serial is
  the backstop, and it works (CP2102 on COM5, 115200 8N1).
- NAND: ESMT F59L1G81LA, 0 bad eraseblocks; one single-bit flip in
  `kernel_stock` (page 0x6b7) that ECC corrects on every read.

## The backup — do not lose this

`D:\r3-backup\` — full 128 MiB NAND dump, all 10 partitions,
md5-verified on the PC. `r3-backup.tar` md5
`65530a59773e0761ee32cb0bc24ad03d`. Keep a second copy elsewhere.

| mtd | name | size | notes |
|---|---|---|---|
| 0 | Bootloader | 256 KiB | stock U-Boot 1.1.3 |
| 1 | Config | 256 KiB | U-Boot env |
| 2 | Bdata | 256 KiB | SN, keys |
| 3 | **factory** | 256 KiB | **RF calibration + MACs — irreplaceable** |
| 4–6 | crash / crash_syslog / reserved0 | | |
| 7 | kernel_stock | 4 MiB | stock 2.6.36 kernel (dead slot) |
| 8 | kernel | 4 MiB | live kernel slot |
| 9 | ubi | 118 MiB | rootfs + overlay |

Reference md5s for read-verification: mtd3
`4d2c86bc2b77adc1a73b059d6b69ca48`, mtd7
`c007b8af668f3e023d87f20d27fad7eb`, mtd8
`043a401a0b09e35870f03427f0a36f70` (full list in `D:\r3-backup\MD5SUMS`).

## Golden rules

1. **Never write mtd0.** All install/recovery paths below work without
   touching it. (pb-boot is shelved — see appendix.)
2. Never install Breed — no R3 build exists; wrong-device bootloader =
   unrecoverable brick.
3. Never let anything erase mtd3 (`factory`).
4. Serial: 3.3 V TTL, RX→TX, TX→RX, GND→GND, **VCC not connected**.
5. In the U-Boot menu, **option 9 writes the bootloader to flash** —
   never select it casually. There is no RAM-test menu option.
6. Flash over LAN cable, never WiFi; never power off mid-write.

## Recovery ladder

Any failure state short of a destroyed bootloader is recoverable:

1. **Firmware misbehaves but boots** → sysupgrade to a known-good image
   (ImmortalWrt or X-Wrt).
2. **Firmware doesn't boot** → serial → U-Boot → RAM-boot an initramfs
   image (below) → repair from Linux: `mtd write` the relevant
   partitions from the backup, or run sysupgrade from the RAM system.
3. **Byte-exact return to the 2026-08-30 X-Wrt state** → RAM-boot any
   initramfs, copy `mtd8.bin` + `mtd9.bin` over (USB stick or scp),
   `mtd write mtd8.bin kernel && mtd write mtd9.bin ubi`.
   (`factory`/`Bdata` only if actually damaged.)

## Serial + U-Boot reference (as captured on this unit)

Wiring per rule 4; MobaXterm/PuTTY 115200 8N1, flow control off.
Interrupt within 5 s of power-on. The real menu:

```
1: Load system code to SDRAM via TFTP.        (RAM-boot, writes nothing)
2: Load system code then write to Flash via TFTP.
3: Boot system code via Flash (default).
4: Entr boot command line interface.          (MT7620 # prompt)
9: Load Boot Loader code then write to Flash via TFTP.   ** WRITES mtd0 **
```

CLI commands available: `tftpboot`, `bootm`, `go`, `nand`, `md`, `mm`,
`nm`, `printenv`, `setenv`, `saveenv`, `reset`, `version`, `mdio`, `rf`.
Rule of thumb: `setenv` without `saveenv` is RAM-only and safe.

### TFTP server gotchas (Windows laptop, tftpd64)

- Laptop static `192.168.1.3/24`, cable into a **LAN** port.
- The link has no gateway → Windows treats it as **Public/Unidentified**
  → firewall silently eats TFTP (and ICMP echo). Symptom signature:
  U-Boot prints `Got ARP REPLY` then `T T T…` timeouts — ARP works,
  TFTP dies on the laptop. Fix: allow tftpd64 on all profiles, or
  temporarily `netsh advfirewall set allprofiles state off` (re-enable
  after).
- Check tftpd64's "Server interfaces" is bound to the 192.168.1.3
  adapter and the base directory holds the image.
- A missing file would come back as an explicit error, not timeouts.

## RAM-booting an initramfs image (proven procedure)

Boots a complete firmware entirely from RAM — **zero flash writes**,
power-cycle returns to the flashed system. This is both the test
harness and recovery vehicle.

1. Put `…initramfs-kernel.bin` in the TFTP root under a short name
   (`r3.bin`).
2. Menu → `4`, then:
   ```
   tftpboot 84000000 r3.bin
   bootm 84000000
   ```
   Load **high** (`0x84000000`): the kernel decompresses to
   `0x80000000`; a multi-MB image at the default `0x80100000` would
   overlap its own destination. Images well past the 4 MiB flash-slot
   limit load fine this way (8.9 MB verified).
3. Root shell appears on serial; LAN comes up as `192.168.1.1`.

**2026-08-31 validation run (ImmortalWrt master, 6.18.44):** all 10
partitions present with exact stock layout; `mtk_nand_probe` +
`fixed-partitions` on `ra_nfc`; md5 of mtd3/mtd7/mtd8 byte-identical
to the backup on two consecutive runs — including a live single-bit
ECC correction (`1. correct byte 445, bit 1!`) with output still
matching; both radios (`phy0`+`phy1`, SSID on air); `switch0`
responding. The port is proven on this hardware.

## Installing ImmortalWrt (permanent)

Use a build whose seed includes LuCI (`CONFIG_PACKAGE_luci=y` —
present since repo commit `1639e0b`). Get
`…squashfs-sysupgrade.bin` from the latest green Actions run.

Via the running firmware's web UI (X-Wrt LuCI, `192.168.15.1`):

1. PC on LAN cable; serial console attached and logging (nice to have).
2. System → Backup / Flash Firmware → flash the `…sysupgrade.bin`.
3. **Uncheck "Keep settings"** (= `sysupgrade -n`). Old-firmware config
   must not carry over.
4. Verify the displayed checksum against the artifact's `sha256sums`,
   proceed, and leave it alone for 3–5 minutes.
5. After reboot the address changes: **`192.168.1.1`**, user `root`, no
   password — set one immediately. WiFi broadcasts as "ImmortalWrt".

CLI equivalent: `scp` the image to `/tmp`, `sysupgrade -n /tmp/….bin`.

Slot behavior (from our `platform.sh`): with stock U-Boot on mtd0 the
kernel is written to `kernel` (mtd8) — the slot the boot flags already
point at. If the upgrader ever refuses the image as incompatible, stop
and investigate; do not force.

Subsequent updates: ImmortalWrt's own sysupgrade with the newer
`sysupgrade.bin`.

## Reverting to X-Wrt

- From a working system: sysupgrade (fresh config) with the X-Wrt image
  from `downloads.x-wrt.com/rom/`.
- From a broken system: recovery ladder step 2 or 3 above.

## Appendix: pb-boot — verified, shelved

`D:\xiaomi mir3\pbboot r3\pb-boot-xiaomi3-20181021-fd6329c.img` —
138,852 B, sha256
`c2235164b2dd676d9564defca9c8eefa3b447ac7f1b2966f0e1bef1145b7442a`,
md5 `87c79881406cafa47853c734c76e1141`. uImage header + data CRC
verified; strings confirm PandoraBox-Boot 2.1 for "Xiaomi R3" with
HTTPD Recovery Module v3.0 (`/upload.cgi`, web recovery reportedly at
`192.168.15.1`). Both stock U-Boot and pb-boot are uImage-wrapped
identically (load/entry `0x80200000`, name "NAND Fla") ⇒ if ever
flashed, the `.img` goes on verbatim — header included.

**Why shelved (2026-08-30):** the only non-destructive test available —
warm-chaining it from the running U-Boot (`tftpboot` + `bootm`,
transfer and CRC OK, jump taken) — died silently: no console, no HTTP,
no DHCP. Bootloaders expect cold-reset CPU state, so this outcome says
nothing about the image; but with no way to validate before the
irreversible mtd0 write, and with serial + initramfs covering every
recovery need, the write is not justified. Revisit only if (a) the
binary is byte-verified against an official PandoraBox release, and
(b) serial-free recovery becomes genuinely necessary.

The old "path B" (custom build with `read-only;` dropped from
`partition@0`, then `mtd write … Bootloader` from Linux) remains
technically possible and equally unjustified.
