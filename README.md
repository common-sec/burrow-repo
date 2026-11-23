# burrow-repo: presets for burrow

The presets [burrow](https://github.com/common-sec/burrow-sandbox) runs, and the pipelines that
build, scan and publish their images. A preset is a pinned image plus the settings it is safe to
run with; users pick `claude` or `trivy-scan`, not an image and twelve podman flags.

| Folder | Presets | Platforms |
|---|---|---|
| `presets/claude`, `codex`, `opencode`, `pi`, `hermes` | agent sandboxes | linux/amd64 |
| `presets/ubuntu`, `kali` | distribution sandboxes | linux/amd64, linux/arm64 |
| `presets/trivy` | `trivy`, `trivy-db`, `trivy-scan` | linux/amd64, linux/arm64 |
| `presets/trufflehog`, `semgrep` | scanners | linux/amd64, linux/arm64 |

## How publishing works

The rules are the [versioning and publishing contract](docs/CONTRACT.md). In short:

1. Every image folder is reviewed source: a Dockerfile pinned by digest, lockfiles with hashes,
   `build.conf`, and its presets. Dependabot proposes updates after a 7-day cooldown.
2. A merge to `main` that changes a folder publishes a new version `<upstream>-r<N>`
   (`claude 2.1.325-r1`): built on a native runner per platform, smoke-tested as burrow would run
   it, scanned, pushed to `ghcr.io/common-sec/burrow-presets/<folder>`.
3. The [`index` branch](https://github.com/common-sec/burrow-repo/tree/index) lists every
   published version with its digest and a ready-to-use preset pinned to that digest. Versions are
   never reused or moved; unsafe ones are yanked, not deleted.

## Use a published preset today

Until burrow reads the index (its roadmap 0.4), download a pinned preset into your presets folder:

```sh
v=2.1.325-r1   # from v1/INDEX on the index branch
curl -fsSo "$(burrow presets)/claude.preset" \
  "https://raw.githubusercontent.com/common-sec/burrow-repo/index/v1/presets/claude/$v.preset"
burrow run claude --name dev
```

## Develop

The host needs Podman (or `ENGINE=docker`), make, sh and git. `make help` lists the targets.

| Command | Does |
|---|---|
| `make check` | static checks: pins, non-root, preset keys, Dependabot coverage, workflows |
| `make image NAME=claude` | build, smoke-test and scan one folder locally |
| `make versions` | the version each folder would be published as |

Rules for changes are in [AGENTS.md](AGENTS.md). Licence: Apache-2.0 ([LICENSE](LICENSE)); the
tools inside the images keep their own licences (see each Dockerfile).
