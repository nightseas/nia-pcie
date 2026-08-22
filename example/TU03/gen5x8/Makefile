# ---------------------------------------------------------------------------
# File        : Makefile
# Description : Entry point of the TU03 Gen5 x8 example design, 1024-bit
#               AXI4-Stream. It holds no build logic: every target delegates to
#               bin/nia-pcie, so this folder and the repository root run the same
#               code path.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

HERE     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT ?= $(shell d='$(HERE)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
TOOL     := $(NIA_ROOT)/bin/nia-pcie
CPM      := GEN5

ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(HERE): this folder has been copied out of the \
nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

ASKED := $(shell printf '%s' '$(NIA_CPM)' | tr '[:lower:]' '[:upper:]' | sed 's/X8$$//')
ifneq ($(ASKED),)
ifneq ($(ASKED),$(CPM))
$(error this folder builds $(CPM) and NIA_CPM asks for $(NIA_CPM): run NIA_CPM=$(NIA_CPM) make image \
from the repository root to build another configuration)
endif
endif

.DEFAULT_GOAL := image

.PHONY: image check help clean

image:
	@NIA_CPM=$(CPM) $(TOOL) image

check:
	@$(TOOL) check

help:
	@$(TOOL) help

clean:
	@rm -rf fpga/build_pdi_1024
