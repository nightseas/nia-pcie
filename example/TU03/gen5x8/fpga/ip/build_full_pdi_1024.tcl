# ---------------------------------------------------------------------------
# File        : build_full_pdi_1024.tcl
# Description : Builds the Gen5 x8, 1024-bit AXIS, device image, from the block design and
#               synthesis through implementation to the PDI.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Tcl
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
set comm [file normalize $app/example/rtl]

set BUILD  [file normalize $fpga/build_pdi_1024]
set R      $BUILD/reports
set IPSET  $BUILD/ip_set
set IPWORK $BUILD/ip
set IPREQ  $IPSET/nia_ip_request.txt
set IPBAR  $IPSET/nia_barmap.txt
set IPLOCK $BUILD/ip_set.lock

file mkdir $BUILD
file mkdir $R

proc nia_env { name def } {
    if {[info exists ::env($name)] && [string length $::env($name)] > 0} {
        return $::env($name)
    }
    return $def
}

proc nia_read_file { path } {
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    return $txt
}

proc nia_write_file { path txt } {
    file mkdir [file dirname $path]
    set fh [open $path w]
    puts -nonewline $fh $txt
    close $fh
}

proc nia_fnv1a64 { data } {
    set h 14695981039346656037
    binary scan $data cu* bytes
    foreach b $bytes {
        set h [expr {($h ^ $b) & 0xFFFFFFFFFFFFFFFF}]
        set h [expr {($h * 1099511628211) & 0xFFFFFFFFFFFFFFFF}]
    }
    set s [format %x $h]
    while {[string length $s] < 16} { set s "0$s" }
    return $s
}

proc nia_digest_bytes { data } {
    return "fnv1a64:[nia_fnv1a64 $data]"
}

proc nia_digest_file { path } {
    if {![file exists $path]} { return "absent" }
    set sha [auto_execok sha256sum]
    if {$sha ne ""} {
        if {![catch {set out [exec {*}$sha $path]} err]} {
            return "sha256:[lindex $out 0]"
        }
    }
    set fh [open $path r]
    fconfigure $fh -translation binary -encoding binary
    set data [read $fh]
    close $fh
    return [nia_digest_bytes $data]
}

proc nia_find { root pattern } {
    set out {}
    foreach f [glob -nocomplain -directory $root *] {
        if {[file isdirectory $f]} {
            foreach g [nia_find $f $pattern] { lappend out $g }
        } elseif {[string match $pattern [file tail $f]]} {
            lappend out $f
        }
    }
    return $out
}

proc nia_lock_acquire { lock timeout } {
    set waited 0
    while {1} {
        if {![catch {set fh [open $lock {WRONLY CREAT EXCL}]}]} {
            puts $fh [pid]
            close $fh
            return 1
        }
        if {$waited >= $timeout} { return 0 }
        after 2000
        incr waited 2
    }
}

proc nia_lock_release { lock } {
    file delete -force $lock
}

proc nia_set_directive { run prop want } {
    if {$want eq ""} { return }
    if {[catch {set_property $prop $want [get_runs $run]} err]} {
        puts "NIA_DIRECTIVE $prop requested='$want' REFUSED '$err'"
    }
}

proc nia_report_directive { run prop want } {
    set have "<unreadable>"
    catch {set have [get_property $prop [get_runs $run]]}
    if {$want eq ""} {
        puts "NIA_DIRECTIVE $prop requested=<unset> readback='$have'"
        return 0
    }
    if {[string equal $have $want]} {
        puts "NIA_DIRECTIVE $prop requested='$want' readback='$have' OK"
        return 0
    }
    puts "NIA_DIRECTIVE $prop requested='$want' readback='$have' DEMOTED"
    return 1
}

puts "NIA_PDI_BUILD_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"
puts "NIA_PDI_BUILD part=$part top=$top"
puts "NIA_PDI_BUILD design=gen5x8"

set ::nia_cips_define_only 1
source $here/cips_cpm5_pcie_g5x8.tcl
unset ::nia_cips_define_only

set bdname  [nia_cips_bd_name]
set request [nia_cips_request $part]

set ours [list \
    $fpga/rtl/fpga.v \
    $fpga/rtl/fpga_core.v \
]

set shim [list \
    $comm/example_core_pcie_versal.v \
    $comm/example_core_pcie_split_width.v \
    $app/rtl/gen5x8/pcie_versal_if.sv \
    $app/rtl/gen5x8/pcie_versal_if_rq.sv \
    $app/rtl/gen5x8/pcie_versal_if_rc.sv \
    $app/rtl/gen5x8/pcie_versal_if_cqcc_gearbox.sv \
]

