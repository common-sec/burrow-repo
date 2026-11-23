#!/bin/sh
# The publish pipeline's steps (docs/CONTRACT.md). Run by .github/workflows/publish.yml; each step
# can be run by hand against a local index folder (a checkout of the `index` branch).
#   sh scripts/publish.sh plan INDEX            image folders whose source is not published yet
#   sh scripts/publish.sh matrix INDEX          the same, as a GitHub Actions matrix (JSON)
#   sh scripts/publish.sh versions INDEX        the version each folder gets, and whether it is new
#   sh scripts/publish.sh push NAME ARCH INDEX  build, smoke-test, scan and push one platform
#   sh scripts/publish.sh release NAME INDEX    multi-platform manifest, then the index entries
#   sh scripts/publish.sh status INDEX          apply YANKED to the index
#   sh scripts/publish.sh index INDEX           rewrite v1/INDEX and v1/SHA256SUMS
# REGISTRY (default ghcr.io/common-sec/burrow-presets), ENGINE (default podman).
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
arch_ok() { case $1 in amd64|arm64) ;; *) die "arch must be amd64 or arm64" ;; esac; }

plan() {
  for d in $(image_dirs); do
    r=$(version "$1" "$d") || exit 1
    [ "${r#* }" = new ] && echo "$d"
  done
  return 0
}

matrix() {
  sep=; printf '{"include":['
  ds=$(plan "$1") || exit 1
  for d in $ds; do
    for p in $(platforms "$d"); do
      a=${p#linux/}
      r=ubuntu-24.04; [ "$a" = arm64 ] && r=ubuntu-24.04-arm
      printf '%s{"name":"%s","arch":"%s","runner":"%s"}' "$sep" "$d" "$a" "$r"; sep=,
    done
  done
  printf ']}\n'
}

push() {
  d=$1; a=$2; arch_ok "$a"; valid_dir "$d" || die "no image folder presets/$d"
  r=$(version "$3" "$d") || exit 1; v=${r% *}
  [ "${r#* }" = new ] || die "$d $v is already published"
  platforms "$d" | grep -qx "linux/$a" || die "$d is not built for linux/$a (build.conf PLATFORMS)"
  sh scripts/build.sh "$d" "linux/$a"
  sh scripts/smoke.sh "$d"
  sh scripts/scan.sh "$d"
  # The per-platform tag only exists so that `release` can assemble the manifest list. It is not
  # part of the contract: clients use the multi-platform digest from the index.
  ref=$REGISTRY/$d:$v-$a
  "$engine" tag "localhost/burrow-preset-$d:dev" "$ref"
  "$engine" push --digestfile ".cache/$d-$a.digest" "$ref"
  echo "pushed $ref@$(cat ".cache/$d-$a.digest")"
}

release() {
  d=$1; idx=$2; valid_dir "$d" || die "no image folder presets/$d"
  r=$(version "$idx" "$d") || exit 1; v=${r% *}
  [ "${r#* }" = new ] || die "$d $v is already published"
  u=$(upstream "$d"); h=$(inputs "$d"); ref=$REGISTRY/$d:$v
  list=localhost/burrow-release-$d:$v
  "$engine" manifest rm "$list" >/dev/null 2>&1 || true
  "$engine" manifest create "$list" >/dev/null
  for p in $(platforms "$d"); do
    "$engine" manifest add "$list" "docker://$ref-${p#linux/}" >/dev/null
  done
  mkdir -p .cache
  "$engine" manifest push --all --digestfile ".cache/$d.digest" "$list" "docker://$ref"
  digest=$(cat ".cache/$d.digest")
  case $digest in sha256:*) ;; *) die "no digest for $ref" ;; esac
  # Platform digests, as recorded in the manifest list we pushed.
  pd=$("$engine" manifest inspect "$list" | tr ',{}' '\n\n\n' | awk -F'"' '
      $2 == "digest" { dg = $4 } $2 == "architecture" { printf "%s%s=%s", s, $4, dg; s = "," }')
  "$engine" manifest rm "$list" >/dev/null 2>&1 || true

  t=$(now); commit=$(git rev-parse HEAD)
  run=local; [ -n "${GITHUB_RUN_ID:-}" ] && run=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
  mkdir -p "$idx/v1/images"
  printf '%s %s %s %s %s\n' "$v" "$h" "$digest" "$t" "$commit" >> "$(ledger "$idx" "$d")"
  for f in $(presets_of "$d"); do
    n=$(key "$f" NAME); out=$idx/v1/presets/$n
    mkdir -p "$out"
    { echo "# Published by https://github.com/common-sec/burrow-repo: $d $v, source $commit, $t."
      echo "# Verify: the IMAGE digest below is the one listed in v1/INDEX and v1/SHA256SUMS."
      awk -v img="$ref@$digest" 'index($0, "IMAGE=") == 1 { print "IMAGE=" img; next } { print }' "$f"
    } > "$out/$v.preset"
    { echo "NAME=$n"
      echo "IMAGE_FOLDER=$d"
      echo "VERSION=$v"
      echo "UPSTREAM=$u"
      echo "REVISION=${v##*-r}"
      echo "IMAGE=$ref@$digest"
      echo "PLATFORMS=$(platforms "$d" | paste -sd, -)"
      echo "PLATFORM_DIGESTS=$pd"
      echo "INPUTS_SHA256=$h"
      echo "SOURCE_REPOSITORY=https://github.com/common-sec/burrow-repo"
      echo "SOURCE_COMMIT=$commit"
      echo "PUBLISHED=$t"
      echo "WORKFLOW_RUN=$run"
      echo "MIN_BURROW=$(conf "$d" MIN_BURROW)"
      echo "STATUS=active"
      echo "STATUS_REASON="
    } > "$out/$v.meta"
  done
  echo "released $ref@$digest"
}

