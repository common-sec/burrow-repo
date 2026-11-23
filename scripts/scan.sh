#!/bin/sh
# Scans images:  sh scripts/scan.sh NAME|IMAGE-REF...
#   NAME       the local build localhost/burrow-preset-NAME:dev
#   IMAGE-REF  a published image by digest (registry/repo@sha256:...), for the weekly rescan
# Secrets fail the scan; HIGH and CRITICAL vulnerabilities with a fix are reported but do not
# fail it (full distribution bases always carry some; the fix is a newer pinned base: burrow
# decision 0009). Trivy runs from the pin in presets/trivy/Dockerfile, as a non-root user with no
# capabilities and a read-only root filesystem.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
[ $# -ge 1 ] || die "usage: $0 NAME|IMAGE-REF..."
TRIVY=$(awk '$1 == "FROM" { print $2; exit }' presets/trivy/Dockerfile)
case $TRIVY in *@sha256:*) ;; *) die "unpinned trivy image in presets/trivy/Dockerfile" ;; esac
repo=$(pwd)
mkdir -p .cache/trivy .cache/images
harden="--rm --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /tmp:rw,size=512m -e HOME=/tmp"
userflag="--user 1000:1000"
[ "$engine" = podman ] && [ "$("$engine" info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ] && userflag="--userns keep-id"
for a in "$@"; do
  case $a in
    *@sha256:*) img=$a; "$engine" pull -q "$img" >/dev/null ;;
    *) valid_dir "$a" || die "no image folder presets/$a"; img=localhost/burrow-preset-$a:dev ;;
  esac
  echo "== scan $img"
  tar=.cache/images/$(echo "$img" | tr '/:@' '___').tar
  rm -f "$tar"; "$engine" save -o "$tar" "$img"
  rm -rf .cache/trivy/tmp && mkdir -p .cache/trivy/tmp
  # shellcheck disable=SC2086
  "$engine" run $harden $userflag -v "$repo/.cache:/work:ro" -v "$repo/.cache/trivy:/cache" -e TMPDIR=/cache/tmp "$TRIVY" \
    image --cache-dir /cache --no-progress --skip-version-check --disable-telemetry --exit-code 1 \
    --scanners secret --input "/work/images/${tar##*/}"
  # shellcheck disable=SC2086
  "$engine" run $harden $userflag -v "$repo/.cache:/work:ro" -v "$repo/.cache/trivy:/cache" -e TMPDIR=/cache/tmp "$TRIVY" \
    image --cache-dir /cache --no-progress --skip-version-check --disable-telemetry --exit-code 0 \
    --severity HIGH,CRITICAL --scanners vuln --ignore-unfixed --input "/work/images/${tar##*/}"
  rm -rf "$tar" .cache/trivy/tmp
done
