# ---------------------------------------------------------------------------
# File        : rerun_impl_pdi.tcl
# Description : Re-runs implementation inside an existing project with the pin
#               constraints already updated on disk, through to
#               write_device_image, and confirms which constraint files are read.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set xpr  [lindex $argv 0]
set jobs [lindex $argv 1]
if {$jobs eq ""} { set jobs 8 }

puts "NIA_REIMPL_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"
open_project $xpr

puts "NIA_REIMPL constrs: [get_files -of_objects [get_filesets constrs_1]]"
foreach f [get_files -of_objects [get_filesets constrs_1]] {
    puts "NIA_REIMPL   xdc '$f' mtime=[clock format [file mtime $f] -format %H:%M:%S]"
}

reset_run impl_1
launch_runs -jobs $jobs impl_1 -to_step write_device_image
wait_on_run impl_1

set st [get_property STATUS   [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
puts "NIA_REIMPL impl status='$st' progress=$pr"

if {$pr ne "100%"} {
    puts "NIA_REIMPL IMPL_FAILED"
    puts "NIA_REIMPL_END rc=1"
    return
}

open_run impl_1
set R [file dirname $xpr]/../reports_r6b
file mkdir $R
report_timing_summary -file $R/timing_summary.rpt
report_timing -sort_by group -max_paths 20 -nworst 1 -file $R/timing_worst.rpt
report_utilization -hierarchical -file $R/utilization.rpt
report_drc -file $R/drc.rpt
report_methodology -file $R/methodology.rpt
check_timing -file $R/check_timing.rpt

set ts [get_timing_paths -max_paths 1 -nworst 1 -setup]
set th [get_timing_paths -max_paths 1 -nworst 1 -hold]
puts "NIA_REIMPL_RESULT_BEGIN"
puts "NIA_REIMPL WNS = [get_property SLACK $ts]"
puts "NIA_REIMPL WHS = [get_property SLACK $th]"
puts "NIA_REIMPL PART = [get_property PART [current_design]]"
foreach p {pcie_user_lnk_up_o sts_cq_poisoned_seen_o} {
    puts "NIA_REIMPL port $p pin=[get_property PACKAGE_PIN [get_ports $p]] std=[get_property IOSTANDARD [get_ports $p]]"
}
puts "NIA_REIMPL_RESULT_END"

set pdi [glob -nocomplain [file dirname $xpr]/*.runs/impl_1/*.pdi]
puts "NIA_REIMPL pdi = $pdi"
foreach f $pdi { puts "NIA_REIMPL pdi_size = [file size $f]" }
puts "NIA_REIMPL_END rc=0"
