# Development guide

How to build, test, and release this port. What the port changes and
why: [PORT-NOTES.md](PORT-NOTES.md). How the conclusions were reached
(dead ends included): [RESEARCH-LOG.md](RESEARCH-LOG.md).

## Repo layout

| | |
|---|---|
| `patches/` | five-commit `git am` series vs ImmortalWrt master `db5c5de` (driver, device, dual-slot nand.sh, ECC reporting, ImageBuilder feeds) — the reviewable/upstreamable form |
| `scripts/apply-r3-support.sh` | idempotent installer; auto-detects `KERNEL_PATCHVER` (works on 6.12 and 6.18 trees) |
| `scripts/trim-mt7620-to-r3.sh` | strips all other mt7620 device recipes so the ImageBuilder offers only the R3 profile (CI runs it after the installer) |
| `scripts/tag-release.sh` | cuts a release: computes the next `<version>-rN`, tags HEAD, pushes — the tag push triggers the release build |
| `scripts/fetch-vendor.sh` | refreshes `vendor/x-wrt/` from x-wrt master and records the HEAD sha read |
| `vendor/x-wrt/` | pinned x-wrt sources + [PROVENANCE.md](../vendor/x-wrt/PROVENANCE.md) |
| `config.seed` | build seed (target + device + LuCI + kmod/IB/ccache options, each explained inline) |
| `docker/`, `build.ps1` | local containerized build |
| `.github/workflows/release.yml` | CI: tag push → build + publish release; manual dispatch → test build (artifacts only) |
| `docs/GUIDE.md`, `docs/RECOVERY.md` | end-user documentation |
| `docs/PORT-NOTES.md`, `docs/RESEARCH-LOG.md`, `docs/boot-logs/` | development documentation and evidence |
| `reference/` | upstream file snapshots used during analysis |

## How the port is applied

Two equivalent mechanisms, kept in lockstep (verified by tree-diff):

- **`patches/0001–0005`** — a `git am` series against ImmortalWrt
  master `db5c5de`; the form a reviewer or upstream would want.
- **`scripts/apply-r3-support.sh <tree>`** — copies/edits files
  directly, guarded and idempotent; version-aware, so it works on
  release trees (6.12) as well as master (6.18). CI uses this one.

Any change to the port must land in **both** (a patch series commit
and the corresponding installer step).

## Building locally

**Docker** (Windows host): `.\build.ps1` — builds the `iwrt-builder`
image, clones ImmortalWrt into a named volume (`iwrt-src`, so re-runs
are fast), applies the patch series, and drops images in `out\`.
`.\build.ps1 -Shell` opens an interactive shell in the build
container instead.

**Any Linux tree:**

```bash
git clone https://github.com/immortalwrt/immortalwrt.git
./scripts/apply-r3-support.sh immortalwrt
cd immortalwrt
./scripts/feeds update -a && ./scripts/feeds install -a
cp ../config.seed .config && make defconfig
make -j"$(nproc)" download && make -j"$(nproc)"
```

Images land in `bin/targets/ramips/mt7620/`.

## Test builds in CI

Dispatch the release workflow manually ("Run workflow" on the Actions
page) with any ImmortalWrt ref — it runs the full pipeline and
uploads the images as workflow **artifacts**, publishing nothing. Use
this to shake out a port change before cutting a release.

## Cutting a release

```bash
sh scripts/tag-release.sh v25.12.1
```

The script refuses a dirty tree or a HEAD not on `origin/main`,
computes the next free `<version>-rN` from origin's tags (max + 1, so
deleted releases never cause number reuse), tags HEAD, and pushes the
tag. The tag push triggers `.github/workflows/release.yml`, which
derives the ImmortalWrt version from the tag name, builds it, and
publishes the GitHub release: all image formats, the manifest,
`sha256sums`, and the build's ImageBuilder, with notes recording the
upstream commit, port commit, and kernel package version.

Rules:

- **Releases are immutable.** Every build has a unique kernel
  vermagic, so a release's ImageBuilder must stay downloadable
  unchanged for as long as anyone runs that release's image. Never
  edit a published release's assets; any rebuild is the next `-rN`.
- **Failure recovery:** if the build fails, fix and re-run the same
  workflow run — the tag stays valid. If publishing half-succeeded,
  delete the incomplete release (not the tag) and re-run.

## CI internals

The authoritative documentation is the comments in
[release.yml](../.github/workflows/release.yml) itself; the shape:

- **Caches**: `dl/` (exact key per ref; release tarballs are frozen),
  toolchain + host trees (keyed on ref + toolchain sources +
  `config.seed` — build options enter every package's configure
  fingerprint, so restored trees must match the config or make
  re-configures on dirty state and fails), the feeds checkout (feed
  commits are pinned per ref), and ccache (saved even on failure so
  retries are cheap). Note: **any textual change to `config.seed`
  invalidates the toolchain cache** — one ~40 min rebuild, then
  cached again.
- **Guards**: after `make defconfig`, the workflow greps the expanded
  `.config` for load-bearing symbols (`CCACHE`, `ALL_KMODS`, `IB`) —
  defconfig silently drops symbols whose Kconfig prompt is hidden,
  and a silent drop should fail the run in minute two, not waste a
  quiet hour.
- **Failure diagnostics**: `CONFIG_BUILD_LOG=y` writes per-package
  logs, uploaded as a `build-logs` artifact when a run fails.

## Refreshing vendor files

`sh scripts/fetch-vendor.sh` re-downloads the driver, DTS, and
Kconfig-hook patch variants from x-wrt master and records the HEAD
sha it read into `vendor/x-wrt/HEAD.sha`. x-wrt rebases its patch
stack continuously, so file contents are vendored rather than commit
SHAs pinned — see
[PROVENANCE.md](../vendor/x-wrt/PROVENANCE.md). After a refresh,
check whether `patches/0001/0004` need regenerating against the new
driver source.

## Validating changes on hardware

The safety doctrine, in order:

1. Build → **RAM-boot the initramfs image first** (TFTP, zero flash
   writes — procedure in [RECOVERY.md](RECOVERY.md)); verify what the
   change was supposed to change.
2. Only then flash via sysupgrade.
3. Archive noteworthy boot logs under `docs/boot-logs/` — **redact
   device identifiers first** (MACs, IPs beyond the router's own
   192.168.1.1, unique IDs); the existing archived log shows the
   masking convention.

Device-private data (serial numbers, backup checksums, local paths)
never goes into tracked files — it belongs in the git-ignored
`PRIVATE-NOTES.md` at the repo root.

## Documentation policy

- `README.md` + `docs/GUIDE.md` + `docs/RECOVERY.md` are for end
  users: instructions, use cases, quirks — no build-system internals.
- `docs/DEVELOPMENT.md` (this file), `docs/PORT-NOTES.md`, and
  `docs/RESEARCH-LOG.md` are for developers.
- Docs state settled facts and must be understandable with zero
  project context. The step-by-step/trial-and-error record is kept —
  deliberately, to avoid repeating bad judgments — but only in
  `RESEARCH-LOG.md`.
