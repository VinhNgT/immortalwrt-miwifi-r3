# Port notes — background, history, and corrections

Research record for the Mi Router 3 ImmortalWrt port. Everything here was
verified against primary sources (git history, raw file fetches,
on-device inspection). Compiled 2026-08-30, updated 2026-08-31 after the
port was built and RAM-tested on the real unit.

Status history: researched → parked (no recovery path) → serial console
established → **port proven from RAM, zero flash writes** → permanent
install via sysupgrade.

## Why the device fell out of OpenWrt

The parallel raw NAND is the entire problem; every other component is
ordinary ramips/mt7620 and works on current kernels.

OpenWrt shipped an in-tree MT7620 NAND driver
(`drivers/mtd/maps/ralink_nand.c`, `CONFIG_MTD_NAND_MT7620=y`) through
kernel 4.4, used by two boards (Sercomm NA930, Ralink MT7620a V22SG EVB):

| commit | date | what happened |
|---|---|---|
| `9c24227090` | 2017-02-13 | "ramips: add v4.9 support" — body reads, in full, "NAND support is missing" |
| `9bc9457b85` | 2017-06-01 | NAND restored — **MT7621 only** |
| `fddc78bc11` | 2017-07-05 | v4.9 bump deletes `patches-4.4/` incl. the 2,408-line NAND patch |
| `dea9922acd` | 2018-04-06 | drops 4.9, removing the dead `CONFIG_MTD_NAND_MT7620` line |
| `10f27c6f00` | 2020-04-01 | new clean MT7621 NAND driver |
| `2f2e81a4ea` | 2022-01-19 | moved to `files/drivers/mtd/nand/raw/mt7621_nand.c`, where it lives today |

Orphaned to this day: `compatible = "mtk,mt7620-nand"` still appears in
`mt7620a_sercomm_na930.dts` and `mt7620a_ralink_mt7620a-v22sg-evb.dts`
upstream with no driver behind it.

**Two upstream attempts, both rejected:**

- openwrt/openwrt#597 — "Mir3 support" by ptpt52 (2018), closed
  unmerged. ptpt52 (Chen Minqiang) subsequently founded X-Wrt, which is
  exactly why X-Wrt has the R3 and OpenWrt does not.
