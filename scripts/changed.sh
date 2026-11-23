#!/bin/sh
# Which image folders a change touches:
#   sh scripts/changed.sh BASE       folders changed between BASE and HEAD (all of them when the
#                                    scripts or workflows changed)
#   sh scripts/changed.sh            every folder
#   sh scripts/changed.sh --json N.. the names as a JSON array (for a GitHub Actions matrix)
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
if [ "${1:-}" = --json ]; then
  shift; sep=; printf '['
  for n in "$@"; do valid_dir "$n" || die "no image folder presets/$n"; printf '%s"%s"' "$sep" "$n"; sep=,; done
  printf ']\n'; exit 0
fi
if [ $# -eq 0 ]; then image_dirs | tr '\n' ' '; echo; exit 0; fi
files=$(git diff --name-only "$1"...HEAD)
if echo "$files" | grep -q -E '^(scripts/|Makefile$|\.github/workflows/)'; then image_dirs | tr '\n' ' '; echo; exit 0; fi
for d in $(echo "$files" | awk -F/ '$1 == "presets" && NF > 2 { print $2 }' | LC_ALL=C sort -u); do
  valid_dir "$d" && printf '%s ' "$d"
done
echo
