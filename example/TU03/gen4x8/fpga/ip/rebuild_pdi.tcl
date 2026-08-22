# ---------------------------------------------------------------------------
# File        : rebuild_pdi.tcl
# Description : Re-places and routes from a post synthesis checkpoint with the
#               pin constraints applied, then writes the device image. It runs
#               from the checkpoint so synthesis is not repeated.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set synth_dcp [lindex $argv 0]
set xdc       [lindex $argv 1]
set outdir    [lindex $argv 2]

file mkdir $outdir/reports
puts "NIA_REBUILD_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"
puts "NIA_REBUILD synth_dcp = $synth_dcp"
puts "NIA_REBUILD xdc       = $xdc"

open_checkpoint $synth_dcp
read_xdc $xdc

set undef {}
foreach p [get_ports -quiet *] {
    if {[llength [get_package_pins -quiet -of_objects $p]] == 0} { continue }
    if {[string match -nocase "*pcie_rx*" $p] || [string match -nocase "*pcie_tx*" $p] \
        || [string match -nocase "*gt_refclk*" $p]} { continue }
    set std [get_property IOSTANDARD $p]
    set pin [get_property PACKAGE_PIN $p]
    puts "NIA_REBUILD port '$p' PACKAGE_PIN='$pin' IOSTANDARD='$std'"
    if {$std eq "" || [string match -nocase "*UNDEFINED*" $std]} { lappend undef $p }
}
if {[llength $undef] > 0} {
    puts "NIA_REBUILD ABORT: still unconstrained: $undef"
    puts "NIA_REBUILD_END rc=2"
    return
}
puts "NIA_REBUILD all non-GT ports constrained - proceeding"

opt_design
place_design
phys_opt_design
route_design

set R $outdir/reports
report_timing_summary -file $R/timing_summary.rpt
report_timing -sort_by group -max_paths 20 -nworst 1 -file $R/timing_worst.rpt
report_utilization -hierarchical -file $R/utilization.rpt
report_drc -file $R/drc.rpt
report_methodology -file $R/methodology.rpt
check_timing -file $R/check_timing.rpt

write_checkpoint -force $outdir/fpga_routed.dcp

set ts [get_timing_paths -max_paths 1 -nworst 1 -setup]
set th [get_timing_paths -max_paths 1 -nworst 1 -hold]
puts "NIA_REBUILD_RESULT_BEGIN"
puts "NIA_REBUILD WNS = [get_property SLACK $ts]"
puts "NIA_REBUILD WHS = [get_property SLACK $th]"
puts "NIA_REBUILD PART = [get_property PART [current_design]]"
puts "NIA_REBUILD_RESULT_END"

write_device_image -force $outdir/fpga.pdi
puts "NIA_REBUILD pdi_written = [file exists $outdir/fpga.pdi]"
if {[file exists $outdir/fpga.pdi]} {
    puts "NIA_REBUILD pdi_size = [file size $outdir/fpga.pdi]"
}
puts "NIA_REBUILD_END rc=0"
