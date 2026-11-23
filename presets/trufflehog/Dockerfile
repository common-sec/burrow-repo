# Image for the trufflehog preset (presets/trufflehog), built by `make build NAME=trufflehog`.
# Only a pinned base (tag for readers and Dependabot, multi-platform digest for what runs) and a
# non-root user. Same pin as burrow-sandbox's packaging/scanners/Dockerfile, which this replaces
# once burrow can run scanners as presets.
FROM docker.io/trufflesecurity/trufflehog:3.99.9@sha256:2ec535840f860aa27f11fee20222fb790326ecd66325c96bd49d02ec6af46eca
USER 65532:65532
