# ---------------------------------------------------------------------------
# File        : write_pdi.tcl
# Description : Writes a device image from a routed checkpoint, as a step of its
#               own, so an image can be produced on a licensed machine from a
#               checkpoint routed anywhere.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set dcp [lindex $argv 0]
set pdi [lindex $argv 1]

puts "NIA_PDI_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"
puts "NIA_PDI dcp = $dcp"
puts "NIA_PDI pdi = $pdi"

open_checkpoint $dcp

set ts [get_timing_paths -max_paths 1 -nworst 1 -setup]
if {[llength $ts]} {
    puts "NIA_PDI WNS_from_dcp = [get_property SLACK $ts]"
}
puts "NIA_PDI PART = [get_property PART [current_design]]"

set assigns [lrange $argv 2 end]

set undef {}
foreach p [get_ports -quiet *] {
    if {[get_property PACKAGE_PIN $p] eq ""} {
        lappend undef $p
    }
}
puts "NIA_PDI unpinned_ports = $undef"
foreach p $undef {
    puts "NIA_PDI   need: port='$p' current_PACKAGE_PIN='[get_property PACKAGE_PIN $p]' current_IOSTANDARD='[get_property IOSTANDARD $p]' direction='[get_property DIRECTION $p]'"
}

if {[llength $undef] > 0 && [llength $assigns] == 0} {
    puts "NIA_PDI DECISION_REQUIRED: [llength $undef] port(s) need a package pin from the owner."
    puts "NIA_PDI No PDI written. Re-run with assignments, or drop these ports from the image top level."
    puts "NIA_PDI_END rc=2"
    return
}
if {[llength $undef] == 0} {
    puts "NIA_PDI every port carries a package pin; nothing to assign"
}

foreach a $assigns {
    set kv   [split $a "="]
    set port [lindex $kv 0]
    set ps   [split [lindex $kv 1] ":"]
    set pin  [lindex $ps 0]
    set std  [lindex $ps 1]
    puts "NIA_PDI applying: $port -> PACKAGE_PIN $pin IOSTANDARD $std"
    set_property PACKAGE_PIN $pin [get_ports $port]
    set_property IOSTANDARD  $std [get_ports $port]
}

write_device_image -force $pdi
puts "NIA_PDI written = [file exists $pdi]"
if {[file exists $pdi]} {
    puts "NIA_PDI size = [file size $pdi]"
}
puts "NIA_PDI_END rc=0"
