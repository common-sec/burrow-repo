# Versioning and publishing contract

**Status:** proposed (2026-11-23), decision [0001](decisions/0001-versioning-and-publishing.md).
**Owner:** J. Serves burrow's R8 (presets), D1 (pinned), D7 (verifiable), and the organisation's
controls TDA-06.4 (integrity of updates), TDA-20.3 (integrity verification), AST-14 (provenance),
CHG-02 (change control) and VPM-06 (vulnerability remediation). SCF is credited as in
secure-standard-platforms' NOTICE.md.

This is what burrow-repo promises to anyone who consumes a preset: burrow itself, a CI job, or a
person who runs the image without burrow. The words **must**, **never** and **may** are binding.
The pipeline in `scripts/` and `.github/workflows/` implements it; `make check` enforces the source
rules. The design and the options discarded are in decision 0001; the research behind it is the
[preset index spike](../research/spikes/2026-11-preset-index/SPIKE.md).

## 1. Terms

| Term | Meaning | Ecosystem analogy |
|---|---|---|
| **Image folder** | `presets/<folder>/`: one Dockerfile, its lockfiles, `build.conf`, and one or more presets | a Debian source package; a Homebrew formula |
| **Preset** | a `<name>.preset` file in an image folder: an image plus the settings it is safe to run with (burrow decision 0005) | a Debian binary package |
| **Version** | `<upstream>-r<revision>`, the same for every preset of an image folder | Debian `1.2-3`; Homebrew `version` + `revision` |
| **Index** | the `index` branch: every published version, its digest and its pinned presets | Debian's `Packages` files; Homebrew's API JSON |

## 2. Source layout (main branch, reviewed)

- `presets/<folder>/Dockerfile`: every `FROM` pinned by tag and digest; ends with a non-root `USER`.
- `presets/<folder>/<name>.preset`: burrow KEY=VALUE, keys burrow's main branch accepts, `NAME`
  equal to the file name and unique in the repository, and `IMAGE=localhost/burrow-preset-<folder>:dev`
  (the local build; the pipeline writes the published digest). Published presets **never** ask for
  root (`RUN_AS` uid 0) and never mount host folders (burrow decisions 0011, 0012, 0013).
- `presets/<folder>/build.conf`: `UPSTREAM` (where the upstream version comes from: `npm:PKG`,
  `pip:PKG`, `from` for the tag of the last `FROM`, or `fixed:VALUE`), `PLATFORMS`
  (`linux/amd64`, `linux/arm64`), `SMOKE_ENTRYPOINT` and `SMOKE` (the smoke test), optional
  `MIN_BURROW`.
- `YANKED`: versions that must no longer be used (section 7).
- Every folder is in `.github/dependabot.yml`; every change goes through a pull request reviewed
  by the security team (CODEOWNERS).

## 3. Versions

1. A version is `<upstream>-r<N>`. `upstream` is the version of what the image packages (the npm
   or PyPI package, the base image tag), read from the lockfile or Dockerfile, so Dependabot
   updates it without anyone editing a version by hand. Characters: `A-Z a-z 0-9 . _ -`.
2. `N` starts at 1 for each upstream version and goes up by one each time the folder's **inputs**
   change without a new upstream version: a new base digest, a changed lockfile entry, a changed
   preset, `build.conf` or Dockerfile. The inputs are the SHA-256 of every file in the folder.
3. **Same inputs, same version.** The pipeline publishes only when the inputs differ from the
   newest entry for that folder; re-running it publishes nothing.
4. **A version is published once and never reused or moved.** Its index entry, digest and presets
   never change; only its status may (section 7). A fix is always a new revision.
5. There are **no moving tags**: no `latest`, no `stable`, no `2.1`. "The newest" is a property of
   the index (the most recent active entry), never of a tag.
6. Versions are ordered by publication time in the index, not by comparing strings: upstreams use
   semver, dates (`noble-20261024.1`) or nothing (`rolling`).

## 4. What triggers a release

- A merge to `main` that changes a folder's inputs (most often a Dependabot PR), or YANKED.
- There are **no scheduled rebuilds**: a rebuild of the same inputs would give a new digest for
  the same version and break rule 3.4. New vulnerabilities in unchanged images are found by the
  weekly rescan (`rescan.yml`) and fixed by a newer pin here, which is a new revision.
- Upstream cooldown: the inputs wait 7 days (Dependabot `cooldown`) before they are proposed, as in
  burrow; security updates skip it and name the advisory. Our own release is not delayed again.

## 5. Images

