# Mi Router 3 — recovery plan and flashing runbook

State of **this** router (SN 12937/20170494), verified 2026-08-30.
Everything below was established by direct inspection over SSH — not
assumed from wikis.

## Current state

- Running firmware: X-Wrt, kernel 6.18.44, LAN `192.168.15.1`, SSH root.
- Bootloader (mtd0): **stock Ralink U-Boot 1.1.3 (Apr 15 2016)**,
  uImage-wrapped. Not breed, not pb-boot.
- Boot env already ideal for serial work: `uart_en=1`, `boot_wait=on`,
  `bootdelay=5`, `bootcmd=tftp`, `ipaddr=192.168.1.1`,
  `serverip=192.168.1.3`.
- Kernel slots: mtd7 `kernel_stock` = stock 2.6.36 kernel (CRC valid but
  its rootfs no longer exists — **not** a usable fallback); mtd8
  `kernel` = X-Wrt 6.18.44 (active, `flag_boot_rootfs=1`).
- **No recovery paths exist today**: no USB recovery in this bootloader
  (only `uboot.bin`/`test.bin` TFTP), no web recovery, no working second
  system. A silent-boot TFTP test confirmed nothing fires on a good boot.
- mtd0 is **read-only in the running kernel** (`flags 0x0`, DTS
  `read-only`), so pb-boot cannot be written from X-Wrt as-is.

## The backup (do not lose this)

`D:\r3-backup\` — full 128 MiB NAND dump, all 10 partitions,
**md5-verified on the PC**. `r3-backup.tar` md5
`65530a59773e0761ee32cb0bc24ad03d`.

| mtd | name | size | notes |
|---|---|---|---|
| 0 | Bootloader | 256 KiB | stock U-Boot 1.1.3 |
| 1 | Config | 256 KiB | U-Boot env |
| 2 | Bdata | 256 KiB | SN, keys |
| 3 | **factory** | 256 KiB | **RF calibration + MACs — irreplaceable, exists nowhere else on earth** |
| 4–6 | crash/crash_syslog/reserved0 | | |
| 7 | kernel_stock | 4 MiB | stock 2.6.36 kernel |
| 8 | kernel | 4 MiB | X-Wrt 6.18.44 kernel |
| 9 | ubi | 118 MiB | X-Wrt rootfs + overlay |

Copy it to a second disk or cloud before flashing anything.

## Golden rules

1. Never write mtd0 (Bootloader) except with the verified pb-boot image
   or the mtd0.bin from the backup. A bad bootloader is the only
   unrecoverable state without soldering-level work.
2. **Never install breed** — no R3 (MT7620+NAND) build exists; the
   mini/3G builds are for different hardware and will hard-brick.
3. Never let anything erase mtd3 (`factory`).
4. Serial: 3.3 V TTL, RX→TX, TX→RX, GND→GND, **VCC not connected**.
5. In the U-Boot menu, the bootloader-write option accepts any file it
   receives — double-check the TFTP filename before confirming.

## The pb-boot image (verified good)

`D:\xiaomi mir3\pbboot r3\pb-boot-xiaomi3-20181021-fd6329c.img`
— 138,852 B, uImage header + data CRC verified, load/entry
`0x80200000`, PandoraBox-Boot 2.1 for "Xiaomi R3", contains
**HTTPD Recovery Module v3.0** and TFTP recovery.

mtd0 analysis showed both the stock bootloader and pb-boot are
uImage-wrapped the same way ⇒ **flash the `.img` verbatim, do not strip
the 64-byte header**.

## Path A (recommended): USB-TTL serial + U-Boot does the write

Needs: any $3 CP2102/CH340/FT232 USB-TTL adapter (3.3 V), and a TFTP
server (tftpd64 on the second laptop, static IP `192.168.1.3`, netmask
`255.255.255.0`, cable to a LAN port).

1. Open the case; find the 4-pin serial header near the SoC. Connect
   RX/TX/GND per rule 4. PuTTY/TeraTerm: 115200 8N1, no flow control.
2. Power on. Boot messages confirm RX wiring; if the router also reacts
   to keypresses, TX is good. (If no output, swap RX/TX — it's the
   usual fix and harmless.)
3. Power-cycle and interrupt U-Boot within the 5 s `boot_wait` window.
   The Ralink 1.1.3 menu appears. Typical entries (confirm against your
   console before acting):
   - `1` load system code to SDRAM via TFTP (RAM-boot, nothing written)
   - `2` load system code then **write to flash** via TFTP
   - `3` boot from flash (default)
   - `4` U-Boot command line
   - `7` load **bootloader** then write to flash via TFTP
   - `9` load bootloader to SDRAM via TFTP (test-run, nothing written)
4. Put `pb-boot-xiaomi3-20181021-fd6329c.img` in the tftpd64 root.
5. **Dry run first**: option `9`, server `192.168.1.3`, filename the
   pb-boot img. It loads into RAM and runs — you should see
   "PandoraBox-Boot Version 2.1". Confirm its recovery mode comes up
   (hold reset; web server on `192.168.15.1` — if not, try
   `192.168.1.1`). Power-cycling discards everything; stock U-Boot is
   untouched.
6. Only after the dry run behaves: repeat with option `7` (write to
   flash). Same file, same server. U-Boot verifies receipt, erases
   mtd0, writes.
7. Reboot. pb-boot should bring up X-Wrt exactly as before (it boots
   the same kernel slot scheme). Recovery from now on: hold **reset**
   while powering on → pb-boot HTTPD recovery → upload a
   `factory.bin`-style image (kernel+UBI). That is precisely the format
   this repo's build produces.

Why A is recommended: U-Boot writes the bootloader itself — the Linux
`read-only` guard on mtd0 is never involved, and the serial console you
used is also your safety net for everything that follows.

## Path B (no serial): unlock mtd0 via a custom build

Build X-Wrt (not ImmortalWrt — smaller first-flash risk on a scheme
X-Wrt has proven on this box) with one DTS change: remove `read-only;`
from `partition@0` in `mt7620a_xiaomi_miwifi-r3.dts`. Sysupgrade to it,
then from the running system:

```
mtd write /tmp/pb-boot-xiaomi3-20181021-fd6329c.img Bootloader
```

Verify before rebooting:

```
dd if=/dev/mtd0 bs=64 count=1 | strings | grep -i pb-boot
md5sum /tmp/pb-boot-*.img; dd if=/dev/mtd0 bs=1 count=138852 | md5sum
```

Risks: you flash a whole firmware to change one DTS flag, and the write
happens with no fallback bootloader — a power cut mid-write bricks with
no serial to recover. Only take this path if serial is truly impossible.

## Reverting to X-Wrt (once pb-boot is installed)

- Preferred: pb-boot recovery → upload the current X-Wrt factory image
  from `downloads.x-wrt.com/rom/` (or one built from x-wrt source).
- Byte-exact restore of today's system: boot any working
  OpenWrt-family firmware, copy from the backup and write
  `mtd8.bin → kernel`, `mtd9.bin → ubi`. (`factory`/`Bdata` only if
  actually damaged.)

## First ImmortalWrt flash (after pb-boot is in place)

1. Build (see README). Take `factory.bin` and `sysupgrade.bin` from
   `out\`.
2. Cleanest: pb-boot recovery → upload `factory.bin` (kernel + UBI,
   both freshly written; no leftover X-Wrt state).
3. If it misbehaves: pb-boot recovery again → X-Wrt factory image →
   back where you started. Nothing is burned.
4. Only after ImmortalWrt is proven: use its own `sysupgrade.bin` for
   subsequent updates.
