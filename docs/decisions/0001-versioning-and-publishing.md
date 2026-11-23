# 0001: Versioning and publishing presets from burrow-repo

**Status:** proposed (2026-11-23). **Owner:** J.
**Why:** presets must be prebuilt and published, because an old burrow binary would otherwise keep
pointing at old images (J's review of burrow-sandbox PR #1). That needs a promise about versions
and where they are listed: the [contract](../CONTRACT.md). Answers
[burrow-sandbox#6](https://github.com/common-sec/burrow-sandbox/issues/6) points 1 (architecture)
and 3 (where it lives); point 2 (overrides) stays with burrow. Research:
[preset index spike](../../research/spikes/2026-11-preset-index/SPIKE.md) (issue #5).

Serves R8, D1, D7, O7, and the organisation's controls TDA-06.4, TDA-20.3, AST-14, CHG-02 and
VPM-06. SCF is credited as in secure-standard-platforms' NOTICE.md.

## Where presets live

| Option | For | Against |
|---|---|---|
| A. In burrow-sandbox | one repository | J: "I don't see github keeping up with both workstreams; sandbox tooling + presets maintenance"; Dependabot PRs for ten images bury the tool's PRs; a preset release would need a tool change |
| **B. A dedicated repository (burrow-repo)** | its own Dependabot, CI, reviewers and release rhythm; burrow-sandbox keeps only test fixtures | two repositories to keep consistent (preset keys must match what burrow accepts) |

**B.** burrow-sandbox keeps the small test presets its e2e needs (alpine, curl, trivy).

## Versions

| Option | For | Against |
|---|---|---|
| **A. `<upstream>-r<N>`, computed from the lockfile or tag and the index** | what users expect ("claude 2.1.325"); Homebrew `revision` and Debian `-N`; no hand edits, so Dependabot PRs publish on their own | `N` depends on the index, so the index must be read before building |
| B. Our own semver per preset | familiar | someone must decide major/minor for a base image bump; nothing about the tool inside is visible |
| C. Dates (`2026.11.23.1`) | simple, ordered | says nothing about the tool; two builds the same day need a counter anyway |
| D. Digests only | immutable | not readable by people; nothing to search for |

**A.**

## Where the post-build digest goes, and the index

| Option | For | Against |
|---|---|---|
| A. Into the reviewed source before merge (Homebrew's `bottle do`, a bot commit into each PR) | everything a client reads was reviewed | a bot with write access to every PR branch; a commit by `GITHUB_TOKEN` does not trigger CI again; every Dependabot PR waits for two builds |
| B. A bot PR after merge that writes the digest | reviewed | a person must merge every publish; PRs from `GITHUB_TOKEN` do not run CI; doubles review load |
| **C. An append-only `index` branch written only by the publish workflow** | no human step after the reviewed merge; full history; plain files over HTTPS or git; works without burrow | the index itself is not reviewed by a person (mitigated: branch protection, entries name their source commit and run, signing later) |
| D. The index as an OCI artifact in the registry | one place for images and index; mirrors with the images | needs an OCI client (oras or similar) to read it; not readable in a browser |
| E. A service (like formulae.brew.sh) | search, statistics | runtime cost and a service to secure; not needed for ten presets |

**C**, with signing added once D7 is decided.

## Builds

| Option | For | Against |
|---|---|---|
| **A. Native runner per platform, then a manifest list** | no emulation; each platform smoke-tested where it runs | two jobs per image; arm64 runners may cost for private repositories (*unverified*) |
| B. Emulated multi-platform build on one runner | one job | needs qemu-user-static installed on the runner (against "nothing installed on the host"); slow |
| C. Scheduled rebuilds | always the newest packages | same inputs, new digest: breaks "same inputs, same version" |

**A**, triggered by a merge that changes inputs; a weekly rescan instead of rebuilds.

## Tools and dependencies

No new dependency. The scripts are POSIX sh with awk and sha256sum, like burrow-sandbox's
`scripts/`; the pipelines use only `actions/checkout` (pinned by SHA) and the runner's podman.
Images reuse the pins burrow-sandbox already reviewed; trufflehog and semgrep reuse the pins of its
`packaging/scanners/Dockerfile`.

## Exceptions (O3)

| What | Owner | Reason | Expiry |
|---|---|---|---|
| `kali` pinned to a digest younger than 7 days (carried over from burrow decision 0009) | J | `kali-rolling` has no dated tags | when the kali image is built from a dated base, or 2027-05-22 |
| Vulnerabilities in the sandbox images do not fail the build (carried over from 0009) | J | full distribution bases always carry some; fixed by a newer pin | 2027-05-22, or earlier if minimal images replace them |

## Consequences and gaps

- burrow reads the index in roadmap 0.4 (issue #6 point 2: overrides, the lock, search). Until
  then the published presets can be downloaded from the index and used by path.
- Presets use only the keys burrow's main branch accepts. `WORKDIR` and `MOUNT` (burrow decision
  0012, PR 16) and the root confirmation (0013, PR 15) are allowed in `make check` once a burrow
  release has them and `MIN_BURROW` can name it. Root stays refused in published presets.
- The GHCR packages must be made public once (GitHub's default is private).
- The `index` branch must be protected so that only GitHub Actions can push (repository settings).
- Not yet: signatures, SBOMs, mirrors (contract section 10).
