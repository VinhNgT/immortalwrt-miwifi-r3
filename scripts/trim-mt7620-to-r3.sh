#!/bin/sh
# trim-mt7620-to-r3.sh
#
# Restricts target/linux/ramips/image/mt7620.mk to the Xiaomi Mi Router R3
# device block, so the ImageBuilder built from this tree offers exactly one
# profile (`make info` lists only xiaomi_miwifi-r3; any other PROFILE= fails).
#
#   usage: scripts/trim-mt7620-to-r3.sh <path-to-tree>
#
# Run AFTER apply-r3-support.sh (needs the R3 block to already be present)
# and BEFORE make defconfig (so .targetinfo is generated from the trimmed
# recipe list). Idempotent. Keeps everything outside `define Device/...`
# blocks (DEFAULT_SOC, shared Build/ helpers, includes) — only the other
# devices' blocks and their TARGET_DEVICES lines are dropped.
set -eu

TREE=${1:?usage: $0 <path-to-immortalwrt-tree>}
MK="$TREE/target/linux/ramips/image/mt7620.mk"
[ -f "$MK" ] || { echo "ERROR: $MK not found" >&2; exit 1; }
grep -q 'xiaomi_miwifi-r3' "$MK" || {
	echo "ERROR: R3 device block missing - run apply-r3-support.sh first" >&2
	exit 1
}

if [ "$(grep -c '^TARGET_DEVICES' "$MK")" = 1 ]; then
	echo "mt7620.mk already trimmed to xiaomi_miwifi-r3"
	exit 0
fi

before=$(grep -c '^TARGET_DEVICES' "$MK")
awk '
/^define Device\// { indev = 1; keep = ($0 ~ /xiaomi_miwifi-r3/) }
indev {
	if (keep) print
	if ($0 ~ /^endef/) indev = 0
	next
}
/^TARGET_DEVICES/ {
	if ($0 ~ /xiaomi_miwifi-r3/) print
	next
}
{ print }
' "$MK" > "$MK.new" && mv "$MK.new" "$MK"
after=$(grep -c '^TARGET_DEVICES' "$MK")

[ "$after" = 1 ] || { echo "ERROR: trim left $after TARGET_DEVICES entries" >&2; exit 1; }
echo "mt7620.mk trimmed: $before device(s) -> 1 (xiaomi_miwifi-r3)"
