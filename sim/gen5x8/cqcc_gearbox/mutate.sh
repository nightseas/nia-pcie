#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# File        : mutate.sh
# Description : Mutation gate for pcie_versal_if_cqcc_gearbox. Runs the unmutated
#               source first and stops unless it passes, then injects one defect at
#               a time, runs the acceptance set, restores the source, and requires
#               every mutation to be caught by the test named with it.
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
RTL="$NIA_ROOT/rtl/gen5x8/pcie_versal_if_cqcc_gearbox.sv"
WORK="$HERE/mut_work"
SIM="${SIM:-icarus}"
TIMEOUT="${TIMEOUT:-1800}"
ONLY="${1:-}"

MUTATIONS=(
"n9_skid_bypassed|test_t8c_completer_request_ready_is_a_register_output|s@(assign s_axis_cq_tready = )cq_in_ready_reg;@\1cq_reg_ready;@"
"n10_input_always_ready|test_t8b_completer_request_bytes_survive_back_pressure|s@(cq_in_ready_reg <= )!cq_skid_tvalid_next;@\1 1'b1;@"
"n11_skid_never_drains|test_t8b_completer_request_bytes_survive_back_pressure|s@(cq_reg_tvalid_next = )cq_skid_tvalid;@\1 1'b0;@"
"n12_high_half_dropped|test_t8a_completer_request_bytes_survive_the_split|s@(wire cq_last_half = )[^;]+;@\1 1'b1;@"
"n14_cc_align_detector_muted|test_t12_completer_completion_start_alignment_is_reported|s@(cc_map_align_err = )1'b1;@\1 1'b0;@"
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
    ( cd "$HERE" && timeout "$TIMEOUT" make SIM="$SIM" GEARBOX_SRC="$src" \
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
        echo "BASELINE FAILED: the unmutated module does not pass, so no mutation result"
        echo "  would mean anything. testcases=$bt failing=$bad log $base/run.log"
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
