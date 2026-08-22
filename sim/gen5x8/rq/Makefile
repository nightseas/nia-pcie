# ---------------------------------------------------------------------------
# File        : Makefile
# Description : The cocotb set for pcie_versal_if_rq, the requester request path
#               at 1024-bit AXI4-Stream, run under Icarus by default.
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

DUT      = pcie_versal_if_rq
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

TB_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT    ?= $(shell d='$(TB_DIR)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(TB_DIR): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

MODEL_DIR   ?= $(NIA_ROOT)/sim/model
RTL_DIR     ?= $(NIA_ROOT)/rtl/gen5x8
VP_RTL_DIR  ?= $(NIA_ROOT)/verilog-pcie/rtl
VP_TB_DIR   ?= $(NIA_ROOT)/verilog-pcie/tb

RQ_SRC ?= $(RTL_DIR)/$(DUT).sv
export RQ_SRC

VERILOG_SOURCES += $(RQ_SRC)
VERILOG_SOURCES += $(VP_RTL_DIR)/pcie_tlp_fifo.v
VERILOG_SOURCES += $(VP_RTL_DIR)/pcie_tlp_fifo_raw.v

export PYTHONPATH := $(TB_DIR):$(MODEL_DIR):$(VP_TB_DIR):$(PYTHONPATH)

RQ_STRADDLE_ENC ?= 1

ifeq ($(filter 0 1,$(RQ_STRADDLE_ENC)),)
$(error RQ_STRADDLE_ENC must be 1 (is_sop and is_eop framing) or 0 (tkeep and tlast framing), got '$(RQ_STRADDLE_ENC)')
endif

export PARAM_AXIS_PCIE_DATA_WIDTH    := 1024
export PARAM_AXIS_PCIE_KEEP_WIDTH    := 32
export PARAM_AXIS_PCIE_RQ_USER_WIDTH := 373
export PARAM_RQ_STRADDLE_ENC         := $(RQ_STRADDLE_ENC)
export PARAM_RQ_SEQ_NUM_WIDTH        := 6
export PARAM_TLP_DATA_WIDTH          := 1024
export PARAM_TLP_STRB_WIDTH          := 32
export PARAM_TLP_HDR_WIDTH           := 128
export PARAM_TLP_SEG_COUNT           := 1
export PARAM_TX_SEQ_NUM_COUNT        := 4
export PARAM_TX_SEQ_NUM_WIDTH        := 5

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

ELAB_1024_OK = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=32 \
    -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=373 \
    -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=6 \
    -P $(TOPLEVEL).TLP_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).TLP_STRB_WIDTH=32 \
    -P $(TOPLEVEL).TLP_HDR_WIDTH=128 \
    -P $(TOPLEVEL).TLP_SEG_COUNT=1 \
    -P $(TOPLEVEL).TX_SEQ_NUM_COUNT=4 \
    -P $(TOPLEVEL).TX_SEQ_NUM_WIDTH=5

ELAB_WIDTH_512 = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=512 \
    -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=16 \
    -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=373 \
    -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=6 \
    -P $(TOPLEVEL).TLP_DATA_WIDTH=512 \
    -P $(TOPLEVEL).TLP_STRB_WIDTH=16 \
    -P $(TOPLEVEL).TLP_HDR_WIDTH=128 \
    -P $(TOPLEVEL).TLP_SEG_COUNT=1 \
    -P $(TOPLEVEL).TX_SEQ_NUM_COUNT=4 \
    -P $(TOPLEVEL).TX_SEQ_NUM_WIDTH=5

ELAB_USER_137 = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=32 \
    -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=137 \
    -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=6 \
    -P $(TOPLEVEL).TLP_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).TLP_STRB_WIDTH=32 \
    -P $(TOPLEVEL).TLP_HDR_WIDTH=128 \
    -P $(TOPLEVEL).TLP_SEG_COUNT=1 \
    -P $(TOPLEVEL).TX_SEQ_NUM_COUNT=4 \
    -P $(TOPLEVEL).TX_SEQ_NUM_WIDTH=5

