#!/bin/bash
# ---------------------------------------------------------------------------
# File        : check_pcie.sh
# Description : Host side enumeration preflight for the endpoint example. Each
#               check reports on its own, because the order is the diagnostic:
#               nothing downstream of an untrained link means anything.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set -u

VENDOR="${VENDOR:-10ee}"
DEVICE_ID="${DEVICE_ID:-0001}"
DRIVER_BINDS_ID="${DRIVER_BINDS_ID:-10ee:0001}"
EXPECT_LNK_SPEED="${EXPECT_LNK_SPEED:-16GT/s}"
EXPECT_LNK_WIDTH="${EXPECT_LNK_WIDTH:-x8}"
EXPECT_BAR0_MB="${EXPECT_BAR0_MB:-16}"

pass=0; fail=0; info=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
no()   { echo "  FAIL  $*"; fail=$((fail+1)); }
note() { echo "  INFO  $*"; info=$((info+1)); }
hdr()  { echo; echo "--- $* ---"; }

lspci_vv() { lspci -s "$1" -vvv 2>/dev/null; }

find_bdf() {
  local b
  b=$(lspci -d "${VENDOR}:${DEVICE_ID}" -mm 2>/dev/null | awk '{print $1}' | head -1)
  [ -z "$b" ] && b=$(lspci -d "${VENDOR}:" -mm 2>/dev/null | awk '{print $1}' | head -1)
  [ -n "$b" ] && { echo "$b"; return 0; }
  return 1
}

check_all() {
  echo "===== host checks $(date -Is) on $(hostname) ====="
  echo "kernel: $(uname -r)"

  hdr "CHECK 1  link trained"
  note "Not testable from software. The top level drives pcie_user_lnk_up_o on a pin;"
  note "read it on the board. Dark means the transceiver or the link state machine"
  note "never trained, so suspect the reference clock or the routed reset, not the adapter."

  hdr "CHECK 2  device enumerates"
  local bdf
  if bdf=$(find_bdf); then
    ok "endpoint present at $bdf"
    lspci -s "$bdf" -nn 2>/dev/null | sed 's/^/        /'
  else
    no "no endpoint found for ${VENDOR}:${DEVICE_ID}"
    echo
    echo "  If the pin is high but nothing enumerates, the usual cause is that the host was"
    echo "  not rebooted after programming: a new endpoint needs a reboot, not a rescan."
    echo "===== VERDICT: FAIL, nothing downstream to check ====="
    return 1
  fi

  hdr "CHECK 3  link speed and width"
  local sta
  sta=$(lspci_vv "$bdf" | grep -m1 "LnkSta:")
  echo "        ${sta:-(LnkSta not readable: run as root)}"
  if echo "$sta" | grep -q "$EXPECT_LNK_SPEED"; then ok "speed $EXPECT_LNK_SPEED"
  else note "speed is not $EXPECT_LNK_SPEED. A slot or a switch upstream of the card can"
       note "cap this, so a lower value may be the host's limit rather than a defect."; fi
  if echo "$sta" | grep -q "Width $EXPECT_LNK_WIDTH"; then ok "width $EXPECT_LNK_WIDTH"
  else no "width is not $EXPECT_LNK_WIDTH"; fi

  hdr "CHECK 4  memory windows assigned"
  local regions
  regions=$(lspci_vv "$bdf" | grep -E "Region [0-9]:")
  if [ -z "$regions" ]; then
    no "no regions reported: the firmware assigned no memory window"
  else
    echo "$regions" | sed 's/^/        /'
    local b0
    b0=$(echo "$regions" | grep -m1 "Region 0:" | grep -oE "size=[0-9]+[KMG]" | tail -1 | cut -d= -f2)
    echo "        region 0 size reported: ${b0:-unknown}"
    if [ "${b0:-}" = "${EXPECT_BAR0_MB}M" ]; then ok "region 0 is ${EXPECT_BAR0_MB}M, matching BAR0_APERTURE = 24"
    else no "region 0 is ${b0:-unknown}, expected ${EXPECT_BAR0_MB}M: the block design and the core disagree"; fi
    if echo "$regions" | grep -q "Region 2:"; then ok "region 2 present"
    else no "region 2 absent: the memory master half of the example cannot be tested"; fi
  fi

  hdr "CHECK 5  message signalled interrupts"
  local msix
  msix=$(lspci_vv "$bdf" | grep -A2 "MSI-X:" | head -3)
  if [ -n "$msix" ]; then echo "$msix" | sed 's/^/        /'
    ok "MSI-X capability present; the block design advertises 8 vectors"
  else no "no MSI-X capability advertised"; fi

  hdr "CHECK 6  the driver will bind"
  local vid
  vid=$(lspci -s "$bdf" -n 2>/dev/null | awk '{print $3}')
  echo "        device reports  : $vid"
  echo "        driver table has: ${DRIVER_BINDS_ID}"
  if echo "$vid" | grep -qi "^${DRIVER_BINDS_ID}"; then
    ok "the identifier matches the driver's table, so it binds unmodified"
  else
    no "the driver's table binds ${DRIVER_BINDS_ID} and this device reports $vid: it will not bind"
    echo "        Either the design reports an identifier it is not meant to, or the table is"
    echo "        stale. driver/build.sh patches the table; point it at $vid, or pass"
    echo "        DRIVER_BINDS_ID=$vid here once that is done."
  fi

  echo
  echo "===== SUMMARY: pass=$pass fail=$fail info=$info ====="
  if [ "$fail" -eq 0 ]; then
    echo "===== RESULT: enumeration passed, proceed to ./run_dma.sh ====="
  else
    echo "===== RESULT: FAIL, resolve the flagged items before spending board time ====="
    return 1
  fi
}

case "${1:-}" in
  all) check_all ;;
  *) sed -n '13,35p' "$0"; exit 2 ;;
esac
