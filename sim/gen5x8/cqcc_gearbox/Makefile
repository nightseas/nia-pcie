# ---------------------------------------------------------------------------
# File        : Makefile
# Description : The cocotb set for pcie_versal_if_cqcc_gearbox, the completer request
#               and completion width conversion, run under Icarus by default.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Makefile
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

TOPLEVEL_LANG = verilog
SIM          ?= icarus
WAVES        ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

DUT      = pcie_versal_if_cqcc_gearbox
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

TB_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT    ?= $(shell d='$(TB_DIR)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(TB_DIR): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

MODEL_DIR   ?= $(NIA_ROOT)/sim/model
RTL_DIR     ?= $(NIA_ROOT)/rtl/gen5x8

GEARBOX_SRC ?= $(RTL_DIR)/$(DUT).sv
export GEARBOX_SRC

VERILOG_SOURCES += $(GEARBOX_SRC)

export PYTHONPATH := $(TB_DIR):$(MODEL_DIR):$(PYTHONPATH)

export PARAM_AXIS_PCIE_DATA_WIDTH    := 1024
export PARAM_AXIS_PCIE_KEEP_WIDTH    := 32
export PARAM_AXIS_PCIE_CQ_USER_WIDTH := 465
export PARAM_AXIS_PCIE_CC_USER_WIDTH := 165
export PARAM_USER_DATA_WIDTH         := 512
export PARAM_USER_KEEP_WIDTH         := 16
export PARAM_USER_CQ_USER_WIDTH      := 231
export PARAM_USER_CC_USER_WIDTH      := 81
export PARAM_CQ_STRADDLE             := 1
export PARAM_CC_STRADDLE             := 1
export PARAM_CQ_SOP_PTR_DW           := 8
export PARAM_CC_SOP_PTR_DW           := 8

ifeq ($(SIM),icarus)
    PLUSARGS += -fst
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES),1)
        VERILOG_SOURCES += iverilog_dump.v
        COMPILE_ARGS += -s iverilog_dump
    endif
else ifeq ($(SIM),verilator)
    COMPILE_ARGS += -Wno-SELRANGE -Wno-WIDTH
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES),1)
        COMPILE_ARGS += --trace-fst
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

ELAB_OK = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=465 \
    -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=165 \
    -P $(TOPLEVEL).CQ_SOP_PTR_DW=8 -P $(TOPLEVEL).CC_SOP_PTR_DW=8

ELAB_CQ_USER_BAD = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=231 \
    -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=165 \
    -P $(TOPLEVEL).CQ_SOP_PTR_DW=8 -P $(TOPLEVEL).CC_SOP_PTR_DW=8

ELAB_CC_USER_BAD = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=465 \
    -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=81 \
    -P $(TOPLEVEL).CQ_SOP_PTR_DW=8 -P $(TOPLEVEL).CC_SOP_PTR_DW=8

ELAB_WIDTH_BAD = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=256 \
    -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=465 \
    -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=165 \
    -P $(TOPLEVEL).CQ_SOP_PTR_DW=8 -P $(TOPLEVEL).CC_SOP_PTR_DW=8

ELAB_CC_PTR_BAD = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_CQ_USER_WIDTH=465 \
    -P $(TOPLEVEL).AXIS_PCIE_CC_USER_WIDTH=165 \
    -P $(TOPLEVEL).CQ_SOP_PTR_DW=8 -P $(TOPLEVEL).CC_SOP_PTR_DW=4

define gearbox_require_refusal
	@iverilog -g2005-sv -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) $(VERILOG_SOURCES) \
	    > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then echo "  $(1): REFUSED"; \
	 else echo "  $(1): ADMITTED, and this configuration must be refused: elab_refuse/$(1).log"; exit 1; fi
endef

define gearbox_require_acceptance
	@iverilog -g2005-sv -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) $(VERILOG_SOURCES) \
	    > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED, and this is the legal configuration: elab_refuse/$(1).log"; exit 1; \
	 else echo "  $(1): ACCEPTED"; fi
endef

.PHONY: elab-refuse
elab-refuse:
	@rm -rf elab_refuse && mkdir -p elab_refuse
	$(call gearbox_require_acceptance,legal_1024,$(ELAB_OK))
	$(call gearbox_require_refusal,cq_user_231_at_1024,$(ELAB_CQ_USER_BAD))
	$(call gearbox_require_refusal,cc_user_81_at_1024,$(ELAB_CC_USER_BAD))
	$(call gearbox_require_refusal,data_width_256,$(ELAB_WIDTH_BAD))
	$(call gearbox_require_refusal,cc_sop_ptr_dw_4,$(ELAB_CC_PTR_BAD))
	@echo "ELAB-REFUSE: every illegal gearbox configuration refused, the legal one accepted"

.PHONY: lint
lint:
	verilator --lint-only --top-module $(DUT) $(VERILOG_SOURCES)

.PHONY: mutate
mutate:
	@./mutate.sh

iverilog_dump.v:
	@echo 'module iverilog_dump();' > $@
	@echo 'initial begin' >> $@
	@echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	@echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	@echo 'end' >> $@
	@echo 'endmodule' >> $@

clean::
	@rm -rf sim_build sim_build_* results*.xml iverilog_dump.v *.fst __pycache__ mut_work elab_refuse
