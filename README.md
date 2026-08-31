# ImmortalWrt for the Xiaomi Mi Router 3 (miwifi-r3)

Out-of-tree port bringing the Xiaomi Mi Router 3 back to current
ImmortalWrt (master, kernel 6.18). The device was dropped when OpenWrt
lost the MT7620 raw-NAND driver at the 4.4 → 4.9 kernel bump; X-Wrt
kept an out-of-tree driver alive, and this repo lifts that work onto
ImmortalWrt. History, driver analysis, and research corrections:
[docs/PORT-NOTES.md](docs/PORT-NOTES.md).

## Status: proven on hardware

RAM-booted on the real unit (2026-08-31) via stock U-Boot TFTP —
zero flash writes:

- NAND driver probes; all 10 stock partitions, exact layout
- mtd reads byte-identical to a verified backup (md5, twice) — with a
  live single-bit ECC correction along the way
- both radios on air (2.4 GHz rt2800soc + 5 GHz MT7612E), switch OK
- kernel 6.18.44 — the same version the unit's proven X-Wrt build runs

CI builds all six image types green in ~50 min. **Installed to flash
2026-08-31** via plain sysupgrade from X-Wrt (web UI, settings not
kept): the upgrade wrote the correct kernel slot, the NAND driver and
UBI came up clean on the real flash boot (944 PEBs, 0 bad,
0 corrupted), and the system boots repeatably to a login prompt with
LuCI at 192.168.1.1. The stock bootloader was never modified.
Same day, `v25.12.1` (kernel 6.12.94) was built via manual dispatch
and installed the same way — the first time this driver has run on a
6.12 kernel anywhere — and boots clean.
Procedures and recovery ladder: [RECOVERY.md](RECOVERY.md).

## Hardware

| | |
|---|---|
| SoC | MediaTek MT7620A @ 580 MHz (MIPS 24KEc, mipsel) |
| RAM | 128 MiB DDR2 |
| Flash | 128 MiB parallel NAND, ESMT F59L1G81LA |
| WiFi | 2.4 GHz rt2800soc (SoC) + 5 GHz MT7612E (PCIe, mt76x2) |
| Ethernet | 3× 100M (2 LAN, 1 WAN) |
| USB | 1× USB 2.0 |
| Serial | 115200 8N1, 3.3 V TTL |

"R3" only — the 3G/3C/3A/3P are different SoCs and share nothing here.

## Repo layout

| | |
|---|---|
| `patches/` | four-commit `git am` series (driver, device, dual-slot nand.sh, ECC bitflip reporting) vs ImmortalWrt master `db5c5de` — the reviewable/upstreamable form |
| `scripts/apply-r3-support.sh` | idempotent installer; auto-detects `KERNEL_PATCHVER` (works on 25.12/6.12 trees too) |
| `scripts/trim-mt7620-to-r3.sh` | strips all other mt7620 device recipes so the ImageBuilder offers only the R3 profile (CI runs it after the installer) |
| `vendor/x-wrt/` | pinned x-wrt sources + [PROVENANCE.md](vendor/x-wrt/PROVENANCE.md); refresh via `scripts/fetch-vendor.sh` |
| `config.seed` | build seed (target + device + LuCI) |
| `docker/`, `build.ps1` | local containerized build |
| `.github/workflows/build.yml` | CI build, images as artifact |
| `docs/PORT-NOTES.md` | background: removal history, driver internals, corrections, ranked approaches |
| `RECOVERY.md` | device runbook: serial/U-Boot reference, RAM-boot testing, install, recovery ladder |
| `reference/` | upstream file snapshots used during analysis |

Both apply mechanisms produce functionally identical trees (verified by
tree-diff). The port totals 10 touch points; original work by
Chen Minqiang (x-wrt), GPL-2.0.

## Building

**CI (recommended):** push to GitHub → the workflow builds `v25.12.1`
(the ref the device runs; docs-only pushes skip the build) and uploads
two artifacts: `immortalwrt-xiaomi-miwifi-r3` (the images) and
`immortalwrt-imagebuilder-miwifi-r3` (see below). Plain image builds
took ~50 min; `CONFIG_ALL_KMODS=y` (every kernel module compiled)
roughly doubles that cold, but the workflow caches `dl/`, ccache, and
the toolchain (keyed per ref, quota-safe), so warm rebuilds of the
same ref drop back to roughly the old time. Manual dispatch
accepts any ImmortalWrt ref — branch or tag, e.g. `v25.12.1`; the
apply step uses the version-aware installer script, so 6.12 and 6.18
trees both work (validated against `v25.12.1` on 2026-08-31):

```bash
gh workflow run build.yml -f ref=v25.12.1
```

**Docker, local:** `.\build.ps1` — clones into a named volume, applies
`patches/`, drops images in `out\`. `-Shell` for an interactive build
environment. (First run downloads a few hundred MB — on a slow
connection, prefer CI.)

**Manual, any tree:**

```bash
git clone https://github.com/immortalwrt/immortalwrt.git
./scripts/apply-r3-support.sh immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620/`:
`sysupgrade.bin` (nand sysupgrade), `initramfs-kernel.bin` (RAM-boot
test/recovery image), `factory.bin` / `breed-factory.bin`
(pb-boot/breed formats), `kernel1.bin` + `rootfs0.bin` (split).

Note: `make defconfig` does **not** include LuCI on its own —
`config.seed` adds it explicitly.

## ImageBuilder — package changes without recompiling

Each CI run also produces an ImageBuilder (`CONFIG_IB=y`): the
prebuilt kernel, the image-assembly machinery, and — via
`CONFIG_ALL_KMODS=y` — **every kernel module** as a `.apk` built
against that kernel's exact vermagic. This solves the missing-kmod
problem: official-feed kmods can never match our patched kernel, but
the ImageBuilder carries its own complete, matching set. Image recipes
are trimmed to the R3 (`scripts/trim-mt7620-to-r3.sh`), so `make info`
lists exactly one profile.

On x86_64 Linux (WSL or Docker on Windows):

```bash
tar xf immortalwrt-imagebuilder-*.tar.zst && cd immortalwrt-imagebuilder-*/
```

```bash
make image PROFILE=xiaomi_miwifi-r3 PACKAGES="luci kmod-batman-adv luci-proto-batman-adv batctl-default"
```

→ a fresh `sysupgrade.bin` in `bin/targets/ramips/mt7620/` in about a
minute; flash with "Keep settings". Alternatively, skip the reflash:
the bundled `packages/` directory is a local feed, and any `kmod-*.apk`
from it installs directly on a router running the **same** build
(`apk add ./kmod-….apk`). Two rules: never mix kmods across builds
(each build is its own vermagic universe — after a reflash, use that
run's ImageBuilder), and kernel-side changes (driver patches, kernel
config) still need a full CI rebuild, which yields a new ImageBuilder.

## Flashing

Read [RECOVERY.md](RECOVERY.md) first — it encodes the safety doctrine
this port was built under: the stock bootloader is never modified,
every image is RAM-tested via TFTP before touching flash, and a
verified full-NAND backup plus working serial console back every step.
