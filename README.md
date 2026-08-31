# ImmortalWrt for the Xiaomi Mi Router 3 (miwifi-r3)

Out-of-tree port that keeps the Xiaomi Mi Router 3 on **current
ImmortalWrt** (tested on master/kernel 6.18 and the `v25.12.1`
release/kernel 6.12). The device was dropped from OpenWrt when the
MT7620 raw-NAND driver was lost in the 4.4 → 4.9 kernel bump; X-Wrt
kept an out-of-tree driver alive, and this repo grafts that work —
plus fixes of its own — onto ImmortalWrt as a patch series and an
idempotent installer script. Full technical background:
[docs/PORT-NOTES.md](docs/PORT-NOTES.md).

## Status

Complete, verified on real hardware.

**What works:** the NAND driver with the full 10-partition stock
layout, UBI rootfs, both radios, switch, USB, LuCI, and normal
sysupgrade — on kernel 6.12 (`v25.12.1` release) and 6.18 (master).
This is the only known build of this driver on a 6.12 kernel.

**Verification approach:** every image can be RAM-booted over TFTP
(zero flash writes) before it touches flash; partition reads were
checked byte-identical against a full NAND backup; installation is
plain sysupgrade; the stock bootloader is never modified
([archived boot log](docs/boot-logs/2026-08-31-first-boot-v25.12.1-p0004-ib-image.md)).

**Beyond a straight port**, two upstream defects are fixed here
(details in [docs/PORT-NOTES.md](docs/PORT-NOTES.md)):

- `patches/0004` — the driver corrected single-bit NAND errors but
  never reported them, so UBI's self-healing never ran; bitflips now
  scrub automatically.
- `patches/0005` (+ `ALL_KMODS` + a per-run ImageBuilder) — kernel
  modules remain installable despite the self-built kernel's
  vermagic — see
  [ImageBuilder](#imagebuilder--package-changes-without-recompiling).

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

"R3" only — the 3G/3C/3A/3P are different SoCs and share nothing
here.

## Repo layout

| | |
|---|---|
| `patches/` | five-commit `git am` series vs ImmortalWrt master `db5c5de` (driver, device, dual-slot nand.sh, ECC reporting, ImageBuilder feeds) — the reviewable/upstreamable form |
| `scripts/apply-r3-support.sh` | idempotent installer; auto-detects `KERNEL_PATCHVER` (works on 6.12 and 6.18 trees) |
| `scripts/trim-mt7620-to-r3.sh` | strips all other mt7620 device recipes so the ImageBuilder offers only the R3 profile (CI runs it after the installer) |
| `vendor/x-wrt/` | pinned x-wrt sources + [PROVENANCE.md](vendor/x-wrt/PROVENANCE.md); refresh via `scripts/fetch-vendor.sh` |
| `config.seed` | build seed (target + device + LuCI + kmod/IB/ccache options, each explained inline) |
| `docker/`, `build.ps1` | local containerized build |
| `.github/workflows/build.yml` | CI: build, cache, upload image + ImageBuilder artifacts |
| `docs/PORT-NOTES.md` | technical reference: driver, the 13 touch points, patches 0004/0005 |
| `docs/RESEARCH-LOG.md` | how the conclusions were reached — corrections, dead ends, incidents |
| `docs/boot-logs/` | archived (redacted) boot logs from real hardware |
| `RECOVERY.md` | device runbook: serial/U-Boot, RAM-boot testing, install, recovery ladder |
| `reference/` | upstream file snapshots used during analysis |

Both apply mechanisms produce functionally identical trees (verified
by tree-diff). The port totals 13 touch points; original driver and
device work by Chen Minqiang (x-wrt), GPL-2.0.

## Building

**CI (recommended):** any push builds `v25.12.1` (docs-only pushes
skip) and uploads two artifacts: `immortalwrt-xiaomi-miwifi-r3` (the
images) and `immortalwrt-imagebuilder-miwifi-r3` (below). The
workflow caches downloads, the toolchain, the feeds checkout, and
ccache, all keyed so that upstream or config changes invalidate
cleanly; a cold build takes ~1.5–2 h, warm rebuilds substantially
less. Manual dispatch accepts any ImmortalWrt ref:

```bash
gh workflow run build.yml -f ref=v25.12.1
```

**Docker, local:** `.\build.ps1` — clones into a named volume,
applies the port, drops images in `out\`. `-Shell` for an interactive
build environment.

**Manual, any tree:**

```bash
git clone https://github.com/immortalwrt/immortalwrt.git
./scripts/apply-r3-support.sh immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620/`: `sysupgrade.bin` (normal
upgrade), `initramfs-kernel.bin` (RAM-boot test/recovery image),
`factory.bin` / `breed-factory.bin` (pb-boot/breed recovery formats),
`kernel1.bin` + `rootfs0.bin` (split pieces).

## ImageBuilder — package changes without recompiling

A self-built kernel's **vermagic** never matches the official
release's, so official-feed kernel modules are permanently
uninstallable on this firmware. The pipeline solves that: each CI run
sets `CONFIG_ALL_KMODS=y` (every kmod is built against that exact
kernel) and ships an ImageBuilder that bundles them all, with
`patches/0005` pointing it at the official per-arch feeds for plain
userland packages. Recipes are trimmed to the R3, so `make info`
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
the bundled `packages/` directory is a local feed, and any
`kmod-*.apk` from it installs directly on a router running the
**same** build (`apk add ./kmod-….apk`).

Two rules: never mix kmods across builds (each build is its own
vermagic universe — after a reflash, use that run's ImageBuilder),
and kernel-side changes (driver patches, kernel config) still need a
full CI rebuild, which yields a new ImageBuilder.

## Flashing

Read [RECOVERY.md](RECOVERY.md) first — it encodes the safety
doctrine this port was built under: the stock bootloader is never
modified, every image is RAM-tested via TFTP before touching flash,
and a verified full-NAND backup plus a working serial console back
every step.
