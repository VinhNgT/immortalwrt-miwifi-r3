#!/bin/sh
# apply-r3-support.sh
#
# Adds Xiaomi Mi Router 3 (miwifi-r3, ramips/mt7620, 128 MiB parallel NAND)
# support to an ImmortalWrt / OpenWrt source tree.
#
#   usage: scripts/apply-r3-support.sh <path-to-tree> [kernel-version]
#
# Idempotent: safe to re-run. Detects KERNEL_PATCHVER automatically.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
V="$HERE/vendor/x-wrt"

TREE=${1:-}
[ -n "$TREE" ] || { echo "usage: $0 <path-to-immortalwrt-tree> [kernel-version]" >&2; exit 1; }
[ -d "$TREE/target/linux/ramips" ] || { echo "ERROR: $TREE is not an OpenWrt/ImmortalWrt tree" >&2; exit 1; }

R="$TREE/target/linux/ramips"
KV=${2:-$(sed -n 's/^KERNEL_PATCHVER:=\(.*\)$/\1/p' "$R/Makefile")}
[ -n "$KV" ] || { echo "ERROR: could not detect KERNEL_PATCHVER" >&2; exit 1; }

CFG="$R/mt7620/config-$KV"
PATCHES="$R/patches-$KV"
[ -f "$CFG" ] || { echo "ERROR: $CFG not found (kernel $KV not supported by this tree?)" >&2; exit 1; }
[ -d "$PATCHES" ] || { echo "ERROR: $PATCHES not found" >&2; exit 1; }

echo "tree:   $TREE"
echo "kernel: $KV"
echo "x-wrt:  $(cat "$V/HEAD.sha" 2>/dev/null || echo unknown)"
echo

