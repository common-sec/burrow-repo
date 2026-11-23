# Spike: how package ecosystems build, version and index (input for the preset index)

**Issue:** [burrow-sandbox#5](https://github.com/common-sec/burrow-sandbox/issues/5). **Date:** 2026-11-23.
**Requirements:** R8, D1, D7. **Result:** the contract in [docs/CONTRACT.md](../../../docs/CONTRACT.md),
decided in [0001](../../../docs/decisions/0001-versioning-and-publishing.md).

The question from J's review of burrow-sandbox PR #1: presets must be prebuilt and published, and
found through an index, because an old burrow binary would keep pointing at old images. How do
established ecosystems build, sign, index and serve packages, and how do clients pin what they use,
when the digest is only known after the build?

Desk research only. Sources were read on 2026-11-23; anything from memory is marked *unverified*.

## Comparison

| | Homebrew | winget | Debian | Nix | OCI registries (Docker Hub, GHCR) |
|---|---|---|---|---|---|
| **Source of truth** | formula in a git repo (homebrew/core) | YAML manifests in a git repo (microsoft/winget-pkgs) | source packages in the archive *(unverified)* | expressions in a git repo (nixpkgs) | none: whatever was pushed |
| **Who builds** | CI: "Bottles for `homebrew/core` formulae are created by BrewTestBot when a pull request is submitted" [1] | nobody: the vendor's installer is referenced by URL and hash | build daemons per architecture *(unverified)* | Hydra CI into the binary cache *(unverified)* | the publisher |
| **Where the post-build hash goes** | back into the formula: BrewTestBot "updates its `bottle do` block and uploads each bottle to GitHub Packages" [1]; one `sha256` per platform [1] | `InstallerSha256` in the manifest, checked on install ("Error-Hash-Mismatch") [3] | `Packages` lists each `.deb` with its hash, `Release` lists `Packages` with its hash, `InRelease` is signed *(unverified: page not readable)* | the store path is a hash of the inputs; the output is signed by the cache | the digest *is* the address; tags point to it |
| **Version scheme** | upstream `version` + `revision`; bottle `rebuild` for "a bottle-only packaging correction" [1] | upstream version | upstream + Debian revision (`1.2-3`) *(unverified)* | upstream + input hash | free-form tags |
| **Index** | API JSON per formula with `versions`, `revision`, `bottle.stable.files` (URL and `sha256` per platform) [2] | a pre-built index the client downloads *(unverified: not on the page read)* | `Release`/`Packages` per suite and architecture | the nixpkgs revision itself; the cache answers by hash | tag list per repository; the referrers API lists "manifests with a subject relationship to a specified digest" (signatures, SBOMs) [6] |
| **Serving** | bottles on ghcr.io: `root_url` `https://ghcr.io/v2/homebrew/core`, blob URLs by sha256 [2] | the vendor's URL | mirrors | `substituters` (default cache.nixos.org) [5, partly read] | the registry |
| **Signing** | none on bottles: integrity from the sha256 in the reviewed formula *(unverified that no signature exists)* | none on manifests; review and automated validation: "automatically validated and evaluated", then "manually reviewed by a moderator" [3] | `InRelease` signed with the archive key | `trusted-public-keys` sign cache objects [5, partly read] | optional (cosign, Notation) through referrers |
| **Moving pointers** | the formula's current version; no history in the API | the newest manifest version | the suite (`stable`, `noble`) | the channel | tags: "A manifest digest may have zero, one, or many tags referencing it" [6]; tags can be re-pointed |
| **Overrides** | your own tap; `brew extract` for an old version *(unverified)* | your own source | your own repository, pinning priorities | overlays | your own image |
| **Cost to run** | GitHub Actions and GitHub Packages | GitHub and Azure validation | mirrors donated | large S3 cache | registry |

[1] https://docs.brew.sh/Bottles · [2] https://formulae.brew.sh/api/formula/jq.json ·
[3] https://learn.microsoft.com/en-us/windows/package-manager/package/repository ·
[4] https://wiki.debian.org/SecureApt (could not be read: JavaScript challenge) ·
[5] https://nix.dev/manual/nix/2.28/command-ref/conf-file (only partly read) ·
[6] https://github.com/opencontainers/distribution-spec/blob/main/spec.md (partly read) ·
[7] https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

## Answers to the issue's questions

**Who builds, and how is an update triggered?** Homebrew is the closest fit: a reviewed source
file, CI that builds per platform, and the post-build hash recorded where clients read it. burrow
already has the first half (Dockerfiles with digests and lockfiles, Dependabot with a 7-day
cooldown). So a merge to main that changes a folder's inputs is the trigger; there is no scheduled
rebuild, because a rebuild of the same inputs gives a new digest for the same version.

**How does the client learn about versions and pin a digest known only after the build?** Every
ecosystem that pins does it the same way: the build writes the hash into a file the client reads
(Homebrew's `bottle do`, winget's `InstallerSha256`, Debian's `Packages`). Homebrew writes it into
the reviewed source before merge; for us that would mean a bot commit into every Dependabot PR.
We write it after the merge into an append-only index instead (decision 0001, option discussion),
and the client pins `NAME VERSION DIGEST` in a lock of its own, like `Brewfile.lock.json` or a
lockfile.

**Versions:** upstream plus a revision (Homebrew `revision`, Debian `-N`) is what people expect
("claude 2.1.325"), and it can be computed: upstream from the lockfile or the tag, the revision
from the index. OCI tags alone are not a contract, because they move.

**Overrides:** all of them let users add their own source next to the official one (tap, source,
repository, overlay). burrow already has the user's presets folder and `--image`; the index adds a
third source with lower priority than the user's own (to be decided in burrow, issue #6).

**Signing, mirrors, offline, cost:** Debian and Nix sign the index or the objects; Homebrew and
winget rely on hashes in a reviewed repository. Until the organisation's D7 decision exists, we do
what Homebrew does (digests in a reviewed and auditable place) and record how signing would be
added. Cost is GitHub Actions minutes and GHCR storage, both free for public repositories
(*unverified for private*). Offline: the index is a git branch and can be copied.

## Recommendation

1. Image folders in burrow-repo as the source of truth, reviewed, pinned, Dependabot-updated.
2. Versions `<upstream>-r<N>`, computed, never reused; no moving tags.
3. CI builds each platform natively, smoke-tests, scans, pushes; then writes an append-only index
   (pinned presets plus metadata) on a branch only the workflow writes.
4. Clients pull by digest only and lock what they use; yanking marks, never deletes.
5. Signing once D7 is decided, through OCI referrers (signatures and SBOMs attached to the digest).
