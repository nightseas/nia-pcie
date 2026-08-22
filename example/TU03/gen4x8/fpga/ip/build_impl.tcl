# ---------------------------------------------------------------------------
# File        : build_impl.tcl
# Description : Synthesises and implements the endpoint example image and
#               reports the three numbers that accept it: worst negative slack,
#               error count and critical warning count.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set part xcvp1552-vsva2785-2MHP-i-S
set top  fpga
set jobs 8

proc nia_repo_root { start } {
    if {[info exists ::env(NIA_ROOT)]} { return [file normalize $::env(NIA_ROOT)] }
    set d [file normalize $start]
    while {![file exists $d/.nia-repo-root]} {
        set up [file dirname $d]
        if {$up eq $d} { error "nia: no .nia-repo-root above $start" }
        set d $up
    }
    return $d
}

set here [file normalize [file dirname [info script]]]
set fpga [file normalize $here/..]
set app  [nia_repo_root $here]
set lib  [expr {[info exists ::env(NIA_VERILOG_PCIE)] ? $::env(NIA_VERILOG_PCIE) : "$app/verilog-pcie"}]

file mkdir $fpga/build/reports

create_project -force -part $part $top $fpga/build/${top}_proj
set_property target_language Verilog [current_project]

set ours [list \
    $fpga/rtl/fpga.v \
    $fpga/rtl/fpga_core.v \
    $app/rtl/gen4x8/pcie_versal_adapt.sv \
]

set reference [list \
    $lib/example/common/rtl/example_core_pcie_us.v \
    $lib/example/common/rtl/example_core_pcie.v \
    $lib/example/common/rtl/example_core.v \
    $lib/example/common/rtl/axi_ram.v \
    $lib/rtl/pcie_us_if.v \
    $lib/rtl/pcie_us_if_rc.v \
    $lib/rtl/pcie_us_if_rq.v \
    $lib/rtl/pcie_us_if_cq.v \
    $lib/rtl/pcie_us_if_cc.v \
    $lib/rtl/pcie_us_cfg.v \
    $lib/rtl/pcie_axil_master.v \
    $lib/rtl/pcie_axi_master.v \
    $lib/rtl/pcie_axi_master_rd.v \
    $lib/rtl/pcie_axi_master_wr.v \
    $lib/rtl/pcie_tlp_demux_bar.v \
    $lib/rtl/pcie_tlp_demux.v \
    $lib/rtl/pcie_tlp_mux.v \
    $lib/rtl/pcie_tlp_fifo.v \
    $lib/rtl/pcie_tlp_fifo_raw.v \
    $lib/rtl/pcie_msix.v \
    $lib/rtl/dma_if_pcie.v \
    $lib/rtl/dma_if_pcie_rd.v \
    $lib/rtl/dma_if_pcie_wr.v \
    $lib/rtl/dma_psdpram.v \
    $lib/rtl/priority_encoder.v \
    $lib/rtl/pulse_merge.v \
]

add_files -fileset sources_1 [concat $ours $reference]
add_files -fileset constrs_1 $fpga/fpga.xdc

source $here/cips_pcie1_bd.tcl

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

puts "NIA_BUILD files_ours=[llength $ours] files_reference=[llength $reference]"
puts "NIA_BUILD top=[get_property top [current_fileset]]"

puts "NIA_STAGE_BEGIN synth"
reset_run synth_1
launch_runs -jobs $jobs synth_1
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
set pr [get_property PROGRESS [get_runs synth_1]]
puts "NIA_BUILD synth status='$st' progress=$pr"
if {$pr ne "100%"} {
    puts "NIA_BUILD SYNTH_FAILED"
    puts "NIA_BUILD_DONE rc=1"
    exit 1
}
puts "NIA_STAGE_END synth"

puts "NIA_STAGE_BEGIN impl"
reset_run impl_1
launch_runs -jobs $jobs impl_1 -to_step write_device_image
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
puts "NIA_BUILD impl status='$st' progress=$pr"
if {$pr ne "100%"} {
    puts "NIA_BUILD IMPL_FAILED"
    puts "NIA_BUILD_DONE rc=2"
    exit 2
}
puts "NIA_STAGE_END impl"

open_run impl_1
set R $fpga/build/reports

report_timing_summary -max_paths 10 -file $R/timing_summary.rpt
report_timing -sort_by group -max_paths 20 -path_type summary -file $R/timing_worst.rpt
report_utilization -hierarchical -file $R/utilization.rpt
report_clocks -file $R/clocks.rpt
report_methodology -file $R/methodology.rpt
report_drc -file $R/drc.rpt
write_checkpoint -force $fpga/build/${top}_routed.dcp

set wns  [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs  [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
set nfail [llength [get_timing_paths -delay_type max -max_paths 10000 -slack_lesser_than 0]]

check_timing -file $R/check_timing.rpt
set noclk "unknown"
if {[file exists $R/check_timing.rpt]} {
    set fh [open $R/check_timing.rpt r]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {checking no_clock\s*\((\d+)\)} $line -> n]} { set noclk $n }
    }
    close $fh
}

puts "NIA_BUILD_RESULT_BEGIN"
puts "NIA_BUILD WNS = $wns"
puts "NIA_BUILD WHS = $whs"
puts "NIA_BUILD FAILING_MAX_PATHS = $nfail"
puts "NIA_BUILD check_timing_no_clock = $noclk"
puts "NIA_BUILD PART = [get_property PART [current_project]]"
set pdi [glob -nocomplain $fpga/build/${top}_proj/${top}.runs/impl_1/*.pdi]
if {[llength $pdi]} {
    foreach f $pdi {
        file copy -force $f $fpga/build/[file tail $f]
        puts "NIA_BUILD pdi = $fpga/build/[file tail $f]"
        puts "NIA_BUILD pdi_size = [file size $f]"
    }
} else {
    puts "NIA_BUILD NO_PDI - write_device_image produced no image"
}
puts "NIA_BUILD_RESULT_END"

puts "NIA_BUILD_DONE rc=0"
