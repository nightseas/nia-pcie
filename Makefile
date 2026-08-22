# ---------------------------------------------------------------------------
# File        : Makefile
# Description : The documented entry point of nia-pcie. It contains no build
#               logic: every target delegates to bin/nia-pcie, so a clone and a
#               release archive run the same code path.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

TOOL := bin/nia-pcie

.PHONY: help deps check sim list image targets hwtest clean

help:
	@$(TOOL) help

deps:
	@$(TOOL) deps

check:
	@$(TOOL) check

sim:
	@$(TOOL) sim

list:
	@$(TOOL) list

image:
	@$(TOOL) image

targets:
	@$(TOOL) targets

hwtest:
	@$(TOOL) hwtest $(ARGS)

clean:
	@$(TOOL) clean