say() { printf '  %-42s %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- 1. driver
mkdir -p "$R/files/drivers/mtd/maps"
cp "$V/ralink_nand.c" "$R/files/drivers/mtd/maps/ralink_nand.c"
cp "$V/ralink_nand.h" "$R/files/drivers/mtd/maps/ralink_nand.h"
say "files/drivers/mtd/maps/ralink_nand.[ch]" "copied"

# ------------------------------------------------------- 2. Kconfig/Makefile hook
P="$V/0038-mtd-ralink-add-mt7620-nand-driver.patch"
[ -f "$P.$KV" ] && P="$P.$KV"
cp "$P" "$PATCHES/0038-mtd-ralink-add-mt7620-nand-driver.patch"
say "patches-$KV/0038-...-nand-driver.patch" "copied ($(basename "$P"))"

# ------------------------------------------------------------------- 3. DTS
cp "$V/mt7620a_xiaomi_miwifi-r3.dts" "$R/dts/mt7620a_xiaomi_miwifi-r3.dts"
say "dts/mt7620a_xiaomi_miwifi-r3.dts" "copied"

# ------------------------------------------------- 4. image recipe (mt7620.mk)
MK="$R/image/mt7620.mk"
if grep -q 'xiaomi_miwifi-r3' "$MK"; then
	say "image/mt7620.mk" "already present, skipped"
else
	cat >> "$MK" <<'SNIP'

define Device/xiaomi_miwifi-r3
  SOC := mt7620a
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 32768k
  UBINIZE_OPTS := -E 5
  IMAGES += kernel1.bin rootfs0.bin breed-factory.bin factory.bin
  IMAGE/kernel1.bin := append-kernel | check-size $$(KERNEL_SIZE)
  IMAGE/rootfs0.bin := append-ubi | check-size
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  IMAGE/factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | append-ubi | check-size
  IMAGE/breed-factory.bin := append-kernel | pad-to $$(KERNEL_SIZE) | \
	append-kernel | pad-to $$(KERNEL_SIZE) | \
	append-ubi | check-size
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router R3
  DEVICE_PACKAGES := kmod-mt76x2 kmod-usb2 kmod-usb-ohci uboot-envtools
endef
TARGET_DEVICES += xiaomi_miwifi-r3
SNIP
	say "image/mt7620.mk" "device block appended"
fi

# ------------------------------------------------ 5. subtarget FEATURES += nand
TMK="$R/mt7620/target.mk"
if grep -qE '^FEATURES\+=.*\bnand\b' "$TMK"; then
	say "mt7620/target.mk" "already has nand, skipped"
else
	sed -i 's/^\(FEATURES+=.*\)$/\1 nand/' "$TMK"
	say "mt7620/target.mk" "FEATURES += nand"
fi

# ------------------------------------------------------ 6. kernel config symbols
added=0
for sym in \
	'CONFIG_MTD_NAND_MT7620=y' \
	'CONFIG_MTD_UBI=y' \
	'CONFIG_MTD_UBI_BEB_LIMIT=20' \
	'CONFIG_MTD_UBI_BLOCK=y' \
	'CONFIG_MTD_UBI_WL_THRESHOLD=4096' \
	'CONFIG_UBIFS_FS=y' \
	'CONFIG_UBIFS_FS_ADVANCED_COMPR=y' \
	'# CONFIG_UBIFS_FS_ZSTD is not set' \
	'CONFIG_CRC16=y' \
	'CONFIG_CRYPTO_DEFLATE=y' \
	'CONFIG_CRYPTO_HASH_INFO=y' \
	'CONFIG_CRYPTO_LZO=y' \
	'CONFIG_LZO_COMPRESS=y' \
	'CONFIG_LZO_DECOMPRESS=y' \
	'CONFIG_ZLIB_DEFLATE=y' \
	'CONFIG_ZLIB_INFLATE=y'
do
	name=$(printf '%s' "$sym" | sed 's/^# //; s/[= ].*//')
	grep -q "^${name}[= ]" "$CFG" 2>/dev/null && continue
	grep -q "^# ${name} is not set" "$CFG" 2>/dev/null && continue
	printf '%s\n' "$sym" >> "$CFG"
	added=$((added+1))
done
say "mt7620/config-$KV" "$added symbol(s) added"

# mt76x8 is also SOC_MT7620, so the new Kconfig symbol is visible there too
CFG8="$R/mt76x8/config-$KV"
if [ -f "$CFG8" ] && ! grep -q 'CONFIG_MTD_NAND_MT7620' "$CFG8"; then
	printf '%s\n' '# CONFIG_MTD_NAND_MT7620 is not set' >> "$CFG8"
	say "mt76x8/config-$KV" "MTD_NAND_MT7620 disabled"
else
	say "mt76x8/config-$KV" "ok, skipped"
fi

# ------------------------------------------------------------ 7. sysupgrade case
PS="$R/mt7620/base-files/lib/upgrade/platform.sh"
if grep -q 'xiaomi,miwifi-r3' "$PS"; then
	say "mt7620/.../platform.sh" "already present, skipped"
else
	awk '
	/^\t\*\)$/ && !done {
		print "\txiaomi,miwifi-r3)"
		print "\t\t# match the slot the running bootloader actually boots from"
		print "\t\tdd if=/dev/mtd0 bs=64 count=1 2>/dev/null | grep -qi breed && CI_KERNPART_EXT=\"kernel_stock\""
		print "\t\tdd if=/dev/mtd7 bs=64 count=1 2>/dev/null | grep -o MIPS.*Linux | grep -qi X-WRT && CI_KERNPART_EXT=\"kernel_stock\""
		print "\t\tdd if=/dev/mtd7 bs=64 count=1 2>/dev/null | grep -o MIPS.*Linux | grep -qi NATCAP && CI_KERNPART_EXT=\"kernel0_rsvd\""
		print "\t\tdd if=/dev/mtd0 2>/dev/null | grep -qi pb-boot && CI_KERNPART_EXT=\"kernel_stock\""
		print "\t\tnand_do_upgrade \"$1\""
		print "\t\t;;"
		done=1
	}
	{ print }
	' "$PS" > "$PS.new" && mv "$PS.new" "$PS"
	say "mt7620/.../platform.sh" "miwifi-r3 case inserted"
fi

# ------------------------------------- 8. network config (switch ports + MACs)
NW="$R/mt7620/base-files/etc/board.d/02_network"
if grep -q 'xiaomi,miwifi-r3' "$NW"; then
	say "mt7620/.../02_network" "already present, skipped"
