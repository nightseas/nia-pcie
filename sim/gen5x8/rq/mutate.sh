#!/bin/bash
# ---------------------------------------------------------------------------
# File        : mutate.sh
# Description : Mutation gate for pcie_versal_if_rq. Runs the unmutated source
#               first and stops unless it passes, then injects one defect at a
#               time, runs the acceptance set, restores the source, and requires
#               every mutation to be caught by the test named with it.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Bash
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
RTL="$NIA_ROOT/rtl/gen5x8/pcie_versal_if_rq.sv"
WORK="$HERE/mut_work"
SIM="${SIM:-icarus}"
ARMS="${ARMS:-1 0}"
TIMEOUT="${TIMEOUT:-1800}"
ONLY="${1:-}"

MUTATIONS=(
"n1_is_sop0_ptr_off_lane_zero|test_t1_read_request_descriptor_and_byte_enables|1|s@((_tuser_next\[53:52\]|is_sop0_ptr(_next|_reg)?)[[:space:]]*=[[:space:]]*)[^;]+;@\1 2'b01;@g"
"n2_is_eop0_ptr_off_by_one|test_t2_write_request_payload_sizes_and_eop_ptr|1|s@((_tuser_next\[68:64\]|is_eop0_ptr(_next|_reg)?)[[:space:]]*=[[:space:]]*)([^;]+);@\1 (\4) + 5'd1;@g"
"n3_first_be_zeroed|test_t1_read_request_descriptor_and_byte_enables|1 0|s@((_tuser_next\[3:0\]|(rq_)?first_be(0)?(_next|_reg)?)[[:space:]]*=[[:space:]]*)[^;]+;@\1 4'd0;@g"
"n4_seq_num0_held|test_t5_sequence_numbers_returned_exactly_once|1 0|s@((_tuser_next\[354:349\]|seq_num0(_next|_reg)?)[[:space:]]*=[[:space:]]*)[^;]+;@\1 6'd9;@g"
"n5_one_beat_dropped|test_t4_interleaved_ports_under_backpressure_keep_every_byte|1 0|s@(m_axis_rq_tvalid_next[[:space:]]*=[[:space:]]*)m_axis_rq_tvalid_reg[[:space:]]*&&[[:space:]]*!m_axis_rq_tready[[:space:]]*;@\1 1'b0;@"
"n6_is_sop_claims_two_starts|test_t3_interleaved_ports_saturated_keep_order|1|s@((_tuser_next\[51:48\]|is_sop(_next|_reg)?)[[:space:]]*=[[:space:]]*)([^;]+);@\1 ((\4) == 4'b0001 ? 4'b0011 : (\4));@g"
"n7_tkeep_and_tlast_driven|test_t2_write_request_payload_sizes_and_eop_ptr|1|s@(m_axis_rq_tkeep_next[[:space:]]*=[[:space:]]*)[^;]+;@\1 {32{1'b1}};@g; s@(m_axis_rq_tlast_next[[:space:]]*=[[:space:]]*)[^;]+;@\1 1'b1;@g"
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

run_arm() {
    local dir="$1" src="$2" enc="$3" tag="$4"
    ( cd "$HERE" && timeout "$TIMEOUT" make SIM="$SIM" RQ_STRADDLE_ENC="$enc" \
          RQ_SRC="$src" SIM_BUILD="$dir/sim_build_$tag" \
          COCOTB_RESULTS_FILE="$dir/results_$tag.xml" ) > "$dir/run_$tag.log" 2>&1
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

for enc in $ARMS; do
    run_arm "$base" "$RTL" "$enc" "enc$enc"
    bt=$(case_count "$base/results_enc$enc.xml")
    bad=$(failing_names "$base/results_enc$enc.xml" | wc -l)
    if [ ! -f "$base/results_enc$enc.xml" ] || [ "$bt" -eq 0 ] || [ "$bad" -gt 0 ]; then
        {
            echo "BASELINE FAILED at RQ_STRADDLE_ENC=$enc: the unmutated module does not"
            echo "  pass, so no mutation result would mean anything."
            echo "  testcases=$bt failing=$bad log $base/run_enc$enc.log"
            if [ ! -f "$base/results_enc$enc.xml" ]; then
                echo "  No results file was written: the simulator or cocotb did not run."
                echo "  Check that cocotb-config is on PATH and that SIM=$SIM is installed."
            fi
            failing_names "$base/results_enc$enc.xml" | sed 's/^/  failing: /'
            echo "RESULT: FAIL (baseline)"
        } | tee -a "$WORK/summary.txt"
        exit 2
    fi
    echo "BASELINE enc=$enc: PASS ($bt testcases)" | tee -a "$WORK/summary.txt"
done

total=0
caught=0
survived=0
inconclusive=0

for spec in "${MUTATIONS[@]}"; do
    IFS='|' read -r name test arms expr <<< "$spec"
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

    verdict="CAUGHT"
    detail=""

    for enc in $arms; do
        case " $ARMS " in
            *" $enc "*) ;;
            *) continue ;;
        esac

        run_arm "$d" "$d/mutated.sv" "$enc" "enc$enc"
        t=$(case_count "$d/results_enc$enc.xml")
        names=$(failing_names "$d/results_enc$enc.xml")

        if [ ! -f "$d/results_enc$enc.xml" ] || [ "$t" -eq 0 ]; then
            verdict="NO-RESULT"
            detail="$detail enc$enc:the set did not run"
            continue
        fi

        if echo "$names" | grep -qx "$test"; then
            detail="$detail enc$enc:caught-by-$test"
        elif [ -n "$names" ]; then
            verdict="WRONG-TEST"
            detail="$detail enc$enc:failed-in-$(echo $names | tr ' ' ',')-not-$test"
        else
            verdict="SURVIVED"
            detail="$detail enc$enc:no-test-failed"
        fi
    done

    case "$verdict" in
        CAUGHT)
            echo "$name ($test): CAUGHT -$detail" | tee -a "$WORK/summary.txt"
            caught=$((caught+1))
            ;;
        NO-RESULT)
            echo "$name ($test): NO-RESULT -$detail, logs in $d" | tee -a "$WORK/summary.txt"
            inconclusive=$((inconclusive+1))
            ;;
        WRONG-TEST)
            echo "$name ($test): WRONG-TEST -$detail" | tee -a "$WORK/summary.txt"
            survived=$((survived+1))
            ;;
        *)
            echo "$name ($test): SURVIVED -$detail, $test does not gate this defect" \
                | tee -a "$WORK/summary.txt"
            survived=$((survived+1))
            ;;
    esac
done

echo "-----" | tee -a "$WORK/summary.txt"
echo "MUTATIONS total=$total caught=$caught survived=$survived no_result=$inconclusive arms='$ARMS'" \
    | tee -a "$WORK/summary.txt"

if [ "$survived" -eq 0 ] && [ "$inconclusive" -eq 0 ] && [ "$total" -gt 0 ]; then
    echo "RESULT: PASS (every mutation caught by the test named with it)" | tee -a "$WORK/summary.txt"
    exit 0
fi

echo "RESULT: FAIL" | tee -a "$WORK/summary.txt"
exit 1
