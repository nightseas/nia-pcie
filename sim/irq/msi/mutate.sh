#!/bin/bash
# ---------------------------------------------------------------------------
# File        : mutate.sh
# Description : Mutation gate for pcie_versal_msi_adapt. Runs the unmutated source
#               first and stops unless it passes, then injects one defect at a
#               time into a copy the run reads through MSI_SRC, so the checked in
#               source is never edited, and requires every mutation to be caught by
#               the test named with it. The name beside each mutation is the
#               property the injected defect breaks.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Bash
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------


set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIA_ROOT="${NIA_ROOT:-$(d="$HERE"; until [ -f "$d/.nia-repo-root" ]; do [ "$d" = / ] && exit 1; d="$(dirname "$d")"; done; printf '%s' "$d")}"
[ -n "$NIA_ROOT" ] && [ -f "$NIA_ROOT/.nia-repo-root" ] || {
    echo "mutate.sh: no .nia-repo-root at or above $HERE; this folder has been copied out of" >&2
    echo "           the nia-pcie tree, so set NIA_ROOT to the checkout" >&2
    exit 2
}
RTL="$NIA_ROOT/rtl/irq/pcie_versal_msi_adapt.sv"
WORK="$HERE/mut_work"
SIM="${SIM:-icarus}"
TIMEOUT="${TIMEOUT:-900}"
ONLY="${1:-}"

MUTATIONS=(
"j1_enable_pad_ones|test_widened_fields_pad_is_zero|s@(assign us_cfg_interrupt_msi_enable   = \{\{\(US_ENABLE_W-CPM5_ENABLE_W\)\{)1'b0@\1 1'b1@"
"j2_enable_shifted|test_widened_fields_preserve_value|s@(assign us_cfg_interrupt_msi_enable   = )\{\{\(US_ENABLE_W-CPM5_ENABLE_W\)\{1'b0\}\}, cpm_cfg_msi_enable\};@\1 {{(US_ENABLE_W-CPM5_ENABLE_W-1){1'b0}}, cpm_cfg_msi_enable, 1'b0};@"
"j3_mmenable_pad_ones|test_widened_fields_pad_is_zero|s@(assign us_cfg_interrupt_msi_mmenable = \{\{\(US_MMENABLE_W-CPM5_MMENABLE_W\)\{)1'b0@\1 1'b1@"
"j4_select_pad_ones|test_widened_fields_pad_is_zero|s@(assign cpm_cfg_msi_select     = \{\{\(CPM5_SELECT_W-US_SELECT_W\)\{)1'b0@\1 1'b1@"
"j5_select_shifted|test_widened_fields_preserve_value|s@(assign cpm_cfg_msi_select     = )\{\{\(CPM5_SELECT_W-US_SELECT_W\)\{1'b0\}\}, us_cfg_interrupt_msi_select\};@\1 {{(CPM5_SELECT_W-US_SELECT_W-1){1'b0}}, us_cfg_interrupt_msi_select, 1'b0};@"
"j6_func_num_pad_ones|test_widened_fields_pad_is_zero|s@(\{\{\(CPM5_FUNC_NUM_W-US_FUNC_NUM_W\)\{)1'b0@\1 1'b1@"
"j7_psfn_pad_ones|test_widened_fields_pad_is_zero|s@(\{\{\(CPM5_PSFN_W-US_PSFN_W\)\{)1'b0@\1 1'b1@"
"j8_data_tied_low|test_passthrough_fields_are_identity|s@(assign us_cfg_interrupt_msi_data        = )cpm_cfg_msi_data;@\1 32'd0;@"
"j9_int_vector_inverted|test_passthrough_fields_are_identity|s@(assign cpm_cfg_msi_int_vector = )us_cfg_interrupt_msi_int;@\1 ~us_cfg_interrupt_msi_int;@"
"j10_sent_and_fail_swapped|test_no_cross_field_coupling|s@(assign us_cfg_interrupt_msi_sent        = )cpm_cfg_msi_sent;@\1 cpm_cfg_msi_fail;@"
"j11_tph_st_tag_truncated|test_passthrough_fields_are_identity|s@(assign cpm_cfg_msi_tph_st_tag  = )us_cfg_interrupt_msi_tph_st_tag;@\1 {1'b0, us_cfg_interrupt_msi_tph_st_tag[TPH_ST_TAG_W-1:1]};@"
"j12_pending_status_stuck|test_random_soak_every_field_independent|s@(assign cpm_cfg_msi_pending_status                  = )us_cfg_interrupt_msi_pending_status;@\1 32'hFFFFFFFF;@"
)