set reference [list \
    $lib/example/common/rtl/example_core.v \
    $lib/example/common/rtl/axi_ram.v \
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

set sources [concat $ours $shim $reference]

set missing 0
foreach f $sources {
    if {![file exists $f]} { puts "NIA_PDI_BUILD MISSING_SOURCE $f"; incr missing }
}
if {![file exists $fpga/fpga.xdc]} { puts "NIA_PDI_BUILD MISSING_SOURCE $fpga/fpga.xdc"; incr missing }
if {$missing != 0} {
    puts "NIA_PDI_BUILD rc=1 reason=missing_sources n=$missing"
    puts "NIA_BUILD_DONE rc=1"
    exit 1
}

puts "NIA_IPSET_BEGIN"
puts "NIA_IPSET request_digest = [nia_digest_bytes $request]"
puts "NIA_IPSET set_dir = $IPSET"

set have ""
if {[file exists $IPREQ]} { set have [nia_read_file $IPREQ] }
set bdfiles [nia_find $IPSET ${bdname}.bd]
set fresh [expr {[string equal $have $request] && [llength $bdfiles] > 0 && [file exists $IPBAR]}]

if {$fresh} {
    puts "NIA_IPSET reuse = yes reason=request_matches"
    puts [string trim [nia_read_file $IPBAR]]
} else {
    if {$have eq ""} {
        puts "NIA_IPSET reuse = no reason=no_request_beside_artefact"
    } elseif {![string equal $have $request]} {
        puts "NIA_IPSET reuse = no reason=request_differs"
    } elseif {![file exists $IPBAR]} {
        puts "NIA_IPSET reuse = no reason=no_barmap_receipt_beside_artefact"
    } else {
        puts "NIA_IPSET reuse = no reason=artefact_absent"
    }
    if {![nia_lock_acquire $IPLOCK 1800]} {
        puts "NIA_IPSET LOCK_TIMEOUT $IPLOCK"
        puts "NIA_BUILD_DONE rc=1"
        exit 1
    }
    set gen_rc 0
    set gen_err ""
    set ::nia_barmap_bad ""
    if {[catch {
        file delete -force $IPSET
        file mkdir $IPSET
        create_project -force -part $part ip_proj $IPSET/ip_proj
        set_property target_language Verilog [current_project]
        source $here/cips_cpm5_pcie_g5x8.tcl
        generate_target all [get_files ${bdname}.bd]
        close_project
        nia_write_file $IPREQ $request
    } gen_err]} {
        set gen_rc 1
    }
    if {$gen_rc == 0} {
        if {$::nia_barmap_bad eq ""} {
            puts "NIA_IPSET GENERATE_FAILED 'the CPM_CONFIG readback did not run'"
            nia_lock_release $IPLOCK
            puts "NIA_BUILD_DONE rc=1"
            exit 1
        }
        nia_write_file $IPBAR "NIA_BARMAP_END bad=$::nia_barmap_bad\n"
    }
    nia_lock_release $IPLOCK
    if {$gen_rc != 0} {
        puts "NIA_IPSET GENERATE_FAILED '$gen_err'"
        puts "NIA_BUILD_DONE rc=1"
        exit 1
    }
    set bdfiles [nia_find $IPSET ${bdname}.bd]
    puts "NIA_IPSET generated = yes"
}

file delete -force $IPWORK
file copy -force $IPSET $IPWORK
set bdcopy [nia_find $IPWORK ${bdname}.bd]
set wrcopy [nia_find $IPWORK ${bdname}_wrapper.v]
if {[llength $wrcopy] == 0} { set wrcopy [nia_find $IPWORK ${bdname}_wrapper.sv] }
puts "NIA_IPSET work_dir = $IPWORK"
puts "NIA_IPSET bd = $bdcopy"
puts "NIA_IPSET wrapper = $wrcopy"
if {[llength $bdcopy] == 0 || [llength $wrcopy] == 0} {
    puts "NIA_IPSET COPY_INCOMPLETE"
    puts "NIA_BUILD_DONE rc=1"
    exit 1
}
puts "NIA_IPSET_END"

create_project -force -part $part $top $BUILD/${top}_proj
set_property target_language Verilog [current_project]

add_files -fileset sources_1 $sources
add_files -fileset sources_1 -norecurse [lindex $bdcopy 0]
add_files -fileset sources_1 -norecurse [lindex $wrcopy 0]
add_files -fileset constrs_1 $fpga/fpga.xdc

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

puts "NIA_PDI_BUILD files_ours=[llength $ours] files_shim=[llength $shim] files_reference=[llength $reference]"
puts "NIA_PDI_BUILD top=[get_property top [current_fileset]]"

nia_cips_width_probe

set d_opt       [nia_env NIA_OPT_DIRECTIVE ""]
set d_place     [nia_env NIA_PLACE_DIRECTIVE ""]
set d_phys      [nia_env NIA_PHYS_OPT_DIRECTIVE AggressiveExplore]
set d_route     [nia_env NIA_ROUTE_DIRECTIVE HigherDelayCost]
set d_postphys  [nia_env NIA_POST_ROUTE_PHYS_OPT_DIRECTIVE ""]
set en_phys     [nia_env NIA_PHYS_OPT 1]
set en_postphys [nia_env NIA_POST_ROUTE_PHYS 1]

puts "NIA_DIRECTIVE_BEGIN"
catch {set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED $en_phys [get_runs impl_1]}
catch {set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $en_postphys [get_runs impl_1]}
nia_set_directive impl_1 STEPS.OPT_DESIGN.ARGS.DIRECTIVE $d_opt
nia_set_directive impl_1 STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $d_place
nia_set_directive impl_1 STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $d_phys
nia_set_directive impl_1 STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $d_route
nia_set_directive impl_1 STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $d_postphys

set demoted 0
incr demoted [nia_report_directive impl_1 STEPS.OPT_DESIGN.ARGS.DIRECTIVE $d_opt]
incr demoted [nia_report_directive impl_1 STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $d_place]
incr demoted [nia_report_directive impl_1 STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $d_phys]
incr demoted [nia_report_directive impl_1 STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $d_route]
incr demoted [nia_report_directive impl_1 STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE $d_postphys]
incr demoted [nia_report_directive impl_1 STEPS.PHYS_OPT_DESIGN.IS_ENABLED $en_phys]
incr demoted [nia_report_directive impl_1 STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED $en_postphys]
puts "NIA_DIRECTIVE_END demoted=$demoted"

puts "NIA_STAGE_BEGIN synth"
reset_run synth_1
launch_runs -jobs $jobs synth_1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "NIA_PDI_BUILD SYNTH_FAILED status='[get_property STATUS [get_runs synth_1]]'"
    puts "NIA_BUILD_DONE rc=2"
    exit 2
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
    puts "NIA_BUILD_DONE rc=3"
    exit 3
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

set p [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
puts "NIA_PDI_BUILD WORST_LOGIC_LEVELS = [get_property LOGIC_LEVELS $p]"
puts "NIA_PDI_BUILD WORST_SRC = [get_property STARTPOINT_PIN $p]"
puts "NIA_PDI_BUILD WORST_DST = [get_property ENDPOINT_PIN $p]"

foreach pin {gpio_lnk_up_o gpio_poison_seen_o gpio_gearbox_err_o gpio_uncor_err_o} {
    puts "NIA_PDI_BUILD port $pin pin=[get_property PACKAGE_PIN [get_ports $pin]] std=[get_property IOSTANDARD [get_ports $pin]]"
}

set pdi [glob -nocomplain $BUILD/${top}_proj/${top}.runs/impl_1/*.pdi]
set kept {}
foreach f $pdi {
    file copy -force $f $BUILD/[file tail $f]
    lappend kept $BUILD/[file tail $f]
    puts "NIA_PDI_BUILD pdi = $BUILD/[file tail $f]"
    puts "NIA_PDI_BUILD pdi_size = [file size $f]"
}
puts "NIA_PDI_BUILD_RESULT_END"

set digest_path $BUILD/${top}_rtl_digest.txt
set lines {}
lappend lines "design gen5x8"
lappend lines "part $part"
lappend lines "top $top"
lappend lines "ip_request [nia_digest_bytes $request]"
foreach f [concat $sources [list $fpga/fpga.xdc]] {
    lappend lines "source [nia_digest_file $f] $f"
}
foreach f $kept {
    lappend lines "image [nia_digest_file $f] $f"
}
set body [join $lines "\n"]
set combined [nia_digest_bytes $body]
nia_write_file $digest_path "$body\ncombined $combined\n"

puts "NIA_RTL_DIGEST_BEGIN"
foreach l $lines { puts "NIA_RTL_DIGEST $l" }
puts "NIA_RTL_DIGEST combined $combined"
puts "NIA_RTL_DIGEST_END files=[llength $sources] path=$digest_path"

if {[llength $pdi] == 0} {
    puts "NIA_PDI_BUILD NO_PDI - write_device_image produced nothing"
    puts "NIA_BUILD_DONE rc=4"
    exit 4
}

puts "NIA_BUILD_DONE rc=0"
