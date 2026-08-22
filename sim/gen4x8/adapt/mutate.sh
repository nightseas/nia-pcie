#!/bin/bash
# ---------------------------------------------------------------------------
# File        : mutate.sh
# Description : Mutation gate for pcie_versal_adapt. Runs the unmutated source
#               first and stops unless it passes, then injects one defect at a
#               time, runs the acceptance set, restores the source, and requires
#               every mutation to be caught by the test named with it. The name beside
#               each mutation is the property the injected defect breaks.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
NIA_ROOT="${NIA_ROOT:-$(d="$HERE"; until [ -f "$d/.nia-repo-root" ]; do [ "$d" = / ] && exit 1; d="$(dirname "$d")"; done; printf '%s' "$d")}"
[ -n "$NIA_ROOT" ] && [ -f "$NIA_ROOT/.nia-repo-root" ] || {
    echo "mutate.sh: no .nia-repo-root at or above $HERE; this folder has been copied out of" >&2
    echo "           the nia-pcie tree, so set NIA_ROOT to the checkout" >&2
    exit 2
}
RTL="$NIA_ROOT/rtl/gen4x8/pcie_versal_adapt.sv"
WORK="$HERE/mut_work"
SIM="${SIM:-icarus}"
TIMEOUT="${TIMEOUT:-900}"
ONLY="${1:-}"

MUTATIONS=(
"m1_rq_shift|rq_tuser_identity|s|assign cpm_rq_tuser  = {{(CPM5_RQ_USER_W-US_RQ_USER_W){1'b0}}, us_rq_tuser};|assign cpm_rq_tuser  = {{(CPM5_RQ_USER_W-US_RQ_USER_W-1){1'b0}}, us_rq_tuser, 1'b0};|"
"m2_rq_pasid_ones|rq_upper_span_zero|s|assign cpm_rq_tuser  = {{(CPM5_RQ_USER_W-US_RQ_USER_W){1'b0}}, us_rq_tuser};|assign cpm_rq_tuser  = {{(CPM5_RQ_USER_W-US_RQ_USER_W){1'b1}}, us_rq_tuser};|"
"m3_cq_off_by_one|cq_tuser_identity|s|assign us_cq_tuser   = cpm_cq_tuser\[US_CQ_USER_W-1:0\];|assign us_cq_tuser   = cpm_cq_tuser[US_CQ_USER_W:1];|"
"m4_poison_dropped|cq_poison_surfaced|s|sts_cq_poisoned_tlp_reg <= cpm_cq_tuser\[CQ_POISON_LO +: 2\];|sts_cq_poisoned_tlp_reg <= 2'b00;|"
"m5_poison_not_sticky|cq_poison_surfaced|s|sts_cq_poisoned_seen_reg <= 1'b1;|sts_cq_poisoned_seen_reg <= 1'b0;|"
"m6_poison_wrong_bits|cq_poison_surfaced|s|localparam CQ_POISON_LO = 229;|localparam CQ_POISON_LO = 227;|"
"m7_rc_truncated|rc_passthrough|s|assign us_rc_tuser   = cpm_rc_tuser;|assign us_rc_tuser   = {4'd0, cpm_rc_tuser[RC_USER_W-1:4]};|"
"m8_cc_truncated|cc_passthrough|s|assign cpm_cc_tuser  = us_cc_tuser;|assign cpm_cc_tuser  = {2'd0, us_cc_tuser[CC_USER_W-1:2]};|"
"m9_tready_stuck|tready_transparent|s|assign us_rq_tready  = cpm_rq_tready;|assign us_rq_tready  = 1'b1;|"
"m10_rq_data_swap|data_path_identity|s|assign cpm_rq_tdata  = us_rq_tdata;|assign cpm_rq_tdata  = {us_rq_tdata[DATA_W-2:0], 1'b0};|"
)

run_set() {
    local dir="$1" src="$2"
    ( cd "$HERE" && timeout "$TIMEOUT" make SIM="$SIM" \
          ADAPT_SRC="$src" SIM_BUILD="$dir/sim_build" \
          COCOTB_RESULTS_FILE="$dir/results.xml" ) > "$dir/run.log" 2>&1
}

count() { grep -o "$1" "$2" 2>/dev/null | wc -l; }

mkdir -p "$WORK"
pass=0; surv=0; total=0; inconc=0
: > "$WORK/summary.txt"

if [ ! -f "$RTL" ]; then
    {
        echo "RTL NOT PRESENT: $RTL"
        echo "RESULT: FAIL (no module to mutate)"
    } | tee -a "$WORK/summary.txt"
    exit 2
fi

base="$WORK/baseline"; rm -rf "$base"; mkdir -p "$base"
run_set "$base" "$RTL"
bf=$(count '<failure' "$base/results.xml")
be=$(count '<error' "$base/results.xml")
bt=$(count '<testcase' "$base/results.xml")
if [ ! -f "$base/results.xml" ] || [ "$bt" -eq 0 ] || [ "$((bf+be))" -gt 0 ]; then
    {
        echo "BASELINE FAILED: the unmutated source does not pass, so no mutation result would"
        echo "  mean anything. testcases=$bt failures=$bf errors=$be, log $base/run.log"
        if [ ! -f "$base/results.xml" ]; then
            echo "  No results file was written at all: the simulator or cocotb did not run."
            echo "  Check that cocotb-config is on PATH and that SIM=$SIM is installed."
        fi
        echo "RESULT: FAIL (baseline)"
    } | tee -a "$WORK/summary.txt"
    exit 2
fi
echo "BASELINE: PASS ($bt testcases, 0 failures, 0 errors)" | tee -a "$WORK/summary.txt"

for spec in "${MUTATIONS[@]}"; do
    IFS='|' read -r name prop expr <<< "$spec"
    if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ]; then
        continue
    fi

    total=$((total+1))
    d="$WORK/$name"; rm -rf "$d"; mkdir -p "$d"
    sed "$expr" "$RTL" > "$d/mutated.sv"

    if cmp -s "$RTL" "$d/mutated.sv"; then
        echo "$name ($prop): SED-DID-NOT-APPLY  <-- fix mutate.sh against the module text, not the module" \
            | tee -a "$WORK/summary.txt"
        surv=$((surv+1)); continue
    fi

    run_set "$d" "$d/mutated.sv"
    f=$(count '<failure' "$d/results.xml")
    e=$(count '<error' "$d/results.xml")
    t=$(count '<testcase' "$d/results.xml")

    if [ ! -f "$d/results.xml" ] || [ "$t" -eq 0 ]; then
        echo "$name ($prop): NO-RESULT - the set did not run, so nothing was proved: $d/run.log" \
            | tee -a "$WORK/summary.txt"
        inconc=$((inconc+1))
    elif [ "$((f+e))" -gt 0 ]; then
        echo "$name ($prop): CAUGHT (failures=$f errors=$e of $t testcases)" | tee -a "$WORK/summary.txt"
        pass=$((pass+1))
    else
        echo "$name ($prop): SURVIVED - $prop is NOT actually gated" | tee -a "$WORK/summary.txt"
        surv=$((surv+1))
    fi
done

echo "-----" | tee -a "$WORK/summary.txt"
echo "MUTATIONS total=$total caught=$pass survived=$surv no_result=$inconc" | tee -a "$WORK/summary.txt"
if [ "$surv" -eq 0 ] && [ "$inconc" -eq 0 ] && [ "$total" -gt 0 ]; then
    echo "RESULT: PASS (every mutation caught)" | tee -a "$WORK/summary.txt"
    exit 0
fi
echo "RESULT: FAIL" | tee -a "$WORK/summary.txt"
exit 1
