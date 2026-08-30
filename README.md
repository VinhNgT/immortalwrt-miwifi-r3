# ImmortalWrt for the Xiaomi Mi Router 3 (miwifi-r3)

Out-of-tree port bringing the Xiaomi Mi Router 3 back to current
ImmortalWrt (master, kernel 6.18). The device was last supported in
18.06-k5.4; it was dropped because OpenWrt lost the MT7620 raw-NAND
controller driver at the 4.4 → 4.9 kernel bump and only the MT7621
driver ever came back. X-Wrt kept an out-of-tree driver alive — this
repo lifts exactly that work onto ImmortalWrt.

## Hardware

| | |
|---|---|
| SoC | MediaTek MT7620A @ 580 MHz (MIPS 24KEc, mipsel) |
| RAM | 128 MiB DDR2 |
| Flash | 128 MiB parallel NAND, ESMT F59L1G81LA |
| WiFi | 2.4 GHz rt2800soc (SoC) + 5 GHz MT7612E (PCIe, mt76x2) |
| Ethernet | 3× 100M (2 LAN, 1 WAN) |
| USB | 1× USB 2.0 |
| Serial | 115200 8N1, 3.3V TTL |

## Layout — two equivalent ways to apply the port

| | mechanism | use when |
|---|---|---|
| `patches/` | two-commit `git am` series (driver, then device), generated against ImmortalWrt master `db5c5de` (2026-08-30) | reviewing the change, upstreaming, deterministic CI builds |
| `scripts/apply-r3-support.sh` + `vendor/x-wrt/` | idempotent installer; auto-detects `KERNEL_PATCHVER`, so it also handles 25.12 / kernel 6.12 trees | day-to-day builds, other branches, after upstream drift breaks the patches |

Both were verified to produce functionally identical trees (differences
are ordering/comments only). `scripts/fetch-vendor.sh` refreshes
`vendor/x-wrt/` from x-wrt master and records the HEAD it read —
x-wrt rebases continuously, so file contents are vendored instead of
pinning commit SHAs (see `vendor/x-wrt/PROVENANCE.md`).

The port touches 10 places in the tree: NAND driver
(`ralink_nand.[ch]`, bypasses the rawnand framework — that is why it
survives kernel churn), kernel Kconfig hook patch, DTS (stock partition
layout: dual kernel slots + 118 MiB UBI), image recipes, `nand`
feature flag, UBI/UBIFS kernel config for mt7620 (+ symbol disabled for
mt76x8), nand sysupgrade with bootloader detection (stock U-Boot /
breed / pb-boot), switch-port + MAC setup, uboot-envtools entry.

Everything derives from x-wrt work by Chen Minqiang, GPL-2.0.
`reference/` holds upstream file snapshots used during analysis;
`r3-port-notes.html` is the research write-up.

## Building (Docker, recommended)

```powershell
.\build.ps1
```

First run clones ImmortalWrt into a named volume (`iwrt-src`), applies
`patches/`, builds, and drops images into `out\`. Expect 1–3 h the
first time; re-runs reuse the volume and download cache.
`.\build.ps1 -Shell` opens a shell in the build environment instead.

## Building (manual, any tree)

```bash
git clone https://github.com/immortalwrt/immortalwrt.git
./scripts/apply-r3-support.sh immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620/`. For an
ImmortalWrt 25.12 (kernel 6.12) tree the same command works — the
installer picks the 6.12 variant of the kernel patch automatically.
Master is the primary target because the running X-Wrt install on this
router is kernel 6.18.44, i.e. this exact driver is proven on 6.18 on
this exact device.

## CI

`.github/workflows/build.yml` builds the series against master and
uploads the images as an artifact. Push this repo to GitHub
(`gh repo create`) to enable it; also runnable manually via
workflow_dispatch with a different ImmortalWrt ref.

## Flashing — read RECOVERY.md first

Do not flash anything before working through [RECOVERY.md](RECOVERY.md).
Short version: the router still runs the stock read-only U-Boot with no
usable recovery path; install pb-boot (web recovery) first, and keep the
verified NAND backup in `D:\r3-backup` safe. The `factory.bin` image
this repo builds is exactly what pb-boot's web recovery flashes.
