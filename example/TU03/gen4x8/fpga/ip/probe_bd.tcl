# ---------------------------------------------------------------------------
# File        : probe_bd.tcl
# Description : Builds the CIPS block design and reports the interface widths it
#               presents to the fabric, so a width the adapter depends on is
#               measured rather than read from a table.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set part xcvp1552-vsva2785-2MHP-i-S

create_project -force -part $part probe ./probe_proj
set_property target_language Verilog [current_project]

source cips_pcie1_bd.tcl

puts "NIA_PROBE_BEGIN"

set wrap [get_files -quiet cips_pcie1_wrapper.v]
if {$wrap eq ""} { set wrap [get_files -quiet cips_pcie1_wrapper.sv] }
puts "NIA_WRAPPER_FILE = $wrap"
if {$wrap ne ""} {
    set fh [open [lindex $wrap 0] r]
    set txt [read $fh]
    close $fh
    puts "NIA_WRAPPER_BEGIN"
    puts $txt
    puts "NIA_WRAPPER_END"
}

puts "NIA_BDPORTS_BEGIN"
foreach p [get_bd_intf_ports] {
    puts "INTF $p vlnv=[get_property VLNV $p] mode=[get_property MODE $p]"
    foreach sub [get_bd_ports -quiet -of_objects $p] {
        puts "    sub $sub"
    }
}
foreach p [get_bd_ports] {
    puts "PORT $p dir=[get_property DIR $p] left=[get_property LEFT $p] right=[get_property RIGHT $p]"
}
puts "NIA_BDPORTS_END"

puts "NIA_CIPSPINS_BEGIN"
foreach pin [get_bd_pins -quiet versal_cips_0/*] {
    set l [get_property -quiet LEFT $pin]
    set r [get_property -quiet RIGHT $pin]
    puts "PIN [get_property NAME $pin] dir=[get_property DIR $pin] left=$l right=$r"
}
puts "NIA_CIPSPINS_END"

puts "NIA_PARITY_BEGIN"
set cfg [get_property CONFIG.CPM_CONFIG [get_bd_cells versal_cips_0]]
foreach k $cfg { if {[string match -nocase "*PARITY*" $k] || [string match -nocase "*MSI_X*" $k]} { puts "CPMCFG_TOKEN $k" } }
foreach pn {CPM_PCIE1_EN_PARITY CPM_PCIE1_AXISTEN_IF_TX_PARITY_EN CPM_PCIE1_AXISTEN_IF_RX_PARITY_EN \
            CPM_PCIE1_MSI_X_OPTIONS CPM_PCIE1_MODES CPM_PCIE1_MAX_LINK_SPEED} {
    if {[catch {set v [get_property -quiet CONFIG.$pn [get_bd_cells versal_cips_0]]} e]} {
        puts "PROP $pn = <not a direct property: $e>"
    } else {
        puts "PROP $pn = $v"
    }
}
puts "NIA_PARITY_END"

puts "NIA_PROBE_END rc=0"
