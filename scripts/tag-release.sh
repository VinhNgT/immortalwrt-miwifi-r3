#!/bin/sh
# tag-release.sh - cut a release tag and push it.
#
#   usage: scripts/tag-release.sh [immortalwrt-ref]    (default: v25.12.1)
#
# Computes the next free <ref>-rN release number from the tags already on
# origin, tags the current HEAD, and pushes the tag. The tag push triggers
# .github/workflows/release.yml, which builds that ImmortalWrt version and
# publishes the GitHub release. Numbering is per upstream version and
# collision-proof: git refuses to push a tag that already exists on origin.
set -eu

REF=${1:-v25.12.1}

[ -z "$(git status --porcelain)" ] || {
	echo "ERROR: working tree not clean - commit or stash first" >&2
	exit 1
}

git fetch -q origin

# A release must be cut from a commit that is on the published branch: the
# workflow builds the tagged commit, and a tag on an unpushed commit would
# release code that main never saw.
git merge-base --is-ancestor HEAD origin/main || {
	echo "ERROR: HEAD is not on origin/main - push it first" >&2
	exit 1
}

# Highest existing rN for this upstream version (max + 1, so a deleted
# release can never cause a reused number). The awk prefix test avoids
# treating dots in the ref as regex; the numeric test drops the ^{}
# dereference lines git ls-remote prints for annotated tags.
last=$(git ls-remote --tags origin "refs/tags/${REF}-r*" \
	| awk -v p="refs/tags/${REF}-r" '
		index($2, p) == 1 {
			n = substr($2, length(p) + 1)
			if (n ~ /^[0-9]+$/) print n
		}' \
	| sort -n | tail -n1)
TAG="${REF}-r$(( ${last:-0} + 1 ))"

git tag -a "$TAG" -m "ImmortalWrt $REF for Mi Router 3, port build $TAG"
git push origin "$TAG"

echo "Pushed $TAG - the release workflow is building it now."
