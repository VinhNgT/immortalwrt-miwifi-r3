# ImmortalWrt for the Xiaomi Mi Router 3 (miwifi-r3)

Modern, maintained firmware for the Xiaomi Mi Router 3. Official
OpenWrt dropped this device years ago because mainline Linux lost the
driver for its NAND storage; this project keeps it alive on **current
ImmortalWrt** by maintaining that driver and the device support out
of tree — with everything a user expects: LuCI web UI, current
kernel, installable packages, and safe upgrades.

## Status

Complete, verified on real hardware.

- Everything works: WiFi (2.4 + 5 GHz), switch, USB, web UI, storage,
  normal sysupgrade — on ImmortalWrt `v25.12.1` (kernel 6.12) and
  master (kernel 6.18).
- Installing never touches the bootloader, and every failure state
  short of deliberately destroying the bootloader is recoverable.
- The NAND driver's silent error-handling defect was fixed along the
  way — flash bit-errors now heal themselves automatically.

## Hardware

| | |
|---|---|
| SoC | MediaTek MT7620A @ 580 MHz (MIPS 24KEc, mipsel) |
| RAM | 128 MiB DDR2 |
| Flash | 128 MiB parallel NAND, ESMT F59L1G81LA |
| WiFi | 2.4 GHz 802.11n (rt2800soc) + 5 GHz 802.11ac (MT7612E, mt76x2) |
| Ethernet | 3× 100M (2 LAN, 1 WAN) |
| USB | 1× USB 2.0 |
| Serial | 115200 8N1, 3.3 V TTL |

"R3" only — the 3G/3C/3A/3P are different devices and share nothing
here.

## Quick start

1. Download `…sysupgrade.bin` and `sha256sums` from the newest
   [GitHub release](../../releases) and verify the checksum.
2. If this is your first flash: **make a backup first** —
   [docs/RECOVERY.md](docs/RECOVERY.md).
3. Flash it from your current OpenWrt-family firmware's web UI
   (settings **not** kept when switching firmware families) — full
   steps in [docs/GUIDE.md](docs/GUIDE.md).
4. The router comes back at `192.168.1.1` (user `root`, no password —
   set one).

Adding packages later: ordinary packages install normally; kernel
modules come from the release's bundled ImageBuilder — the guide
covers both, plus the quirks worth knowing.

## Documentation

**For users:**

- [docs/GUIDE.md](docs/GUIDE.md) — installing, upgrading, adding
  packages, common use cases, quirks
- [docs/RECOVERY.md](docs/RECOVERY.md) — backup, serial console, and
  every path back from a bad flash

**For developers** (how it works and why):

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — building, testing,
  cutting releases, CI internals
- [docs/PORT-NOTES.md](docs/PORT-NOTES.md) — technical reference:
  the NAND driver, what the port changes, the fixes made here
- [docs/RESEARCH-LOG.md](docs/RESEARCH-LOG.md) — how the conclusions
  were reached, dead ends included

## Credits & license

The NAND driver and original device support are by Chen Minqiang
([x-wrt](https://github.com/x-wrt/x-wrt)); this repo forward-ports
that work onto ImmortalWrt and adds fixes of its own. Licensed
[GPL-2.0](LICENSE), like the OpenWrt code it derives from
(provenance of the vendored files:
[vendor/x-wrt/PROVENANCE.md](vendor/x-wrt/PROVENANCE.md)).
