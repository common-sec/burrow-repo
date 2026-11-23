# Shared functions for the scripts in this folder (sourced, not run). POSIX sh.
# The contract these functions implement is docs/CONTRACT.md: read it before changing a rule here.

# Where published images go. One repository per image folder: $REGISTRY/<folder>:<version>.
REGISTRY=${REGISTRY:-ghcr.io/common-sec/burrow-presets}
engine=${ENGINE:-podman}

die() { echo "burrow-repo: $*" >&2; exit 1; }

# image_dirs: every folder under presets/ (the "source packages"), sorted.
image_dirs() {
  for d in presets/*/; do d=${d%/}; [ -d "$d" ] && echo "${d#presets/}"; done | LC_ALL=C sort
}

# valid_dir NAME: the same name rule as a burrow preset NAME (2 to 32 of a-z, 0-9, -).
valid_dir() {
  case $1 in ''|-*|*[!a-z0-9-]*) return 1 ;; esac
  [ ${#1} -ge 2 ] && [ ${#1} -le 32 ] && [ -d "presets/$1" ]
}

# conf DIR KEY: a value from presets/DIR/build.conf (KEY=VALUE lines, # comments). Empty if unset.
conf() {
  awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "presets/$1/build.conf"
}

# platforms DIR: the platforms to build, one per line (linux/amd64 when unset).
platforms() {
  p=$(conf "$1" PLATFORMS); [ -n "$p" ] || p=linux/amd64
  echo "$p" | tr ',' '\n'
}

# upstream DIR: the upstream version this image packages (docs/CONTRACT.md, "Versions").
upstream() {
  u=$(conf "$1" UPSTREAM)
  case $u in
    npm:?*)
      pkg=${u#npm:}
      v=$(awk -v key="\"node_modules/$pkg\": {" '
            index($0, key) { found = 1; next }
            found && /"version":/ { gsub(/[",]/, "", $2); print $2; exit }' "presets/$1/package-lock.json") ;;
    pip:?*)
      pkg=${u#pip:}
      v=$(awk -v p="$pkg==" 'index($0, p) == 1 { s = substr($1, length(p) + 1); print s; exit }' "presets/$1/requirements.txt") ;;
    from)
      ref=$(awk '$1 == "FROM" { r = $2 } END { print r }' "presets/$1/Dockerfile")
      ref=${ref%%@*}; ref=${ref##*/}
      case $ref in *:*) v=${ref#*:} ;; *) v= ;; esac ;;
    fixed:?*) v=${u#fixed:} ;;
    *) die "$1: UPSTREAM must be npm:PKG, pip:PKG, from or fixed:VERSION (got '$u')" ;;
  esac
  case $v in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) die "$1: cannot read a valid upstream version from UPSTREAM=$u (got '$v')" ;;
  esac
  [ ${#v} -le 100 ] || die "$1: upstream version longer than 100 characters"
  echo "$v"
}

# inputs DIR: SHA-256 over every file of presets/DIR (path and content), so any change to the
# Dockerfile, a lockfile, build.conf or a preset gives a new revision.
inputs() {
  (cd "presets/$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
     printf '%s  %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"
   done) | sha256sum | cut -d' ' -f1
}

# ledger INDEX DIR: the file that lists every version published from presets/DIR.
ledger() { echo "$1/v1/images/$2.versions"; }

# version INDEX DIR: the version the current source of DIR gets (docs/CONTRACT.md, "Versions").
# Prints "VERSION new" when it must be published, "VERSION published" when the newest entry in the
# ledger already has exactly these inputs.
version() {
  u=$(upstream "$2"); h=$(inputs "$2"); l=$(ledger "$1" "$2")
  if [ -f "$l" ]; then
    last=$(awk 'NF && $1 !~ /^#/ { v = $1; i = $2 } END { print v " " i }' "$l")
    if [ "${last#* }" = "$h" ]; then echo "${last% *} published"; return; fi
    n=$(awk -v u="$u" 'NF && $1 !~ /^#/ { p = u "-r"; if (index($1, p) == 1) { r = substr($1, length(p) + 1); if (r ~ /^[0-9]+$/ && r + 0 > m) m = r + 0 } } END { print m + 0 }' "$l")
  else
    n=0
  fi
  echo "$u-r$((n + 1)) new"
}

# presets_of DIR: the preset files of an image folder.
presets_of() { for f in "presets/$1"/*.preset; do [ -f "$f" ] && echo "$f"; done; }

# key FILE KEY: a value from a preset file.
key() { awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1"; }