failing_names() {
    python3 -c '
import sys
import xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
for case in root.iter("testcase"):
    if list(case.iter("failure")) or list(case.iter("error")):
        print(case.get("name"))
' "$1" 2>/dev/null
}

case_count() {
    grep -o '<testcase' "$1" 2>/dev/null | wc -l
}

run_set() {
    local dir="$1" src="$2"
    ( cd "$HERE" && timeout "$TIMEOUT" make SIM="$SIM" MSI_SRC="$src" \
          SIM_BUILD="$dir/sim_build" COCOTB_RESULTS_FILE="$dir/results.xml" ) \
        > "$dir/run.log" 2>&1
}

mkdir -p "$WORK"
: > "$WORK/summary.txt"

if [ ! -f "$RTL" ]; then
    {
        echo "RTL NOT PRESENT: $RTL"
        echo "RESULT: FAIL (no module to mutate)"
    } | tee -a "$WORK/summary.txt"
    exit 2
fi

base="$WORK/baseline"
rm -rf "$base"
mkdir -p "$base"
run_set "$base" "$RTL"
bt=$(case_count "$base/results.xml")
bad=$(failing_names "$base/results.xml" | wc -l)
if [ ! -f "$base/results.xml" ] || [ "$bt" -eq 0 ] || [ "$bad" -gt 0 ]; then
    {
        echo "BASELINE FAILED: the unmutated module does not pass, so no mutation result would"
        echo "  mean anything. testcases=$bt failing=$bad log $base/run.log"
        if [ ! -f "$base/results.xml" ]; then
            echo "  No results file was written: the simulator or cocotb did not run."
            echo "  Check that cocotb-config is on PATH and that SIM=$SIM is installed."
        fi
        failing_names "$base/results.xml" | sed 's/^/  failing: /'
        echo "RESULT: FAIL (baseline)"
    } | tee -a "$WORK/summary.txt"
    exit 2
fi
echo "BASELINE: PASS ($bt testcases)" | tee -a "$WORK/summary.txt"

total=0
caught=0
survived=0
inconclusive=0

for spec in "${MUTATIONS[@]}"; do
    IFS='|' read -r name test expr <<< "$spec"
    if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then
        continue
    fi

    total=$((total+1))
    d="$WORK/$name"
    rm -rf "$d"
    mkdir -p "$d"

    sed -E "$expr" "$RTL" > "$d/mutated.sv"

    if cmp -s "$RTL" "$d/mutated.sv"; then
        echo "$name ($test): SED-DID-NOT-APPLY  <-- fix mutate.sh against the module text, not the module" \
            | tee -a "$WORK/summary.txt"
        survived=$((survived+1))
        continue
    fi

    run_set "$d" "$d/mutated.sv"
    t=$(case_count "$d/results.xml")
    names=$(failing_names "$d/results.xml")

    if [ ! -f "$d/results.xml" ] || [ "$t" -eq 0 ]; then
        echo "$name ($test): NO-RESULT, the set did not run, logs in $d" | tee -a "$WORK/summary.txt"
        inconclusive=$((inconclusive+1))
        continue
    fi

    if echo "$names" | grep -qx "$test"; then
        echo "$name ($test): CAUGHT - caught-by-$test" | tee -a "$WORK/summary.txt"
        caught=$((caught+1))
    elif [ -n "$names" ]; then
        echo "$name ($test): WRONG-TEST - failed-in-$(echo $names | tr ' ' ',')-not-$test" \
            | tee -a "$WORK/summary.txt"
        survived=$((survived+1))
    else
        echo "$name ($test): SURVIVED - no test failed, $test does not gate this defect" \
            | tee -a "$WORK/summary.txt"
        survived=$((survived+1))
    fi
done

echo "-----" | tee -a "$WORK/summary.txt"
echo "MUTATIONS total=$total caught=$caught survived=$survived no_result=$inconclusive" \
    | tee -a "$WORK/summary.txt"

if [ "$survived" -eq 0 ] && [ "$inconclusive" -eq 0 ] && [ "$total" -gt 0 ]; then
    echo "RESULT: PASS (every mutation caught by the test named with it)" | tee -a "$WORK/summary.txt"
    exit 0
fi

echo "RESULT: FAIL" | tee -a "$WORK/summary.txt"
exit 1