else
	grep -q 'zbtlink,zbt-we1026-5g-16m)' "$NW" || { echo "ERROR: 02_network anchor missing" >&2; exit 1; }
	grep -q 'zyxel,keenetic-lite-iii-a)' "$NW" || { echo "ERROR: 02_network anchor missing" >&2; exit 1; }
	awk '
	/^\tzbtlink,zbt-we1026-5g-16m\)$/ && !sw {
		print "\txiaomi,miwifi-r3)"
		print "\t\tucidef_add_switch \"switch0\" \\"
		print "\t\t\t\"1:lan\" \"4:lan\" \"0:wan\" \"6@eth0\""
		print "\t\t;;"
		sw=1
	}
	/^\tzyxel,keenetic-lite-iii-a\)$/ && !mac {
		print "\txiaomi,miwifi-r3)"
		print "\t\twan_mac=$(mtd_get_mac_binary factory 0x28)"
		print "\t\tlan_mac=$(macaddr_setbit_la \"$wan_mac\")"
		print "\t\t;;"
		mac=1
	}
	{ print }
	' "$NW" > "$NW.new" && mv "$NW.new" "$NW"
	say "mt7620/.../02_network" "switch + MAC cases inserted"
fi

# --------------------------------------------- 9. uboot-envtools (fw_printenv)
UE="$TREE/package/boot/uboot-tools/uboot-envtools/files/ramips"
[ -f "$UE" ] || UE="$TREE/package/boot/uboot-envtools/files/ramips"
if [ ! -f "$UE" ]; then
	say "uboot-envtools/files/ramips" "NOT FOUND - add xiaomi,miwifi-r3 by hand"
elif grep -q 'xiaomi,miwifi-r3' "$UE"; then
	say "uboot-envtools/files/ramips" "already present, skipped"
else
	awk '
	{ print }
	/^xiaomi,mi-router-4\|\\$/ && !done {
		print "xiaomi,miwifi-r3|\\"
		done=1
	}
	' "$UE" > "$UE.new" && mv "$UE.new" "$UE"
	say "uboot-envtools/files/ramips" "miwifi-r3 entry inserted"
fi

# ------------------------------- 10. nand.sh dual-slot kernel (CI_KERNPART_EXT)
NS="$TREE/package/base-files/files/lib/upgrade/nand.sh"
if grep -q 'CI_KERNPART_EXT' "$NS" 2>/dev/null; then
	say "base-files/.../nand.sh" "already present, skipped"
else
	P3=$(ls "$HERE"/patches/0003-*.patch 2>/dev/null | head -n1)
	if [ -n "$P3" ] && patch -d "$TREE" -p1 -N -s < "$P3"; then
		say "base-files/.../nand.sh" "CI_KERNPART_EXT support applied"
	else
		echo "ERROR: nand.sh patch failed - apply patches/0003 by hand" >&2
		exit 1
	fi
fi

# --------------------------- 11. driver: report bitflips so UBI can scrub
DRV="$R/files/drivers/mtd/maps/ralink_nand.c"
if grep -q 'ranfc_ecc_corrected' "$DRV" 2>/dev/null; then
	say "files/.../ralink_nand.c (ecc report)" "already present, skipped"
else
	P4=$(ls "$HERE"/patches/0004-*.patch 2>/dev/null | head -n1)
	if [ -n "$P4" ] && patch -d "$TREE" -p1 -N -s < "$P4"; then
		say "files/.../ralink_nand.c (ecc report)" "bitflip reporting applied"
	else
		echo "ERROR: ralink_nand.c ecc-report patch failed - apply patches/0004 by hand" >&2
		exit 1
	fi
fi

# ------------------ 12. ImageBuilder: userland feeds for standalone apk builds
IBMK="$TREE/target/imagebuilder/Makefile"
if grep -q 'Remote userland feeds' "$IBMK" 2>/dev/null; then
	say "target/imagebuilder/Makefile" "already present, skipped"
else
	P5=$(ls "$HERE"/patches/0005-*.patch 2>/dev/null | head -n1)
	if [ -n "$P5" ] && patch -d "$TREE" -p1 -N -s < "$P5"; then
		say "target/imagebuilder/Makefile" "userland feeds applied"
	else
		echo "ERROR: imagebuilder patch failed - apply patches/0005 by hand" >&2
		exit 1
	fi
fi

echo
echo "Done. Next:"
echo "  cd $TREE"
echo "  ./scripts/feeds update -a && ./scripts/feeds install -a"
echo "  make menuconfig   # Target: Ralink MIPS / Subtarget: MT7620 / Profile: Xiaomi Mi Router R3"
echo "  make -j\$(nproc) V=s"
