# Image for the trufflehog preset (presets/trufflehog), built by `make build NAME=trufflehog`.
# Only a pinned base (tag for readers and Dependabot, multi-platform digest for what runs) and a
# non-root user. Same pin as burrow-sandbox's packaging/scanners/Dockerfile, which this replaces
# once burrow can run scanners as presets.
FROM docker.io/trufflesecurity/trufflehog:3.99.8@sha256:674b2f187620a19df77f44cf9a7d77efcc581a5662accef2f2739cbb46ba4a3a
USER 65532:65532
