#!/bin/sh
# The index lives on the `index` branch of this repository (docs/CONTRACT.md, "The index").
#   sh scripts/index-branch.sh fetch DIR [COMMIT]  check it out into DIR (empty if it does not
#                                                  exist yet; COMMIT "none" also means empty)
#   sh scripts/index-branch.sh push DIR MESSAGE    commit DIR and push it to the index branch
#   sh scripts/index-branch.sh current DIR         newest active image (by digest) per folder
# TOKEN (GITHUB_TOKEN in Actions) authenticates fetch and push through an HTTP header, so it never
# appears in a URL, a remote or the process list of git's children.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh
url=https://github.com/${GITHUB_REPOSITORY:-common-sec/burrow-repo}
auth() {
  if [ -n "${TOKEN:-}" ]; then
    h=$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')
    git -C "$dir" -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $h" "$@"
  else
    git -C "$dir" "$@"
  fi
}
[ $# -ge 2 ] || die "usage: $0 fetch|push|current DIR ..."
cmd=$1; dir=$2
case $dir in ''|/|.|..|/*/..|*/..) die "refusing index folder '$dir'" ;; esac
case $cmd in
  fetch)
    at=${3:-}
    rm -rf "$dir"; mkdir -p "$dir"; git -C "$dir" init -q
    git -C "$dir" checkout -q --orphan index
    if [ "$at" = none ]; then echo "index: starting empty"; exit 0; fi
    if auth fetch -q --no-tags "$url" refs/heads/index 2>/dev/null; then
      git -C "$dir" checkout -q -B index "${at:-FETCH_HEAD}"
      echo "index: $(git -C "$dir" rev-parse HEAD)"
    else
      [ -z "$at" ] || die "index branch not found, but commit $at was planned"
      echo "index: no index branch yet, starting empty"
    fi ;;
  push)
    [ $# -eq 3 ] || die "usage: $0 push DIR MESSAGE"
    git -C "$dir" add -A
    if git -C "$dir" diff --cached --quiet; then echo "index: nothing changed"; exit 0; fi
    git -C "$dir" -c user.name="burrow-repo publish" -c user.email="actions@users.noreply.github.com" \
      commit -q -m "$3"
    # No force: if the branch moved since the plan, the push fails and nothing is overwritten.
    auth push -q "$url" HEAD:refs/heads/index
    echo "index: pushed $(git -C "$dir" rev-parse HEAD)" ;;
  current)
    [ -f "$dir/v1/INDEX" ] || exit 0
    awk '$3 == "active" { r = $4; sub(/:[^:@\/]*@.*/, "", r)
                          if (!(r in p) || $5 >= p[r]) { p[r] = $5; last[r] = $4 } }
         END { for (r in last) print last[r] }' "$dir/v1/INDEX" | LC_ALL=C sort -u ;;
  *) die "unknown command $cmd" ;;
esac
