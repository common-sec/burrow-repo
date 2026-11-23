#!/bin/sh
# Smoke test of a built image:  sh scripts/smoke.sh NAME
# Starts localhost/burrow-preset-NAME:dev the way burrow starts a tool (no capabilities, no new
# privileges, read-only root, no network, the image's own non-root user) and runs the command in
# build.conf (SMOKE_ENTRYPOINT SMOKE). Fails if the image runs as root or the tool does not answer.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
[ $# -eq 1 ] || die "usage: $0 NAME"
valid_dir "$1" || die "no image folder presets/$1"
img=localhost/burrow-preset-$1:dev
u=$("$engine" image inspect --format '{{.Config.User}}' "$img")
case $u in ''|0|0:*|root|root:*) die "$img runs as root by default (USER '$u')" ;; esac
ep=$(conf "$1" SMOKE_ENTRYPOINT); args=$(conf "$1" SMOKE)
echo "== smoke $1: $ep $args (as $u)"
# shellcheck disable=SC2086
"$engine" run --rm --cap-drop ALL --security-opt no-new-privileges --read-only \
  --tmpfs /tmp:rw,size=256m -e HOME=/tmp --network none --pids-limit 256 \
  --entrypoint "$ep" "$img" $args
