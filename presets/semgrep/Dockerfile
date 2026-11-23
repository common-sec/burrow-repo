# Image for the semgrep preset (presets/semgrep), built by `make build NAME=semgrep`.
# Only a pinned base (tag for readers and Dependabot, multi-platform digest for what runs) and a
# non-root user. Same pin as burrow-sandbox's packaging/scanners/Dockerfile, which this replaces
# once burrow can run scanners as presets.
FROM docker.io/semgrep/semgrep:1.185.0@sha256:67518c174185a2043fdbed16c70631b79209499b3671178e7194379b48295a0d
ENV SEMGREP_SEND_METRICS=off
USER 65532:65532
