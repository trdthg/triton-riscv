# Development entry points. The logic lives in scripts/.
SHELL := /bin/bash

PY_TAG ?= cp312
ARCH   ?= $(shell uname -m | sed 's/^amd64$$/x86_64/')
PYTEST ?= python/examples
IGNORE := --ignore=python/examples/test_core.py --ignore=python/examples/test_annotations.py --ignore=python/examples/flaggems

.PHONY: all setup build test test-all release clean

all: setup build  ## Bootstrap a fresh checkout and build it

setup:  ## Virtualenv, build dependencies, Triton checkout, toolchains
	scripts/setup.sh

build:  ## Rebuild Triton with the triton-shared backend
	scripts/build.sh

test:  ## Run the example test suite
	bash -c 'source scripts/env.sh && pytest $(PYTEST) $(IGNORE) -q'

test-all:  ## Run it including test_core, test_annotations and flaggems
	bash -c 'source scripts/env.sh && pytest $(PYTEST) -q'

release:  ## Build the wheels; needs docker: make release PY_TAG=cp312 ARCH=riscv64
	scripts/release.sh $(PY_TAG) $(ARCH)

clean:  ## Remove the Triton build tree
	rm -rf triton/build
