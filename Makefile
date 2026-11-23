# The single entry point, locally and in CI (CI runs these same targets). The host needs only
# Podman (or ENGINE=docker), make, sh and git: every tool runs in a container pinned by digest
# (burrow decision 0010). NAME is an image folder under presets/ (`make list`).
.DEFAULT_GOAL := help
NAME ?=
INDEX ?= .cache/index

.PHONY: help list check build smoke scan image versions clean

help: ## list the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  make %-10s %s\n", $$1, $$2}' Makefile

list: ## the image folders and the presets each one publishes
	@for d in presets/*/; do printf '%-12s' "$$(basename $$d)"; ls $$d | sed -n 's/\.preset$$//p' | tr '\n' ' '; echo; done

check: ## static checks: pins, non-root, preset keys, Dependabot coverage, workflows (no container)
	sh scripts/check.sh

build: ## build presets/NAME as localhost/burrow-preset-NAME:dev
	sh scripts/build.sh $(NAME)

smoke: ## start the built image as burrow would (non-root, no capabilities, no network) and run its tool
	sh scripts/smoke.sh $(NAME)

scan: ## Trivy on the built image: secrets fail, vulnerabilities reported
	sh scripts/scan.sh $(NAME)

image: build smoke scan ## build, smoke-test and scan presets/NAME

versions: ## the version each folder would get against a local index (INDEX=dir, default .cache/index)
	@sh scripts/publish.sh versions $(INDEX)

clean: ## remove .cache/
	rm -r -f .cache
