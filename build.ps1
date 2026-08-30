# Build ImmortalWrt for the Xiaomi Mi Router 3 in Docker.
# Source tree + downloads live in a named volume (iwrt-src) so re-runs are fast.
# Artifacts land in .\out\
#
# Usage:  .\build.ps1            (build master)
#         .\build.ps1 -Ref master -Shell   (drop into a shell instead)
param(
    [string]$Ref = "master",
    [switch]$Shell
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot

docker build -t iwrt-builder "$repo\docker"
if ($LASTEXITCODE -ne 0) { exit 1 }

docker volume create iwrt-src | Out-Null

if ($Shell) {
    docker run -it --rm -v iwrt-src:/home/build -v "${repo}:/repo" iwrt-builder bash
} else {
    docker run --rm -e IWRT_REF=$Ref -v iwrt-src:/home/build -v "${repo}:/repo" `
        iwrt-builder bash /repo/docker/build-inside.sh
}
