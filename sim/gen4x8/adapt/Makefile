# ---------------------------------------------------------------------------
# File        : Makefile
# Description : cocotb acceptance run for pcie_versal_adapt. Names the
#               adapter as its only source, selects the simulator, and is
#               shaped after the reference libraries' own testbench Makefiles.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------


TOPLEVEL_LANG = verilog
SIM          ?= icarus
WAVES        ?= 0

DUT      = pcie_versal_adapt
TOPLEVEL = $(DUT)
MODULE   = test_$(DUT)

TB_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NIA_ROOT  ?= $(shell d='$(TB_DIR)'; while [ ! -f "$$d/.nia-repo-root" ]; do [ "$$d" = / ] && exit 1; d=$$(dirname "$$d"); done; printf '%s' "$$d")
ifeq ($(wildcard $(NIA_ROOT)/.nia-repo-root),)
$(error no .nia-repo-root at or above $(TB_DIR): this folder has been copied out of the nia-pcie tree, so set NIA_ROOT to the checkout, for example NIA_ROOT=/path/to/nia-pcie)
endif

RTL_DIR   ?= $(NIA_ROOT)/rtl/gen4x8

ADAPT_SRC ?= $(RTL_DIR)/$(DUT).sv
export ADAPT_SRC

VERILOG_SOURCES += $(ADAPT_SRC)

export PARAM_DATA_W         ?= 512
export PARAM_CPM5_RQ_USER_W ?= 183
export PARAM_CPM5_CQ_USER_W ?= 231
export PARAM_US_RQ_USER_W   ?= 137
export PARAM_US_CQ_USER_W   ?= 183
export PARAM_RC_USER_W      ?= 161
export PARAM_CC_USER_W      ?= 81

ifeq ($(SIM),icarus)
    PLUSARGS += -fst
    COMPILE_ARGS += -P $(TOPLEVEL).DATA_W=$(PARAM_DATA_W)
    COMPILE_ARGS += -P $(TOPLEVEL).CPM5_RQ_USER_W=$(PARAM_CPM5_RQ_USER_W)
    COMPILE_ARGS += -P $(TOPLEVEL).CPM5_CQ_USER_W=$(PARAM_CPM5_CQ_USER_W)
    COMPILE_ARGS += -P $(TOPLEVEL).US_RQ_USER_W=$(PARAM_US_RQ_USER_W)
    COMPILE_ARGS += -P $(TOPLEVEL).US_CQ_USER_W=$(PARAM_US_CQ_USER_W)
    COMPILE_ARGS += -P $(TOPLEVEL).RC_USER_W=$(PARAM_RC_USER_W)
    COMPILE_ARGS += -P $(TOPLEVEL).CC_USER_W=$(PARAM_CC_USER_W)
    ifeq ($(WAVES),1)
        VERILOG_SOURCES += iverilog_dump.v
        COMPILE_ARGS += -s iverilog_dump
    endif
else ifeq ($(SIM),verilator)
    COMPILE_ARGS += -Wno-fatal
    COMPILE_ARGS += -GDATA_W=$(PARAM_DATA_W)
    COMPILE_ARGS += -GCPM5_RQ_USER_W=$(PARAM_CPM5_RQ_USER_W)
    COMPILE_ARGS += -GCPM5_CQ_USER_W=$(PARAM_CPM5_CQ_USER_W)
    COMPILE_ARGS += -GUS_RQ_USER_W=$(PARAM_US_RQ_USER_W)
    COMPILE_ARGS += -GUS_CQ_USER_W=$(PARAM_US_CQ_USER_W)
    COMPILE_ARGS += -GRC_USER_W=$(PARAM_RC_USER_W)
    COMPILE_ARGS += -GCC_USER_W=$(PARAM_CC_USER_W)
    ifeq ($(WAVES),1)
        COMPILE_ARGS += --trace-fst
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	@echo 'module iverilog_dump();' > $@
	@echo 'initial begin' >> $@
	@echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	@echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	@echo 'end' >> $@
	@echo 'endmodule' >> $@

.PHONY: elab-check
elab-check:
	@echo "widths: elaborate the adapter and confirm the US+ face widths match the library's"
	verilator --lint-only -Wno-fatal --top-module $(DUT) $(ADAPT_SRC)
	@grep -q 'US_RQ_USER_W != 137' $(ADAPT_SRC) && echo "  RQ 137 guard present"
	@grep -q 'US_CQ_USER_W != 183' $(ADAPT_SRC) && echo "  CQ 183 guard present"
	@grep -q 'RC_USER_W != 161'    $(ADAPT_SRC) && echo "  RC 161 guard present"
	@grep -q 'CC_USER_W != 81'     $(ADAPT_SRC) && echo "  CC  81 guard present"

.PHONY: mutate
mutate:
	@./mutate.sh

clean::
	@rm -rf sim_build sim_build_* results*.xml iverilog_dump.v *.fst __pycache__ mut_work