- `ghcr.io/common-sec/burrow-presets/<folder>:<version>` is a multi-platform manifest list with
  the platforms of `build.conf`. Each platform is built on its own native runner (no emulation),
  smoke-tested and scanned before it is pushed.
- Per-platform tags (`<version>-amd64`) exist only to assemble the list; they are not part of the
  contract and clients must not use them.
- Labels: `org.opencontainers.image.source`, `.revision` (source commit), `.version` (upstream).
- Images are **never deleted**, so a pinned user is told "yanked, because..." instead of getting a
  missing image.
- Packages are private by default on GHCR ("When you first publish a package, the default
  visibility is private", GitHub docs); to be usable without burrow (roadmap 0.4) the owner makes
  each package public once.

## 6. The index

The `index` branch of this repository, written only by `publish.yml`, append-only, one commit per
publish. Clients read it over HTTPS (raw files or a git fetch) at a known commit or at the branch.

```
v1/FORMAT                         1 (a client refuses a format it does not know)
v1/INDEX                          NAME VERSION STATUS IMAGE@DIGEST PUBLISHED, one line per preset version
v1/SHA256SUMS                     SHA-256 of every other file under v1/
v1/images/<folder>.versions       VERSION INPUTS_SHA256 DIGEST PUBLISHED SOURCE_COMMIT (the ledger)
v1/presets/<name>/<version>.preset  the preset, ready for burrow: IMAGE pinned by digest
v1/presets/<name>/<version>.meta    KEY=VALUE: NAME IMAGE_FOLDER VERSION UPSTREAM REVISION IMAGE
                                    PLATFORMS PLATFORM_DIGESTS INPUTS_SHA256 SOURCE_REPOSITORY
                                    SOURCE_COMMIT PUBLISHED WORKFLOW_RUN MIN_BURROW STATUS STATUS_REASON
```

Everything is KEY=VALUE or space-separated lines, like burrow's definitions (its decision 0003):
no expansion, no includes, data only. A new field may be added to `.meta` without a new format;
removing or changing the meaning of a field needs `v2/` next to `v1/`.

## 7. Yanking

A version that must not be used (a vulnerability, a broken image, a wrong `ALLOW`) is added to
`YANKED` on main with a reason, through a reviewed PR. The next publish marks it `STATUS=yanked`
with `STATUS_REASON` in the index. Removing the line makes it active again. Nothing is deleted.

## 8. What a client must do (burrow, roadmap 0.4, issue #6)

1. Pull **only by digest** from the index (`IMAGE` in the `.meta` or `.preset`), never by tag, and
   check that the digest it ran is the one in the index.
2. Check `v1/FORMAT`, and `v1/SHA256SUMS` for every file it reads.
3. Record what it uses as `NAME VERSION DIGEST` in a lock the user owns (outside the workspace), so
   the same command runs the same image until the user updates on purpose.
4. "Newest" is the most recent `active` line for a name in `INDEX`. A yanked version is refused
   unless the user names it explicitly, and its reason is printed.
5. Refuse a preset whose `MIN_BURROW` is newer than itself.
6. Treat a downloaded preset as a shared definition: it gets the confirmation of burrow decision
   0013 for any weakened setting, and it is never read from the workspace.

## 9. Verification today, signing later (D7)

The organisation has no signing solution yet (D7, research topic `signing`). Until it does, every
published artifact records how it can be verified:

- the **digest** is content-addressed: an image that does not match it cannot be served under it;
- the **index** is a git history: each entry names its source commit and the workflow run that
  built it, and every change to the index is a commit that can be audited;
- the **source** is reviewed: every input went through a PR reviewed by the security team.

What this does not cover: someone with write access to the `index` branch or the packages could
publish an entry that no reviewed commit produced. Protect the `index` branch so that only GitHub
Actions can push. Signing the index and the images (Sigstore keyless or GitHub artifact
attestations, with provenance) is the next step once D7 is decided; the `.meta` file will gain the
signature reference without a format change.

## 10. Gaps

- arm64 is built only for images whose upstream is known to support it (`build.conf`); the agent
  images are amd64 only until their lockfiles are checked for arm64 packages.
- arm64 runners (`ubuntu-24.04-arm`) are free for public repositories; for a private repository
  they may need larger runners (*unverified*).
- GHCR tags can be overwritten by anyone with write access to the package (GitHub's docs on the
  container registry do not mention immutable tags); clients are safe because they pull by digest
  (8.1), but a person who pulls by tag is not.
- No SBOM is attached yet (roadmap: releases).
- The index is one branch of one repository: no mirror. Offline use means copying the branch.
