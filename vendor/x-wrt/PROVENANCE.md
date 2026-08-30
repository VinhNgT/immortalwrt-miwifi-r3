# Provenance

Everything here is taken verbatim from [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt),
`master` branch, and is GPL-2.0 licensed like the rest of the OpenWrt tree.

Taken at x-wrt HEAD **3d76e35c18d0efd727fa8f02f8b4ad4f9009c75f**.

| file | upstream path |
|---|---|
| `ralink_nand.c` | `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.c` |
| `ralink_nand.h` | `target/linux/ramips/files/drivers/mtd/maps/ralink_nand.h` |
| `mt7620a_xiaomi_miwifi-r3.dts` | `target/linux/ramips/dts/mt7620a_xiaomi_miwifi-r3.dts` |
| `0038-...patch.<kv>` | `target/linux/ramips/patches-<kv>/0038-mtd-ralink-add-mt7620-nand-driver.patch` |

## Why vendored rather than pinned

x-wrt rebases its entire patch stack onto current OpenWrt — the NAND driver
carries an author date of 2017-11-18 but a committer date of 2026-08-29. Commit
SHAs therefore change on every rebase and cannot be used as stable references.
`scripts/fetch-vendor.sh` refreshes these files and records the HEAD it read.

## What the driver is

`ralink_nand.c` (2113 lines) is the legacy Ralink SDK NAND driver. It does **not**
use the Linux rawnand framework: it implements its own `struct ra_nand_chip`, its
own bad-block table, and registers a bare `struct mtd_info` via
`mtd_device_parse_register()`. That is simultaneously why upstream OpenWrt rejects
it and why it survives kernel churn — it touches almost no kernel API. It carries
explicit `LINUX_VERSION_CODE >= KERNEL_VERSION(6,12,0)` guards for the
`.remove_new` → `.remove` platform_driver transition.

Device tree binding: `compatible = "mtk,mt7620-nand"`.
MTD device name (for `mtdparts=`): `ra_nfc`.

The 6.12 and 6.18 patch variants are byte-identical; 6.1 and 6.6 differ only in
context lines.
