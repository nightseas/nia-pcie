# ---------------------------------------------------------------------------
# File        : Makefile
# Description : The cocotb set for pcie_versal_msi_adapt, the CPM5 to UltraScale+
#               MSI sideband adaptor, run under Icarus by default. Its elab-refuse
#               target elaborates the module once per parameter configuration and
#               requires every configuration that would truncate a field to be
#               refused, and the legal one to be accepted.
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

DUT      = pcie_versal_msi_adapt
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

TB_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT    ?= $(shell d='$(TB_DIR)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(TB_DIR): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

RTL_DIR     ?= $(NIA_ROOT)/rtl/irq

MSI_SRC ?= $(RTL_DIR)/$(DUT).sv
export MSI_SRC

VERILOG_SOURCES += $(MSI_SRC)

export PYTHONPATH := $(TB_DIR):$(PYTHONPATH)

export PARAM_US_ENABLE_W     ?= 4
export PARAM_US_MMENABLE_W   ?= 12
export PARAM_US_SELECT_W     ?= 2
export PARAM_US_PSFN_W       ?= 2
export PARAM_US_FUNC_NUM_W   ?= 8
export PARAM_CPM5_ENABLE_W   ?= 1
export PARAM_CPM5_MMENABLE_W ?= 3
export PARAM_CPM5_SELECT_W   ?= 4
export PARAM_CPM5_PSFN_W     ?= 4
export PARAM_CPM5_FUNC_NUM_W ?= 16
export PARAM_VECTOR_W        ?= 32
export PARAM_ATTR_W          ?= 3
export PARAM_TPH_TYPE_W      ?= 2
export PARAM_TPH_ST_TAG_W    ?= 8

export NIA_SEED ?= 1

ifeq ($(SIM),icarus)
    PLUSARGS += -fst
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES),1)
        VERILOG_SOURCES += iverilog_dump.v
        COMPILE_ARGS += -s iverilog_dump
    endif
else ifeq ($(SIM),verilator)
    COMPILE_ARGS += -Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES),1)
        COMPILE_ARGS += --trace-fst
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

ELAB_OK = \
    -P $(TOPLEVEL).US_ENABLE_W=4 -P $(TOPLEVEL).CPM5_ENABLE_W=1 \
    -P $(TOPLEVEL).US_MMENABLE_W=12 -P $(TOPLEVEL).CPM5_MMENABLE_W=3 \
    -P $(TOPLEVEL).US_SELECT_W=2 -P $(TOPLEVEL).CPM5_SELECT_W=4 \
    -P $(TOPLEVEL).US_PSFN_W=2 -P $(TOPLEVEL).CPM5_PSFN_W=4 \
    -P $(TOPLEVEL).US_FUNC_NUM_W=8 -P $(TOPLEVEL).CPM5_FUNC_NUM_W=16 \
    -P $(TOPLEVEL).VECTOR_W=32

ELAB_ENABLE_TRUNCATES = $(subst -P $(TOPLEVEL).US_ENABLE_W=4,-P $(TOPLEVEL).US_ENABLE_W=1 -P $(TOPLEVEL).CPM5_ENABLE_W=4,$(ELAB_OK))
ELAB_MMENABLE_TRUNCATES = $(subst -P $(TOPLEVEL).US_MMENABLE_W=12,-P $(TOPLEVEL).US_MMENABLE_W=2,$(ELAB_OK))
ELAB_SELECT_TRUNCATES = $(subst -P $(TOPLEVEL).CPM5_SELECT_W=4,-P $(TOPLEVEL).CPM5_SELECT_W=1,$(ELAB_OK))
ELAB_PSFN_TRUNCATES = $(subst -P $(TOPLEVEL).CPM5_PSFN_W=4,-P $(TOPLEVEL).CPM5_PSFN_W=1,$(ELAB_OK))
ELAB_FUNC_NUM_TRUNCATES = $(subst -P $(TOPLEVEL).CPM5_FUNC_NUM_W=16,-P $(TOPLEVEL).CPM5_FUNC_NUM_W=4,$(ELAB_OK))
ELAB_VECTOR_NOT_32 = $(subst -P $(TOPLEVEL).VECTOR_W=32,-P $(TOPLEVEL).VECTOR_W=16,$(ELAB_OK))
ELAB_ATTR_NOT_3 = $(ELAB_OK) -P $(TOPLEVEL).ATTR_W=4

define elaborate_and_require_refusal
	@iverilog -g2012 -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(MSI_SRC) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED"; \
	else \
	    echo "  $(1): ADMITTED, and this configuration must be refused: elab_refuse/$(1).log"; \
	    exit 1; \
	fi
endef

define elaborate_and_require_acceptance
	@iverilog -g2012 -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(MSI_SRC) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED, and this is the legal configuration: elab_refuse/$(1).log"; \
	    exit 1; \
	else \
	    echo "  $(1): ACCEPTED"; \
	fi
endef

.PHONY: elab-refuse
elab-refuse:
	@rm -rf elab_refuse && mkdir -p elab_refuse
	$(call elaborate_and_require_acceptance,legal_cpm5_to_us,$(ELAB_OK))
	$(call elaborate_and_require_refusal,enable_truncates,$(ELAB_ENABLE_TRUNCATES))
	$(call elaborate_and_require_refusal,mmenable_truncates,$(ELAB_MMENABLE_TRUNCATES))
	$(call elaborate_and_require_refusal,select_truncates,$(ELAB_SELECT_TRUNCATES))
	$(call elaborate_and_require_refusal,psfn_truncates,$(ELAB_PSFN_TRUNCATES))
	$(call elaborate_and_require_refusal,func_num_truncates,$(ELAB_FUNC_NUM_TRUNCATES))
	$(call elaborate_and_require_refusal,vector_not_32,$(ELAB_VECTOR_NOT_32))
	$(call elaborate_and_require_refusal,attr_not_3,$(ELAB_ATTR_NOT_3))
	@echo "ELAB-REFUSE: every truncating configuration refused, the legal one accepted"

.PHONY: params
params:
	@echo "NIA_MSI_PARAMS us_enable=$(PARAM_US_ENABLE_W) cpm5_enable=$(PARAM_CPM5_ENABLE_W)" \
	      "us_mmenable=$(PARAM_US_MMENABLE_W) cpm5_mmenable=$(PARAM_CPM5_MMENABLE_W)" \
	      "us_select=$(PARAM_US_SELECT_W) cpm5_select=$(PARAM_CPM5_SELECT_W)" \
	      "us_func=$(PARAM_US_FUNC_NUM_W) cpm5_func=$(PARAM_CPM5_FUNC_NUM_W)" \
	      "vector=$(PARAM_VECTOR_W) seed=$(NIA_SEED)" \
	      "src=$(MSI_SRC) sim=$(SIM)"

.PHONY: lint
lint:
	verilator --lint-only --top-module $(DUT) $(MSI_SRC)

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
	@rm -rf sim_build sim_build_* results*.xml iverilog_dump.v *.fst __pycache__ \
	    mut_work elab_refuse