# status INDEX: every version listed in YANKED becomes STATUS=yanked with its reason; a version
# removed from YANKED becomes active again. Images are never deleted (docs/CONTRACT.md, "Yanking").
status() {
  idx=$1
  for m in "$idx"/v1/presets/*/*.meta; do
    [ -f "$m" ] || continue
    n=$(key "$m" NAME); v=$(key "$m" VERSION)
    r=$( [ -f YANKED ] && awk -v n="$n" -v v="$v" '$1 == n && $2 == v { $1 = ""; $2 = ""; sub(/^  /, ""); print; exit }' YANKED || true)
    s=active; [ -n "$r" ] && s=yanked
    awk -v s="$s" -v r="$r" '
      index($0, "STATUS=") == 1 { print "STATUS=" s; next }
      index($0, "STATUS_REASON=") == 1 { print "STATUS_REASON=" r; next } { print }' "$m" > "$m.tmp"
    mv "$m.tmp" "$m"
  done
}

# index INDEX: v1/INDEX has one line per published preset version, oldest first per preset:
#   NAME VERSION STATUS IMAGE@DIGEST PUBLISHED
# and v1/SHA256SUMS covers every file of v1/ (docs/CONTRACT.md, "The index").
index() {
  idx=$1; mkdir -p "$idx/v1"
  echo 1 > "$idx/v1/FORMAT"
  for m in "$idx"/v1/presets/*/*.meta; do
    [ -f "$m" ] || continue
    printf '%s %s %s %s %s\n' "$(key "$m" NAME)" "$(key "$m" VERSION)" "$(key "$m" STATUS)" "$(key "$m" IMAGE)" "$(key "$m" PUBLISHED)"
  done | LC_ALL=C sort -k1,1 -k5,5 > "$idx/v1/INDEX"
  (cd "$idx/v1" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum) > "$idx/.SHA256SUMS.tmp"
  mv "$idx/.SHA256SUMS.tmp" "$idx/v1/SHA256SUMS"
}

versions() {
  for d in $(image_dirs); do r=$(version "$1" "$d") || exit 1; printf '%-12s %s\n' "$d" "$r"; done
}

[ $# -ge 1 ] || die "usage: $0 plan|matrix|versions|push|release|status|index ..."
cmd=$1; shift
case $cmd in
  plan) [ $# -eq 1 ] || die "usage: $0 plan INDEX"; plan "$1" ;;
  versions) [ $# -eq 1 ] || die "usage: $0 versions INDEX"; versions "$1" ;;
  matrix) [ $# -eq 1 ] || die "usage: $0 matrix INDEX"; matrix "$1" ;;
  push) [ $# -eq 3 ] || die "usage: $0 push NAME ARCH INDEX"; push "$@" ;;
  release) [ $# -eq 2 ] || die "usage: $0 release NAME INDEX"; release "$@" ;;
  status) [ $# -eq 1 ] || die "usage: $0 status INDEX"; status "$1" ;;
  index) [ $# -eq 1 ] || die "usage: $0 index INDEX"; index "$1" ;;
  *) die "unknown step $cmd" ;;
esac
