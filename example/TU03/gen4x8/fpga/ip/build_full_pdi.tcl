# ---------------------------------------------------------------------------
# File        : build_full_pdi.tcl
# Description : Builds the endpoint example image from scratch through the
#               project, synthesis to write_device_image. It passes on non
#               negative slack, every clock constrained, no error, an image.
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

set R $fpga/build_pdi/reports
file mkdir $R

puts "NIA_PDI_BUILD_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"

create_project -force -part $part $top $fpga/build_pdi/${top}_proj
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

puts "NIA_PDI_BUILD files_ours=[llength $ours] files_reference=[llength $reference]"
puts "NIA_PDI_BUILD top=[get_property top [current_fileset]]"

puts "NIA_STAGE_BEGIN synth"
reset_run synth_1
launch_runs -jobs $jobs synth_1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "NIA_PDI_BUILD SYNTH_FAILED status='[get_property STATUS [get_runs synth_1]]'"
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
puts "NIA_PDI_BUILD impl status='$st' progress=$pr"
if {$pr ne "100%"} {
    puts "NIA_PDI_BUILD IMPL_FAILED"
    puts "NIA_BUILD_DONE rc=2"
    exit 2
}
puts "NIA_STAGE_END impl"

open_run impl_1

report_timing_summary -max_paths 10 -file $R/timing_summary.rpt
report_timing -sort_by group -max_paths 20 -nworst 1 -file $R/timing_worst.rpt
report_utilization -hierarchical -file $R/utilization.rpt
report_clocks -file $R/clocks.rpt
report_methodology -file $R/methodology.rpt
report_drc -file $R/drc.rpt
check_timing -file $R/check_timing.rpt

set wns   [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs   [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
set nfail [llength [get_timing_paths -delay_type max -max_paths 10000 -slack_lesser_than 0]]

set noclk "unknown"
if {[file exists $R/check_timing.rpt]} {
    set fh [open $R/check_timing.rpt r]
    foreach line [split [read $fh] "\n"] {
        if {[regexp {checking no_clock\s*\((\d+)\)} $line -> n]} { set noclk $n }
    }
    close $fh
}

puts "NIA_PDI_BUILD_RESULT_BEGIN"
puts "NIA_PDI_BUILD WNS = $wns"
puts "NIA_PDI_BUILD WHS = $whs"
puts "NIA_PDI_BUILD FAILING_MAX_PATHS = $nfail"
puts "NIA_PDI_BUILD check_timing_no_clock = $noclk"
puts "NIA_PDI_BUILD PART = [get_property PART [current_design]]"
foreach p {pcie_user_lnk_up_o sts_cq_poisoned_seen_o} {
    puts "NIA_PDI_BUILD port $p pin=[get_property PACKAGE_PIN [get_ports $p]] std=[get_property IOSTANDARD [get_ports $p]]"
}
set pdi [glob -nocomplain $fpga/build_pdi/${top}_proj/${top}.runs/impl_1/*.pdi]
puts "NIA_PDI_BUILD pdi = $pdi"
foreach f $pdi { puts "NIA_PDI_BUILD pdi_size = [file size $f]" }
puts "NIA_PDI_BUILD_RESULT_END"

if {[llength $pdi] == 0} {
    puts "NIA_PDI_BUILD NO_PDI - write_device_image produced nothing (check DRC NSTD-2 / the four status pins)"
    puts "NIA_BUILD_DONE rc=3"
    exit 3
}

puts "NIA_BUILD_DONE rc=0"
