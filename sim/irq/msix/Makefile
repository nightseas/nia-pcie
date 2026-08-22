# ---------------------------------------------------------------------------
# File        : Makefile
# Description : The cocotb set for pcie_versal_msix_adapt, the MSI-X request
#               adaptor onto the CPM5 interrupt interface, run under Icarus by
#               default. Its elab-refuse target elaborates the module once per
#               parameter configuration and requires every illegal one, no vector,
#               an index wider than a vector number and no retry, to be refused.
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

DUT      = pcie_versal_msix_adapt
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

TB_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT    ?= $(shell d='$(TB_DIR)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(TB_DIR): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

MODEL_DIR   ?= $(NIA_ROOT)/sim/model
RTL_DIR     ?= $(NIA_ROOT)/rtl/irq

MSIX_SRC ?= $(RTL_DIR)/$(DUT).sv
export MSIX_SRC

VERILOG_SOURCES += $(MSIX_SRC)

export PYTHONPATH := $(TB_DIR):$(MODEL_DIR):$(PYTHONPATH)

export PARAM_IRQ_INDEX_WIDTH   ?= 6
export PARAM_MSIX_VECTOR_COUNT ?= 8
export PARAM_FUNCTION_NUMBER   ?= 0
export PARAM_FAIL_RETRY_LIMIT  ?= 3
export PARAM_STS_COUNT_WIDTH   ?= 8

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
    -P $(TOPLEVEL).IRQ_INDEX_WIDTH=6 \
    -P $(TOPLEVEL).MSIX_VECTOR_COUNT=8 \
    -P $(TOPLEVEL).FAIL_RETRY_LIMIT=3

ELAB_VECTOR_COUNT_0 = \
    -P $(TOPLEVEL).IRQ_INDEX_WIDTH=6 \
    -P $(TOPLEVEL).MSIX_VECTOR_COUNT=0 \
    -P $(TOPLEVEL).FAIL_RETRY_LIMIT=3

ELAB_INDEX_WIDTH_33 = \
    -P $(TOPLEVEL).IRQ_INDEX_WIDTH=33 \
    -P $(TOPLEVEL).MSIX_VECTOR_COUNT=8 \
    -P $(TOPLEVEL).FAIL_RETRY_LIMIT=3

ELAB_RETRY_LIMIT_0 = \
    -P $(TOPLEVEL).IRQ_INDEX_WIDTH=6 \
    -P $(TOPLEVEL).MSIX_VECTOR_COUNT=8 \
    -P $(TOPLEVEL).FAIL_RETRY_LIMIT=0

define elaborate_and_require_refusal
	@iverilog -g2012 -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(MSIX_SRC) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q '$(DUT):' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED"; \
	else \
	    echo "  $(1): ADMITTED, and this configuration must be refused: elab_refuse/$(1).log"; \
	    exit 1; \
	fi
endef

define elaborate_and_require_acceptance
	@iverilog -g2012 -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(MSIX_SRC) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q '$(DUT):' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED, and this is the legal configuration: elab_refuse/$(1).log"; \
	    exit 1; \
	else \
	    echo "  $(1): ACCEPTED"; \
	fi
endef

.PHONY: elab-refuse
elab-refuse:
	@rm -rf elab_refuse && mkdir -p elab_refuse
	$(call elaborate_and_require_acceptance,legal_8_vectors,$(ELAB_OK))
	$(call elaborate_and_require_refusal,vector_count_0,$(ELAB_VECTOR_COUNT_0))
	$(call elaborate_and_require_refusal,index_width_33,$(ELAB_INDEX_WIDTH_33))
	$(call elaborate_and_require_refusal,retry_limit_0,$(ELAB_RETRY_LIMIT_0))
	@echo "ELAB-REFUSE: every illegal configuration refused, the legal one accepted"

.PHONY: params
params:
	@echo "NIA_MSIX_PARAMS irq_index_w=$(PARAM_IRQ_INDEX_WIDTH)" \
	      "vectors=$(PARAM_MSIX_VECTOR_COUNT)" \
	      "function=$(PARAM_FUNCTION_NUMBER)" \
	      "retry_limit=$(PARAM_FAIL_RETRY_LIMIT)" \
	      "sts_count_w=$(PARAM_STS_COUNT_WIDTH)" \
	      "seed=$(NIA_SEED)" \
	      "src=$(MSIX_SRC)" \
	      "sim=$(SIM)"

.PHONY: lint
lint:
	verilator --lint-only --top-module $(DUT) $(MSIX_SRC)

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
