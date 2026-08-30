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

## Serial session outcome (2026-08-30) — pb-boot SHELVED

Executed on the real unit: CP2102 on COM5, console proven both ways,
menu captured, TFTP from the laptop working (after firewall off).
The pb-boot dry run — `tftpboot 80100000 pbboot.img` + autostart
`bootm` — transferred and checksum-verified, jumped… and died silently:
no console output, no keypress response, no web server on
`192.168.1.1`/`192.168.15.1`, no DHCP. Warm-chaining a bootloader from
a running U-Boot is inherently unreliable (it expects cold-reset CPU
state), so this neither proves nor clears the image — and a bootloader
write on ambiguous evidence is the one unrecoverable mistake available
in this project.

**Decision: do not write mtd0. Recovery doctrine is serial console +
stock U-Boot + the verified backup.** With serial, stock U-Boot can
RAM-boot a full Linux anytime (menu option 1 / `tftpboot`+`bootm`) to
repair any partition from the backup — pb-boot adds nothing except
serial-free convenience. Revisit only if the exact binary can be
byte-verified against an official PandoraBox release.

## Path A (reference — write step shelved): USB-TTL serial + U-Boot does the write

Needs: any $3 CP2102/CH340/FT232 USB-TTL adapter (3.3 V), and a TFTP
server (tftpd64 on the second laptop, static IP `192.168.1.3`, netmask
`255.255.255.0`, cable to a LAN port).

1. Open the case; find the 4-pin serial header near the SoC. Connect
   RX/TX/GND per rule 4. PuTTY/TeraTerm: 115200 8N1, no flow control.
2. Power on. Boot messages confirm RX wiring; if the router also reacts
   to keypresses, TX is good. (If no output, swap RX/TX — it's the
   usual fix and harmless.)
3. Power-cycle and interrupt U-Boot within the 5 s window. The menu on
   **this unit** (captured over serial, 2026-08-30) is:
   - `1` Load system code to SDRAM via TFTP (RAM-boot, nothing written)
   - `2` Load system code then write to Flash via TFTP
   - `3` Boot system code via Flash (default)
   - `4` Enter boot command line interface (`MT7620 #` prompt)
   - `9` Load Boot Loader code then **write to Flash** via TFTP
   There is **no RAM-test option for bootloaders** in this menu:
   option `9` writes mtd0. Do not touch `9` until the dry run below
   has passed.
4. Put `pb-boot-xiaomi3-20181021-fd6329c.img` in the tftpd64 root,
   copied to a short name, e.g. `pbboot.img`.
5. **Dry run from the CLI** (nothing written): choose `4`, then at
   `MT7620 #` (command set verified on this unit: `tftpboot`, `bootm`,
   `go`, `nand`, `setenv`/`saveenv`):
   ```
   setenv autostart yes
   tftpboot 80100000 pbboot.img
   bootm 80100000
   ```
   Expect `Bytes transferred = 138852` from the tftp step. `bootm`
   parses the uImage header, copies the payload to its load address
   `0x80200000` and jumps (the pb-boot image is a type-standalone
   uImage; `autostart yes` makes bootm jump — it is RAM-only unless
   `saveenv` is run, so never run `saveenv` here). If `bootm` loads
   but returns to the prompt, `go 80200000` starts it. You should see
   "PandoraBox-Boot Version 2.1". Look but do not touch: do NOT use
   any pb-boot menu entry that writes or uploads while running from
   RAM. Power-cycling discards everything; stock U-Boot is untouched.
6. Only after the dry run behaves: power-cycle into the menu, choose
   `9`, and answer the prompts — device IP `192.168.1.1`, server
   `192.168.1.3`, filename `pbboot.img`. U-Boot receives the file,
   erases the Bootloader region and writes it. **Do not power off
   during this step.**
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

## First ImmortalWrt boot — from RAM, zero flash writes

The port ships `ramdisk` support, so the build produces an
**initramfs image** (`…initramfs-kernel.bin`): a complete ImmortalWrt
that runs entirely from RAM under the stock bootloader.

1. Copy the initramfs image to the TFTP root under a short name,
   e.g. `r3.bin`.
2. Serial → U-Boot menu → `4`, then:
   ```
   tftpboot 84000000 r3.bin
   bootm 84000000
   ```
   Load it **high** (`0x84000000`): the kernel decompresses to
   `0x80000000`, and a multi-MB image loaded at the default
   `0x80100000` would overlap its own destination.
3. Test everything while flash stays untouched: NAND driver probes
   (`dmesg | grep -i nand`), all 10 mtd partitions visible, `ubiattach`
   works, both radios up, switch ports mapped, sysupgrade metadata.
   Power-cycling returns to X-Wrt as if nothing happened.
4. Permanent install, only after the RAM test passes: from running
   X-Wrt, `sysupgrade -n` with our `sysupgrade.bin` (identical
   partition scheme and kernel-slot logic by design — mtd0 is never
   touched). Keep the serial console attached for the first boot.

## Reverting to X-Wrt

- From a running ImmortalWrt: `sysupgrade -n` with the X-Wrt sysupgrade
  image from `downloads.x-wrt.com/rom/`.
- From a broken system: serial → RAM-boot the initramfs image (above),
  then restore from the backup: copy `mtd8.bin`/`mtd9.bin` over and
  `mtd write` them to `kernel`/`ubi`. (`factory`/`Bdata` only if
  actually damaged.) An X-Wrt initramfs image works for this too.
