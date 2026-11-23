#!/bin/sh
# Static checks of the source, before anything is built (`make check`, CI on every pull request).
# Needs only sh, awk and sha256sum: no container, no network. Each rule is in docs/CONTRACT.md.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

fail=0
bad() { echo "check: $*" >&2; fail=1; }

# Preset keys burrow (main) accepts. WORKDIR and MOUNT (burrow decision 0012, PR 16) are added
# here once a burrow release has them and presets can say which release they need (MIN_BURROW).
preset_keys=" NAME DESCRIPTION IMAGE WORKSPACE_MODE NETWORK ALLOW ENV ENGINE RUN_AS MEMORY ARGS CACHE CAP_ADD "
conf_keys=" UPSTREAM PLATFORMS SMOKE_ENTRYPOINT SMOKE MIN_BURROW "
seen_names=" "

for d in $(image_dirs); do
  valid_dir "$d" || { bad "presets/$d: folder name must be 2 to 32 of a-z, 0-9, -"; continue; }
  for f in Dockerfile build.conf; do [ -f "presets/$d/$f" ] || bad "presets/$d: missing $f"; done
  [ -f "presets/$d/build.conf" ] || continue

  # build.conf: known keys only, a readable upstream version, known platforms.
  while IFS= read -r line; do
    case $line in ''|'#'*) continue ;; esac
    k=${line%%=*}
    case $conf_keys in *" $k "*) ;; *) bad "presets/$d/build.conf: unknown key '$k'" ;; esac
  done < "presets/$d/build.conf"
  (upstream "$d" >/dev/null) || bad "presets/$d: no upstream version"
  for p in $(platforms "$d"); do
    case $p in linux/amd64|linux/arm64) ;; *) bad "presets/$d: platform '$p' is not linux/amd64 or linux/arm64" ;; esac
  done
  [ -n "$(conf "$d" SMOKE_ENTRYPOINT)" ] || bad "presets/$d/build.conf: SMOKE_ENTRYPOINT is required (the smoke test)"

  # Dockerfile: every base pinned by digest (D1); the image ends as a non-root user.
  if [ -f "presets/$d/Dockerfile" ]; then
    awk '$1 == "FROM" && $2 !~ /@sha256:[0-9a-f]{64}$/ { print FILENAME ": unpinned FROM " $2; e = 1 } END { exit e }' \
      "presets/$d/Dockerfile" >&2 || fail=1
    u=$(awk '$1 == "USER" { u = $2 } END { print u }' "presets/$d/Dockerfile")
    case $u in
      '') bad "presets/$d/Dockerfile: no USER (images run as a non-root user by default)" ;;
      0|0:*|root|root:*) bad "presets/$d/Dockerfile: last USER is root" ;;
    esac
  fi

  # Lockfiles that Dependabot must see.
  for eco in docker npm pip; do
    case $eco in
      docker) need=1 ;;
      npm) [ -f "presets/$d/package-lock.json" ] && need=1 || need=0 ;;
      pip) [ -f "presets/$d/requirements.txt" ] && need=1 || need=0 ;;
    esac
    [ "$need" = 1 ] || continue
    awk -v eco="$eco" -v dir="/presets/$d" '
      /package-ecosystem:/ { cur = $NF; gsub(/"/, "", cur) }
      cur == eco && ($NF == dir || $NF == "\"" dir "\"") { ok = 1 }
      END { exit !ok }' .github/dependabot.yml || bad ".github/dependabot.yml: /presets/$d is not in the $eco ecosystem"
  done

  # Presets: at least one; known keys; one key per line; NAME unique and equal to the file name;
  # IMAGE is the local build of this folder (the pipeline pins the published digest); never root.
  n=0
  for f in $(presets_of "$d"); do
    n=$((n + 1))
    dup=$(awk '/^[A-Z_]+=/ { k = substr($0, 1, index($0, "=") - 1); if (c[k]++) print k }' "$f")
    [ -z "$dup" ] || bad "$f: key set twice: $dup"
    while IFS= read -r line; do
      case $line in ''|'#'*) continue ;; esac
      case $line in *=*) ;; *) bad "$f: not KEY=VALUE: $line"; continue ;; esac
      k=${line%%=*}
      case $preset_keys in *" $k "*) ;; *) bad "$f: unknown key '$k'" ;; esac
    done < "$f"
    name=$(key "$f" NAME); base=$(basename "$f" .preset)
    [ "$name" = "$base" ] || bad "$f: NAME=$name must match the file name ($base)"
    case $seen_names in *" $name "*) bad "$f: NAME $name used twice" ;; esac
    seen_names="$seen_names$name "
    [ "$(key "$f" IMAGE)" = "localhost/burrow-preset-$d:dev" ] || bad "$f: IMAGE must be localhost/burrow-preset-$d:dev (the pipeline pins the published digest)"
    case $(key "$f" RUN_AS) in 0|0:*) bad "$f: published presets never ask for root (burrow decisions 0011, 0013)" ;; esac
  done
  [ "$n" -gt 0 ] || bad "presets/$d: no .preset file"
done

# Workflows: only actions/checkout, pinned by commit SHA (AGENTS.md).
for w in .github/workflows/*.yml; do
  [ -f "$w" ] || continue
  other=$(grep -n 'uses:' "$w" | grep -v -E 'uses: actions/checkout@[0-9a-f]{40}( |$)' || true)
  [ -z "$other" ] || bad "$w: only actions/checkout pinned by SHA is allowed: $other"
done

# YANKED: NAME VERSION REASON..., names and versions that exist in the source tree's form.
if [ -f YANKED ]; then
  awk 'NF && $1 !~ /^#/ && (NF < 3 || $1 !~ /^[a-z0-9-]+$/ || $2 !~ /^[A-Za-z0-9._-]+-r[0-9]+$/) { print "check: YANKED:" NR ": want NAME VERSION REASON"; e = 1 } END { exit e }' YANKED >&2 || fail=1
fi

# The scripts parse.
for s in scripts/*.sh; do sh -n "$s" || bad "$s does not parse"; done

[ "$fail" = 0 ] && echo "check: ok ($(image_dirs | wc -l | tr -d ' ') image folders)"
exit "$fail"
