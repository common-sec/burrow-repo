#!/bin/sh
# Builds one image folder:  sh scripts/build.sh NAME [PLATFORM]
# Result: localhost/burrow-preset-NAME:dev (PLATFORM defaults to the host's). Local builds and CI
# use the same command; the publish pipeline tags and pushes this result (scripts/publish.sh).
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
[ $# -ge 1 ] || die "usage: $0 NAME [PLATFORM]"
valid_dir "$1" || die "no image folder presets/$1"
plat=
if [ $# -ge 2 ]; then
  case $2 in linux/amd64|linux/arm64) plat="--platform $2" ;; *) die "platform must be linux/amd64 or linux/arm64" ;; esac
fi
rev=$(git rev-parse HEAD 2>/dev/null || echo unknown)
# --pull=missing: bases come by digest, so a cached base is the same base.
# shellcheck disable=SC2086
"$engine" build --pull=missing $plat \
  --label "org.opencontainers.image.source=https://github.com/common-sec/burrow-repo" \
  --label "org.opencontainers.image.revision=$rev" \
  --label "org.opencontainers.image.version=$(upstream "$1")" \
  -t "localhost/burrow-preset-$1:dev" "presets/$1"
