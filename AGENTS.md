# Working in burrow-repo (for AI agents and people)

burrow-repo publishes the presets and images that [burrow](https://github.com/common-sec/burrow-sandbox)
runs. A preset decides what a tool can reach, and an image is code that runs with the user's
workspace: treat every change as security-relevant. `CLAUDE.md` only points here. The rules of
burrow-sandbox's AGENTS.md apply here too; this file lists what is specific to this repository.

## Commands

Everything goes through the Makefile, locally and in CI (`make help`). The host needs only Podman
(or `ENGINE=docker`), make, sh and git: no tool is installed on the host or the CI runner.

| Command | When |
|---|---|
| `make check` | before saying a change is done (static: pins, non-root, preset keys, Dependabot, workflows) |
| `make image NAME=<folder>` | when a folder changes: build, smoke test as burrow runs it, scan |
| `make versions` | to see what a merge would publish |

Report results as they are. If something could not run (no Podman, no network), say so.

## Rules for every change

- **The contract is binding:** [docs/CONTRACT.md](docs/CONTRACT.md). A change to versions, tags,
  the index format or what clients may rely on needs a decision record in `docs/decisions/` and
  a new index format (`v2/`) if it removes or changes a field.
- Name the requirement (burrow's R8, D1, D7...) and the organisation's controls (SCF IDs such as
  TDA-06.4, AST-14, CHG-02; SCF is credited as in secure-standard-platforms' NOTICE.md) in the
  commit message.
- **Never edit a version by hand** and never re-publish one: versions are computed (contract
  section 3). To fix a published version, change the source (a new revision) and add the old
  one to `YANKED` with a reason.
- **Everything pinned, with a cooldown:** every `FROM` by tag and digest; npm by
  `package-lock.json` with integrity hashes; pip by `requirements.txt` with hashes; Actions by
  commit SHA; 7 days before a new version (Dependabot `cooldown`, `--before` / `--exclude-newer`
  when generating lockfiles). Security fixes may skip it; name the advisory.
- **Least privilege in presets:** ask only for what the tool needs. Never root (`RUN_AS` uid 0),
  never host mounts, `CAP_ADD` only from burrow's list, `ALLOW` only the hosts the tool needs and
  marked *unverified* until checked. Images end with a non-root `USER`.
- **A new folder** needs: Dockerfile, `build.conf`, at least one preset, a line in
  `.github/dependabot.yml` per ecosystem, the licence of the tool in the Dockerfile header, and
  `make image` passing.
- No third-party GitHub Actions besides `actions/checkout`. Workflows get the least
  `permissions` they need, per job.
- The `index` branch is written only by `publish.yml`. Never push to it by hand.
