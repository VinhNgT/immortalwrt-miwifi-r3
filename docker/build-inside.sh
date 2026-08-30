#!/bin/bash
# Runs INSIDE the builder container. Expects:
#   /repo             this project (bind mount, read: patches/, config.seed; write: out/)
#   /home/build       persistent named volume (source tree + downloads survive runs)
# Env:
#   IWRT_REF          git ref to build (default: master)
set -e

IWRT_REF=${IWRT_REF:-master}
cd /home/build

if [ ! -d immortalwrt ]; then
	git clone https://github.com/immortalwrt/immortalwrt.git
fi
cd immortalwrt
git config user.name "builder"
git config user.email "builder@local"

# reset to a clean upstream state, then apply the series
git am --abort 2>/dev/null || true
git fetch origin "$IWRT_REF"
git checkout -B build FETCH_HEAD
git am --3way /repo/patches/*.patch

./scripts/feeds update -a
./scripts/feeds install -a

cp /repo/config.seed .config
make defconfig

# sanity: the device must have survived defconfig
grep -q "CONFIG_TARGET_ramips_mt7620_DEVICE_xiaomi_miwifi-r3=y" .config || {
	echo "ERROR: xiaomi_miwifi-r3 profile missing after defconfig"
	exit 1
}

make -j"$(nproc)" download
make -j"$(nproc)" world || make -j1 V=s world

mkdir -p /repo/out
cp -v bin/targets/ramips/mt7620/*miwifi-r3* /repo/out/
cp -v bin/targets/ramips/mt7620/sha256sums /repo/out/ 2>/dev/null || true
echo "DONE - images in out/"
