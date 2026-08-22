#!/bin/bash
# ---------------------------------------------------------------------------
# File        : program.sh
# Description : Programs a device image onto the board over JTAG and verifies
#               that it took, by reading the tool log rather than trusting an
#               exit status. It does not reboot the host, which a new endpoint
#               needs before it enumerates.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set -u

DEVICE="${NIA_DEVICE:-xcvp1552_1}"
TARGET="${NIA_TARGET:-}"
HW_URL="${NIA_HW_URL:-localhost:3121}"
VIVADO="${NIA_VIVADO:-}"
VIVADO_BIN="${NIA_VIVADO_BIN:-vivado}"
HOST="${NIA_HOST:-}"
USER_="${NIA_USER:-$(id -un)}"
SSH_OPTS="${NIA_SSH_OPTS:-}"
WORK="${NIA_WORK:-\$HOME/nia_pcie_hw}"
PDI_LOCAL="${PDI:-}"
SRC=""

if [ -n "$HOST" ]; then
  run() { ssh $SSH_OPTS "$USER_@$HOST" "$@"; }
  put() { scp $SSH_OPTS "$1" "$USER_@$HOST:$2" >/dev/null; }
  WHERE="$USER_@$HOST"
else
  run() { bash -c "$*"; }
  put() { [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] && { echo "image is already at the destination; no copy needed"; return 0; }; cp "$1" "$2"; }
  WHERE="this host"
fi

banner() { echo; echo "=================== $* ==================="; }

precheck() {
  banner "PRECONDITIONS"
  if [ -z "$PDI_LOCAL" ]; then echo "FAIL: no image given. Set PDI=<path>."; return 1; fi
  if [ ! -f "$PDI_LOCAL" ]; then echo "FAIL: image not found: $PDI_LOCAL"; return 1; fi
  echo "image    : $PDI_LOCAL"
  echo "size     : $(stat -c %s "$PDI_LOCAL") B"
  echo "md5      : $(md5sum "$PDI_LOCAL" | cut -d' ' -f1)"
  echo "target   : $WHERE, device $DEVICE"

  banner "TOOL"
  if [ -n "$VIVADO" ]; then
    if run "[ -f $VIVADO ]"; then
      echo "settings : $VIVADO   (given by NIA_VIVADO)"
      SRC="source $VIVADO && "
    else
      echo "FAIL: NIA_VIVADO names no file there: $VIVADO"
      return 1
    fi
  else
    SRC=""
  fi
  if run "${SRC}command -v $VIVADO_BIN"; then
    :
  else
    echo "FAIL: '$VIVADO_BIN' is not on the path there."
    echo "      Source your install's settings script in the shell that runs this, or set"
    echo "      NIA_VIVADO to that script. A Lab Edition install carries vivado_lab and no"
    echo "      vivado: set NIA_VIVADO_BIN accordingly."
    return 1
  fi

  banner "JTAG TARGETS"
  if [ -n "$TARGET" ]; then echo "selecting targets matching: $TARGET"
  else echo "no NIA_TARGET given: the first target will be used"; fi

  banner "SHARED MACHINE"
  echo "--- other builds running there, which a reboot would end ---"
  BUILDS=$(run 'ps -eo user,pid,etime,args --sort=-etime | grep -E "(^|/)(vivado|vivado_lab)( |$)|unwrapped/lnx64\.o/vivado" | grep -v "[g]rep" | head -5 | cut -c1-110')
  if [ -n "$BUILDS" ]; then echo "$BUILDS"; else echo "(none)"; fi
}

program() {
  precheck || return 1
  REMOTE_WORK=$(run "eval echo $WORK")
  REMOTE_PDI="$REMOTE_WORK/$(basename "$PDI_LOCAL")"

  banner "UPLOAD"
  run "mkdir -p $REMOTE_WORK"
  put "$PDI_LOCAL" "$REMOTE_PDI"
  echo "there md5: $(run "md5sum $REMOTE_PDI | cut -d' ' -f1")"
  echo "here  md5: $(md5sum "$PDI_LOCAL" | cut -d' ' -f1)   these must match"

  banner "PROGRAM over JTAG"
  run "cat > $REMOTE_WORK/program.tcl <<'EOT'
open_hw_manager
connect_hw_server -url $HW_URL
set targets [get_hw_targets]
puts \"NIA_TARGETS: \$targets\"
set want {$TARGET}
set chosen [lindex \$targets 0]
if {\$want ne {}} {
  set hits {}
  foreach t \$targets { if {[string first \$want \$t] >= 0} { lappend hits \$t } }
  if {[llength \$hits] != 1} {
    error \"NIA_TARGET '\$want' matched [llength \$hits] of [llength \$targets] targets: \$hits\"
  }
  set chosen [lindex \$hits 0]
} elseif {[llength \$targets] > 1} {
  puts \"NIA_TARGET_WARN: [llength \$targets] targets attached and no NIA_TARGET given; using the first\"
}
puts \"NIA_TARGET_USED: \$chosen\"
current_hw_target \$chosen
open_hw_target
set dev [get_hw_devices $DEVICE]
current_hw_device \$dev
refresh_hw_device -update_hw_probes false \$dev
set_property PROGRAM.FILE {$REMOTE_PDI} \$dev
program_hw_devices \$dev
if {[catch {refresh_hw_device -update_hw_probes false \$dev} msg]} { puts \"NIA_PROG_REFRESH_WARN: \$msg\" }
close_hw_target
disconnect_hw_server
puts \"NIA_PROG_TCL_OK\"
EOT"

  run "${SRC}export TERM=xterm && \
      cd $REMOTE_WORK && (pgrep -x hw_server >/dev/null || (setsid nohup hw_server >hw_server.log 2>&1 & sleep 3)) && \
      timeout 900 $VIVADO_BIN -mode batch -nojournal -log $REMOTE_WORK/program.log -notrace \
      -source $REMOTE_WORK/program.tcl > $REMOTE_WORK/program.stdout 2>&1; echo \"VIVADO_RC=\$?\"" \
      2>&1 | grep -v Warning | tail -2

  banner "VERIFY from the log, not from the exit status"
  run "L=$REMOTE_WORK/program.log; \
      echo -n 'target used            : '; grep -m1 'NIA_TARGET_USED' \$L 2>/dev/null | cut -d' ' -f2-; \
      echo -n 'programmed (27-3439)   : '; grep -c '27-3439' \$L 2>/dev/null; \
      echo -n 'DONE bit HIGH          : '; grep -ci 'DONE bit *: *HIGH' \$L 2>/dev/null; \
      echo -n 'script marker          : '; grep -c 'NIA_PROG_TCL_OK' \$L 2>/dev/null; \
      echo -n 'errors in the log      : '; grep -c '^ERROR' \$L 2>/dev/null; \
      echo '--- tail ---'; tail -6 \$L 2>/dev/null | cut -c1-120"
  echo
  echo "NEXT: this is a new endpoint, so the host must reboot rather than rescan."
  echo "  Memory windows and interrupt vectors are assigned at power-on; a rescan"
  echo "  leaves a window unassigned. After the reboot: ./check_pcie.sh all"
}

case "${1:-}" in
  check)   precheck ;;
  program) program ;;
  *) sed -n '14,36p' "$0"; exit 2 ;;
esac