ELAB_TX_SEQ_2 = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=32 \
    -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=373 \
    -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=6 \
    -P $(TOPLEVEL).TLP_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).TLP_STRB_WIDTH=32 \
    -P $(TOPLEVEL).TLP_HDR_WIDTH=128 \
    -P $(TOPLEVEL).TLP_SEG_COUNT=1 \
    -P $(TOPLEVEL).TX_SEQ_NUM_COUNT=2 \
    -P $(TOPLEVEL).TX_SEQ_NUM_WIDTH=5

ELAB_SEQ_NUM_4 = \
    -P $(TOPLEVEL).AXIS_PCIE_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).AXIS_PCIE_KEEP_WIDTH=32 \
    -P $(TOPLEVEL).AXIS_PCIE_RQ_USER_WIDTH=373 \
    -P $(TOPLEVEL).RQ_SEQ_NUM_WIDTH=4 \
    -P $(TOPLEVEL).TLP_DATA_WIDTH=1024 \
    -P $(TOPLEVEL).TLP_STRB_WIDTH=32 \
    -P $(TOPLEVEL).TLP_HDR_WIDTH=128 \
    -P $(TOPLEVEL).TLP_SEG_COUNT=1 \
    -P $(TOPLEVEL).TX_SEQ_NUM_COUNT=4 \
    -P $(TOPLEVEL).TX_SEQ_NUM_WIDTH=3

define elaborate_and_require_refusal
	@iverilog -g2005-sv -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(VERILOG_SOURCES) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED"; \
	else \
	    echo "  $(1): ADMITTED, and 3-R7 requires a refusal here: elab_refuse/$(1).log"; \
	    exit 1; \
	fi
endef

define elaborate_and_require_acceptance
	@iverilog -g2005-sv -o elab_refuse/$(1).vvp -s $(TOPLEVEL) $(2) \
	    $(VERILOG_SOURCES) > elab_refuse/$(1).log 2>&1 || true
	@vvp elab_refuse/$(1).vvp >> elab_refuse/$(1).log 2>&1 || true
	@if grep -q 'Error:.*(instance' elab_refuse/$(1).log; then \
	    echo "  $(1): REFUSED, and this is the legal configuration: elab_refuse/$(1).log"; \
	    exit 1; \
	else \
	    echo "  $(1): ACCEPTED"; \
	fi
endef

.PHONY: params
params:
	@echo "NIA_RQ1024_PARAMS width=$(PARAM_AXIS_PCIE_DATA_WIDTH)" \
	      "tuser=$(PARAM_AXIS_PCIE_RQ_USER_WIDTH)" \
	      "straddle_enc=$(PARAM_RQ_STRADDLE_ENC)" \
	      "rq_seq_w=$(PARAM_RQ_SEQ_NUM_WIDTH)" \
	      "tlp_seg_count=$(PARAM_TLP_SEG_COUNT)" \
	      "tx_seq_count=$(PARAM_TX_SEQ_NUM_COUNT)" \
	      "tx_seq_w=$(PARAM_TX_SEQ_NUM_WIDTH)" \
	      "src=$(RQ_SRC)" \
	      "sim=$(SIM)"

.PHONY: arms
arms:
	$(MAKE) RQ_STRADDLE_ENC=1 SIM_BUILD=sim_build_enc1 COCOTB_RESULTS_FILE=results_enc1.xml
	$(MAKE) RQ_STRADDLE_ENC=0 SIM_BUILD=sim_build_enc0 COCOTB_RESULTS_FILE=results_enc0.xml

.PHONY: elab-refuse
elab-refuse:
	@rm -rf elab_refuse && mkdir -p elab_refuse
	$(call elaborate_and_require_acceptance,legal_1024,$(ELAB_1024_OK))
	$(call elaborate_and_require_refusal,width_512,$(ELAB_WIDTH_512))
	$(call elaborate_and_require_refusal,user_137,$(ELAB_USER_137))
	$(call elaborate_and_require_refusal,tx_seq_num_count_2,$(ELAB_TX_SEQ_2))
	$(call elaborate_and_require_refusal,rq_seq_num_width_4,$(ELAB_SEQ_NUM_4))
	@echo "ELAB-REFUSE: every illegal configuration refused, the legal one accepted"

.PHONY: lint
lint:
	verilator --lint-only --top-module $(DUT) \
	    -GRQ_STRADDLE_ENC=$(RQ_STRADDLE_ENC) $(VERILOG_SOURCES)

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
