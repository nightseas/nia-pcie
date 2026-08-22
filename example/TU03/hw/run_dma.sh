#!/bin/bash
# ---------------------------------------------------------------------------
# File        : run_dma.sh
# Description : Runs the endpoint example on a board through the reference
#               driver: builds it through driver/build.sh, loads it, captures a
#               register read and a DMA transfer, and unloads it.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TU03="$(cd "$HERE/.." && pwd)"
DRV_BUILD="$TU03/driver/build.sh"
BUILD="${BUILD:-$HOME/nia_pcie_hw/example_driver}"
LOGDIR="${LOGDIR:-$HOME/nia_pcie_hw/logs}"
KO="$BUILD/example.ko"
MODNAME="$(basename "$KO" .ko)"
BENCH="${NIA_BENCH:-}"

mkdir -p "$LOGDIR"

build() {
  echo "=== build the example driver OUT-OF-TREE, through driver/build.sh ==="
  if [ ! -x "$DRV_BUILD" ]; then echo "FAIL: $DRV_BUILD not found"; return 1; fi
  BUILD="$BUILD" "$DRV_BUILD" 2>&1 | tee "$LOGDIR/driver_build.log" | tail -12
  if [ -f "$KO" ]; then
    echo "PASS build: $KO ($(stat -c %s "$KO") B)"
  else
    echo "FAIL build - see $LOGDIR/driver_build.log"; return 1
  fi
}

load() {
  echo "=== load ==="
  if [ ! -f "$KO" ]; then echo "FAIL: $KO missing - run './run_dma.sh build' first"; return 1; fi
  if lsmod | awk '{print $1}' | grep -qx "$MODNAME"; then
    echo "$MODNAME is already loaded: unloading it first, so what follows is a fresh probe"
    sudo rmmod "$MODNAME" || { echo "FAIL: it is loaded and will not unload; something holds it"; return 1; }
    sleep 1
  fi
  sudo dmesg -C 2>/dev/null || true
  echo "insmod $KO${BENCH:+ bench=$BENCH}"
  if sudo insmod "$KO" ${BENCH:+bench=$BENCH}; then
    echo "PASS insmod returned 0"
  else
    echo "FAIL insmod: the module did not load, so nothing below would be about binding."
    echo "  Read the message above: a missing symbol or a kernel version mismatch is a build"
    echo "  problem, not an endpoint problem."
    return 1
  fi
  sleep 2
  echo "--- bound devices ---"
  for d in /sys/bus/pci/drivers/*/; do
    if [ "$(basename "$(readlink -f "$d/module" 2>/dev/null)")" = "$MODNAME" ]; then
      find "$d" -maxdepth 1 -name "0000:*" -printf "  %f bound to %h\n" 2>/dev/null | sed "s|/sys/bus/pci/drivers/||"
    fi
  done | grep . || echo "  (nothing bound)"
  echo "--- dmesg (the driver's own probe and test output) ---"
  sudo dmesg | tail -60 | tee "$LOGDIR/dmesg.log"
  echo
  echo "--- interpretation ---"
  DRVMSG=$(sudo dmesg | grep -viE "loading out-of-tree|module verification failed" | grep -iE "edev|example" || true)
  if [ -n "$DRVMSG" ]; then
    echo "  the driver probed: BAR mapping and its self-test result are above."
  else
    echo "  NO driver output at all, so it bound nothing. Most likely the endpoint reports an"
    echo "  identifier the driver's table does not carry, not a datapath fault: check"
    echo "  ./check_pcie.sh CHECK 6."
  fi
  if echo "$DRVMSG" | grep -qiE "error|fail|timeout|-12"; then
    echo "  errors present in the driver's own output, capture them. -12 (ENOMEM) after a hot"
    echo "  rescan is the known unassigned-window signature: reboot, do not rescan."
  fi
}

unload() {
  echo "=== unload, always before a reboot ==="
  sudo rmmod "$MODNAME" 2>/dev/null && echo "rmmod ok" || echo "(not loaded)"
}

case "${1:-}" in
  build)  build ;;
  load)   load ;;
  unload) unload ;;
  all)    build && load; unload ;;
  *) sed -n '13,23p' "$0"; exit 2 ;;
esac