- openwrt/openwrt#9344 (2022) — Daniel Golle: a separate
  `ramips/mt7620-nand` subtarget would be needed ("enabling that for
  all mt7620 boards will break many devices… too much effort only to
  allow support of basically this one device. Imho it's a good
  candidate for a community build") and "the NAND driver is in very bad
  shape and unfit for submission upstream." The space concern is real:
  75 of 137 `IMAGE_SIZE` declarations in `mt7620.mk` are ≤ 8192k.

ImmortalWrt's own `openwrt-18.06-k5.4` branch carries the identical
patch filename — this is ImmortalWrt-lineage code; the port is asking
them to forward-port their own patch.

## The driver

`ralink_nand.c` (2,113 lines) is the legacy Ralink SDK driver. Its
defining property explains both why upstream refuses it and why it
never breaks: it **bypasses the Linux rawnand framework completely** —
own `struct ra_nand_chip`, own bad-block table, own read/write/erase,
registering a bare `struct mtd_info`. It touches almost no kernel API,
so it survived 5.10 → 6.18 essentially untouched. It carries
`LINUX_VERSION_CODE` guards for 6.12+ and a local `nand_ecclayout`
replacing the struct the kernel removed.

- Binding `compatible = "mtk,mt7620-nand"`; MTD device name `ra_nfc`.
- Partition probes `{ "cmdlinepart", "ofpart", NULL }` — cmdlinepart
  outranks the device tree.
- Author date 2017-11-18, committer date rolling — x-wrt continuously
  rebases its stack onto current OpenWrt. Live code, not abandonware.
  (This is also why `vendor/x-wrt/` pins file contents + a HEAD sha,
  not commit SHAs.)

### "Just extend mt7621_nand.c" does not work

Different IP generations, not variants:

| | MT7620 NFC | MT7621 NFI |
|---|---|---|
| registers | `0x1000_0800`, 256-byte block | `0x1e003000` NFI + `0x1e003800` ECC engine |
| ECC | Hamming 24-bit/512B, 1-bit correction **in software** | hardware BCH, strength 4–12, hardware error readback |
| overlap | zero shared register offsets | — |

The windows MT7621 uses are marked *Reserved* on MT7620. 0 of 1,344
driver lines transfer. Only `mtk_bmt` is controller-independent.

**Witnessed on this unit (2026-08-31):** the software Hamming path
detected a real single-bit flip (page 0x6b7 in `kernel_stock`, byte
445 bit 1), corrected it, and produced output byte-identical to the
verified backup on consecutive runs. The correction path works.

## The port

Ten touch points, all derived from x-wrt commits `387988e8c956`
(driver) and `f4fc1766f08a` + follow-ups (device), author Chen Minqiang:

1. `files/drivers/mtd/maps/ralink_nand.c` — new
2. `files/drivers/mtd/maps/ralink_nand.h` — new
3. `patches-<kv>/0038-mtd-ralink-add-mt7620-nand-driver.patch` — 18-line
   Kconfig/Makefile hook (6.12 and 6.18 variants byte-identical)
4. `dts/mt7620a_xiaomi_miwifi-r3.dts` — new; x-wrt master's version
   (modernized `nvmem-layout`; the 18.06-era one uses removed bindings)
5. `image/mt7620.mk` — device recipe (see below)
6. `mt7620/target.mk` — `FEATURES += nand`
7. `mt7620/config-<kv>` — `MTD_NAND_MT7620`, UBI, UBIFS + compression deps
8. `mt7620/base-files/lib/upgrade/platform.sh` — nand sysupgrade with
   bootloader/slot detection
9. `mt7620/base-files/etc/board.d/02_network` — switch ports
   (`1:lan 4:lan 0:wan 6@eth0`) + MACs from factory `0x28`
10. `package/boot/uboot-tools/uboot-envtools/files/ramips` — fw_printenv
    config (mtd1, 0x0/0x1000/0x20000)
11. `package/base-files/files/lib/upgrade/nand.sh` — `CI_KERNPART_EXT`
    support (`patches/0003`): platform.sh's breed/pb-boot detection
    sets this so sysupgrade writes the kernel to **both** slots; the
    variable is an x-wrt extension that stock ImmortalWrt ignores, so
    without this patch the detection lines are decorative and
    sysupgrade under breed/pb-boot would leave the booted slot stale.

(The original research counted eight; 9 and 10 surfaced when lifting
the actual device commit — the first scaffold's apply script missed
both, which would have produced wrong network config and no
fw_printenv. 11 surfaced during the pb-boot safety research.)

`mt76x8/config-<kv>` additionally needs
`# CONFIG_MTD_NAND_MT7620 is not set` — mt76x8 is also `SOC_MT7620`,
so the new Kconfig symbol is visible there.

Kernel target rationale: ImmortalWrt master = 6.18 = the same kernel as
the X-Wrt build proven on this unit (6.18.44). One variable changes
(distro), not two. The 6.12/25.12 combination is compiled by no one —
x-wrt's mt7620 has only `config-6.18`.

Image formats: `sysupgrade.bin` (nand sysupgrade tar + metadata),
`kernel1.bin`/`rootfs0.bin` (split), `factory.bin` (kernel padded to
4 MiB + UBI — the pb-boot/breed single-image format), and
`breed-factory.bin` (kernel **twice** + UBI — both slots populated).
Slot logic: with stock U-Boot the kernel lands in `kernel` (mtd8); with
breed/pb-boot detected on mtd0, in `kernel_stock` (mtd7).

Adding `nand` to the shared mt7620 subtarget is fine for this build
(only the R3 profile is compiled) but is exactly what would sink an
upstream PR — a PR-quality version needs a `ramips/mt7620-nand`
subtarget. Reassuringly mt7621 already ships `FEATURES+=nand` with 46
UBI recipes, so the ubinize/UBI/nand_do_upgrade pipeline is proven in
the target tree.

## Corrections — things that looked true and are wrong

Read before re-researching anything.

- **"There's a Breed for the R3" — there isn't.**
  `breed-mt7620-xiaomi-mini.bin` is the Mini (SPI-NOR);
  `breed-mt7621-xiaomi-r3g.bin` is the 3G (MT7621). The only
  NAND-capable Breed is for Atheros AR9344. A wrong-device bootloader
  on mtd0 is an unrecoverable brick.
- **"USB recovery will save me" — not on this unit.** The bootloader
  contains no USB/FAT support (full-partition strings scan: only
  `uboot.bin`, `test.bin`, `saveenv`). Xiaomi's USB recovery lived in
  the stock system in kernel0+rootfs0 — overwritten by X-Wrt.
- **"U-Boot has a bootloader RAM-test menu option" — not on this
  unit.** The real menu is 1/2/3/4/9 only; there is no option 7, and
  **option 9 is "Load Boot Loader code then write to Flash"** — it
  writes mtd0. Wiki lore about option layouts is not portable.
- **"A bootloader image can be dry-run from a running U-Boot" — no.**
  Warm-chaining pb-boot via `tftpboot`+`bootm` (transfer + CRC OK,
  jump taken) died silently: no console, no HTTP, no DHCP. Bootloaders
  expect cold-reset CPU state. The result says nothing about the
  image's health — which is precisely why it can't serve as a
  validation gate.
- **"OpenWrt never had an MT7620 NAND driver" — wrong.** In-tree
  through 4.4; see history above.
- **"mt7620 on 6.12 has a bad WiFi regression" — fixed.**
  openwrt/openwrt#19128 is closed/fixed, shipping in 25.12.1.
- **"mt7620 is being deprecated" — no.** Active 2026 development
  (upstream MediaTek ethernet PR #24557, PPE offload #24515).
- **"ImmortalWrt images always include LuCI" — release images do,
  `make defconfig` does not.** The first CI build booted SSH-only;
  `CONFIG_PACKAGE_luci=y` belongs in the seed.
- **A dormant second kernel slot is not a fallback.** mtd7 holds a
  CRC-valid stock 2.6.36 kernel whose rootfs no longer exists — it
  boots to a panic. Both slots share one UBI.
- **"pb-boot recovery is at 192.168.15.1" — wrong, it's 192.168.1.1.**
  Confirmed three ways: the binary's compiled-in env, and two
  independent tutorials. pb-boot also ignores Xiaomi's A/B boot flags
  entirely (no flag strings in the binary) — it always boots
  `kernel_stock` @ 0x200000, which is why x-wrt's sysupgrade mirrors
  the kernel there when it detects pb-boot/breed on mtd0.
- **"pb-boot can be verified against an official hash" — no longer
  possible.** `downloads.pangubox.com` is dead, the Wayback Machine
  never captured the file, no forum or repo ever published its hash,
  and GitHub code search finds nothing. The strongest available
  verification is internal (self-CRC + cold-boot entry code + the
  community record). See RECOVERY.md appendix for the full verdict.

## Questions that were open, now answered

- *Does the driver build at 6.18 on ImmortalWrt?* **Yes** — CI-built
  2026-08-30, first try.
- *Has anyone booted an R3 on 6.18 with ImmortalWrt?* **Yes — this
  unit, 2026-08-31**, initramfs from RAM: all 10 partitions, backup-
  identical reads, both radios on air, switch OK.
- *Does `bootcmd=tftp` give a serial-free recovery path?* Observed
  silent on a healthy boot; whether it fires after a kernel CRC failure
  remains untested (and untestable without inducing that state).
- *Will stock U-Boot load a uImage larger than the 4 MiB kernel slot
  via TFTP?* **Yes** — the 8.9 MB initramfs loads and boots fine from
  RAM (the 4 MiB limit is the flash slot, not TFTP).

Still open: whether current OpenWrt maintainers would accept a proper
driver in 2026 (Golle's refusal is from 2022); whether the NAND is
BMT-formatted (x-wrt's own simple BBT works, mildly encouraging);
whether U-Boot passes `bootargs` (env has none — the `cmdlinepart`
mtd0-unlock trick was never tested and is moot now).

## Ranked approaches (from the original research)

1. Mainline-quality driver + `mt7620-nand` subtarget → OpenWrt PR —
   months, refused twice, only worth it for its own sake.
2. Same quality bar, ImmortalWrt only — plausible; they ship the patch
   on 18.06-k5.4. No ImmortalWrt issue/PR mentions miwifi-r3.
3. Fork ImmortalWrt master, lift the two x-wrt commits — **done, this
   repo.**
4. Same against openwrt-25.12 (6.12) — the installer script supports
   it; combination still compiled by no one.
5. Rebasable patch series + CI — **done, this repo.**
6. Stay on X-Wrt — the fallback that remains available.
7. SDK-backport packages onto 18.06-k5.4 — leaf packages only.
8. Kernel in NAND, rootfs on USB — fails on initramfs/extroot
   interaction and sysupgrade; not worth it.
9. 25.12 userspace on the 18.06 base — impossible; the 25.12 feeds are
   apk-v3 (`ADBd` container), opkg cannot read them, plus musl time64,
   vermagic, ucode-LuCI, procd/ubusd singletons.

## Reference

Local:
- `D:\r3-backup\` — verified full NAND backup (see RECOVERY.md)
- `D:\xiaomi mir3\` — pb-boot image, stock firmware 2.11.20, padavan
  .trx, old openwrt builds, STOK-exploit notes (`ssh r3.txt` — stock
  firmware only: uses `nvram`, which X-Wrt-family firmware lacks)

Upstream:
- x-wrt source github.com/x-wrt/x-wrt · images downloads.x-wrt.com/rom/
- ImmortalWrt github.com/immortalwrt/immortalwrt (master 6.18,
  openwrt-25.12 6.12, openwrt-18.06-k5.4 5.4)
- OpenWrt ToH openwrt.org/toh/xiaomi/mir3 (listed unsupported)
- Breed breed.hackpascal.net (no R3 build — see corrections)

Community R3 efforts: ptpt52/lede-source,
JustNoLimit/Xiaomi-MiWifi-R3-OpenWrt-Stable,
XFY9326/Xiaomi-R3-OpenWrt-Stable, astolfogit/miwifi-r3-production,
SourceForge mir3-openwrt (5.10 builds), OpenWrt forum thread 140403.
