#!/bin/bash
# ---------------------------------------------------------------------------
# File        : mutate.sh
# Description : Mutation gate for pcie_versal_msix_adapt. Runs the unmutated source
#               first and stops unless it passes, then injects one defect at a
#               time into a copy the run reads through MSIX_SRC, so the checked in
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
RTL="$NIA_ROOT/rtl/irq/pcie_versal_msix_adapt.sv"
WORK="$HERE/mut_work"
SIM="${SIM:-icarus}"
TIMEOUT="${TIMEOUT:-1800}"
ONLY="${1:-}"

MUTATIONS=(
"k1_mint_vector_onehot|test_vector_fidelity_binary_not_onehot|s@(mint_valid_reg \? )[^:]+( : 32'd0;)@\1(32'd1 << vec_reg)\2@"
"k2_accept_ready_held|test_d2_one_accept_per_ready_beat|s@irq_ready_next = 1'b0;@irq_ready_next = 1'b1;@"
"k3_ready_in_every_state|test_d2_one_accept_per_ready_beat|s@(irq_ready_next   = )1'b0;@\1 1'b1;@"
"k4_out_of_range_admitted|test_d4_out_of_range_is_dropped_not_stalled|s@(wire index_in_range = )[^;]+;@\1 1'b1;@"
"k5_disabled_admitted|test_d5_disabled_is_dropped_not_stalled|s@end else if \(!cfg_msix_enable\) begin@end else if (1'b0) begin@"
"k6_mask_filters_the_vector|test_d6_function_masked_is_still_forwarded|s@end else if \(!cfg_msix_enable\) begin@end else if (!cfg_msix_enable || cfg_msix_mask) begin@"
"k7_retry_unbounded|test_d3_fail_is_retransmitted_then_bounded|s@if \(retry_reg < FAIL_RETRY_LIMIT\) begin@if (1'b1) begin@"
"k8_vec_pending_moves|test_d7_static_pins_never_move|s@(assign cfg_msix_vec_pending     = )2'b00;@\1 2'b01;@"
"k9_sent_counter_wraps|test_d8_counters_saturate|s@if \(c_sent_reg != \{STS_COUNT_WIDTH\{1'b1\}\}\) (c_sent_next = c_sent_reg \+ 1;)@\1@"
"k10_reset_leaves_state|test_d9_reset_mid_request_is_clean|s@(state_reg       <= )ST_IDLE;@\1 state_next;@"
"k11_index_off_by_one|test_random_burst_no_loss_no_reorder|s@(vec_next   = )irq_index;@\1 irq_index + 1;@"
"k12_stale_vector_latch|test_d1_one_outstanding_request|s@(vec_next   = )irq_index;@\1 vec_reg;@"
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
    ( cd "$HERE" && timeout "$TIMEOUT" make SIM="$SIM" MSIX_SRC="$src" \
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
