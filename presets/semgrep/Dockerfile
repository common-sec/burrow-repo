# Image for the semgrep preset (presets/semgrep), built by `make build NAME=semgrep`.
# Only a pinned base (tag for readers and Dependabot, multi-platform digest for what runs) and a
# non-root user. Same pin as burrow-sandbox's packaging/scanners/Dockerfile, which this replaces
# once burrow can run scanners as presets.
FROM docker.io/semgrep/semgrep:1.184.0@sha256:cc1b68266f267878b39739373ea9985b9a78e5d64497dd875c8de100b22695ed
ENV SEMGREP_SEND_METRICS=off
USER 65532:65532
