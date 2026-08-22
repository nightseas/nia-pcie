# ---------------------------------------------------------------------------
# File        : Makefile
# Description : Entry point of the interrupt adaptor simulation sets, MSI and
#               MSI-X. It holds no simulation logic: it delegates to bin/nia-pcie
#               with a path filter, so a set runs the same way from here as from
#               the repository root, and its mutate target runs the mutation gate
#               of every set below it.
# Language    : Makefile
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

HERE     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT ?= $(shell d='$(HERE)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
TOOL     := $(NIA_ROOT)/bin/nia-pcie

ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(HERE): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif
SCOPE    := sim/irq

.DEFAULT_GOAL := sim

.PHONY: sim list mutate clean

sim:
	@NIA_SIM_MATCH=$(SCOPE) $(TOOL) sim

list:
	@NIA_SIM_MATCH=$(SCOPE) $(TOOL) list

mutate:
	@for d in $(HERE)/*/mutate.sh; do echo "== $${d}"; ( cd "$$(dirname $$d)" && ./mutate.sh ) || exit 1; done

clean:
	@for d in $(HERE)/*/Makefile; do $(MAKE) -C "$$(dirname $$d)" clean >/dev/null 2>&1 || true; done
