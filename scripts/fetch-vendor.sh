#!/bin/sh
# Refresh vendor/x-wrt/ from x-wrt master.
#
# x-wrt continuously rebases its patch stack onto current OpenWrt, so commit
# SHAs are unstable and cannot be pinned. We vendor file contents instead and
# record the HEAD sha we took them from.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
V="$HERE/vendor/x-wrt"
X=https://raw.githubusercontent.com/x-wrt/x-wrt/master/target/linux/ramips
mkdir -p "$V"

curl -sSf "$X/files/drivers/mtd/maps/ralink_nand.c" -o "$V/ralink_nand.c"
curl -sSf "$X/files/drivers/mtd/maps/ralink_nand.h" -o "$V/ralink_nand.h"
curl -sSf "$X/dts/mt7620a_xiaomi_miwifi-r3.dts"     -o "$V/mt7620a_xiaomi_miwifi-r3.dts"

for kv in 6.1 6.6 6.12 6.18; do
	curl -sSf "$X/patches-$kv/0038-mtd-ralink-add-mt7620-nand-driver.patch" \
		-o "$V/0038-mtd-ralink-add-mt7620-nand-driver.patch.$kv" 2>/dev/null \
		&& echo "  patch variant $kv" || echo "  patch variant $kv: not present upstream"
done
cp "$V/0038-mtd-ralink-add-mt7620-nand-driver.patch.6.18" \
   "$V/0038-mtd-ralink-add-mt7620-nand-driver.patch"

git ls-remote https://github.com/x-wrt/x-wrt.git HEAD | cut -f1 > "$V/HEAD.sha"
echo "x-wrt HEAD: $(cat "$V/HEAD.sha")"
