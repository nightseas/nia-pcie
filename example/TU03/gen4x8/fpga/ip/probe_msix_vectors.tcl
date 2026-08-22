# ---------------------------------------------------------------------------
# File        : probe_msix_vectors.tcl
# Description : Reports how many MSI-X vectors CPM5 grants per function, by
#               building the block design once per requested count and reading
#               the value back, because a request above the limit is ignored.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set part xcvp1552-vsva2785-2MHP-i-S

set variants [list \
    [list a_base_silicon   {}] \
    [list b_vec64_only     {CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION {64}}] \
    [list c_vec64_tbl3F    {CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION {64} CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {03F}}] \
    [list d_vec32_tbl1F    {CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION {32} CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {01F}}] \
    [list e_vec16_tbl0F    {CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION {16} CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {00F}}] \
    [list f_tbl3F_only     {CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {03F}}] \
    [list g_illegal_vec17  {CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION {17}}] \
    [list h_illegal_tblZZZ {CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {ZZZ}}] \
]

set base {
      CPM_PCIE0_MODES {None}
      CPM_PCIE1_MODES {PCIE}
      CPM_PCIE1_MODE_SELECTION {Advanced}
      CPM_PCIE1_MAX_LINK_SPEED {16.0_GT/s}
      CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH {X8}
      CPM_PCIE1_REF_CLK_FREQ {100_MHz}
      CPM_PCIE1_AXISTEN_IF_ENABLE_CLIENT_TAG {1}
      CPM_PCIE1_CFG_CTL_IF {1}
      CPM_PCIE1_CFG_FC_IF {1}
      CPM_PCIE1_CFG_MGMT_IF {1}
      CPM_PCIE1_CFG_STS_IF {1}
      CPM_PCIE1_MESG_RSVD_IF {1}
      CPM_PCIE1_MESG_TRANSMIT_IF {1}
      CPM_PCIE1_TX_FC_IF {1}
      CPM_PCIE1_PF0_DEV_CAP_EXT_TAG_EN {1}
      CPM_PCIE1_EN_PARITY {0}
      CPM_PCIE1_AXISTEN_IF_TX_PARITY_EN {0}
      CPM_PCIE1_AXISTEN_IF_EXT_512_RQ_STRADDLE {1}
      CPM_PCIE1_AXISTEN_IF_EXT_512_RC_STRADDLE {1}
      CPM_PCIE1_AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE {1}
      CPM_PCIE1_AXISTEN_IF_EXT_512_CQ_STRADDLE {1}
      CPM_PCIE1_AXISTEN_IF_EXT_512_CC_STRADDLE {1}
      CPM_PCIE1_RQ_STRADDLE_SIZE {2_TLP}
      CPM_PCIE1_CQ_STRADDLE_SIZE {2_TLP}
      CPM_PCIE1_CC_STRADDLE_SIZE {2_TLP}
      CPM_PCIE1_RC_STRADDLE_SIZE {4_TLP}
      CPM_PCIE1_PF0_BAR0_ENABLED {1}
      CPM_PCIE1_PF0_BAR0_TYPE {Memory}
      CPM_PCIE1_PF0_BAR0_SIZE {16}
      CPM_PCIE1_PF0_BAR0_SCALE {Megabytes}
      CPM_PCIE1_PF0_BAR0_64BIT {1}
      CPM_PCIE1_PF0_BAR0_PREFETCHABLE {1}
      CPM_PCIE1_PF0_BAR2_ENABLED {1}
      CPM_PCIE1_PF0_BAR2_TYPE {Memory}
      CPM_PCIE1_PF0_BAR2_SIZE {16}
      CPM_PCIE1_PF0_BAR2_SCALE {Megabytes}
      CPM_PCIE1_PF0_BAR2_64BIT {1}
      CPM_PCIE1_PF0_BAR2_PREFETCHABLE {1}
      CPM_PCIE1_PF0_BAR4_ENABLED {1}
      CPM_PCIE1_PF0_BAR4_TYPE {Memory}
      CPM_PCIE1_PF0_BAR4_SIZE {64}
      CPM_PCIE1_PF0_BAR4_SCALE {Kilobytes}
      CPM_PCIE1_PF0_BAR4_64BIT {1}
      CPM_PCIE1_PF0_BAR4_PREFETCHABLE {1}
      CPM_PCIE1_MSI_X_OPTIONS {MSI-X_Internal}
      CPM_PCIE1_PF0_MSI_ENABLED {0}
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_BIR {BAR_5:4}
      CPM_PCIE1_PF0_MSIX_CAP_PBA_BIR {BAR_5:4}
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_OFFSET {0}
      CPM_PCIE1_PF0_MSIX_CAP_PBA_OFFSET {8000}
}

set ps_cfg {
      DESIGN_MODE {1}
      PMC_REF_CLK_FREQMHZ {33.333333}
      PCIE_APERTURES_DUAL_ENABLE {0}
      PCIE_APERTURES_SINGLE_ENABLE {0}
      PS_BOARD_INTERFACE {Custom}
      PS_PCIE1_PERIPHERAL_ENABLE {0}
      PS_PCIE2_PERIPHERAL_ENABLE {1}
      PS_PCIE_EP_RESET1_IO {PMC_MIO 24}
      PS_PCIE_EP_RESET2_IO {PMC_MIO 25}
      PS_PCIE_RESET {{ENABLE 1}}
      SMON_ALARMS {Set_Alarms_On}
      SMON_ENABLE_TEMP_AVERAGING {0}
      SMON_TEMP_AVERAGING_SAMPLES {0}
}

create_project -force -part $part i4probe ./i4_proj
set_property target_language Verilog [current_project]

puts "NIA_PROBE_MSIX_VEC_BEGIN [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S]"

set readback_keys {CPM_PCIE1_MSI_X_OPTIONS \
                   CPM_PCIE1_AXISTEN_MSIX_VECTORS_PER_FUNCTION \
                   CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE \
                   CPM_PCIE1_PF0_MSIX_CAP_TABLE_BIR \
                   CPM_PCIE1_PF0_MSIX_CAP_PBA_BIR \
                   CPM_PCIE1_PF0_MSIX_CAP_TABLE_OFFSET \
                   CPM_PCIE1_PF0_MSIX_CAP_PBA_OFFSET \
                   CPM_PCIE1_PF0_MSI_ENABLED}

foreach v $variants {
    set name  [lindex $v 0]
    set extra [lindex $v 1]

    puts "=============================================================="
    puts "NIA_PROBE_MSIX_VEC_VARIANT $name"
    puts "NIA_PROBE_MSIX_VEC_WORDS   $extra"

    catch {close_bd_design [current_bd_design -quiet]}
    create_bd_design "bd_$name"
    current_bd_design "bd_$name"
    set cell [create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 cips_$name]

    set cfg "$base\n      $extra\n"
    if {[catch {
        set_property -dict [list CONFIG.CPM_CONFIG $cfg \
                                 CONFIG.PS_PMC_CONFIG $ps_cfg \
                                 CONFIG.PS_PMC_CONFIG_APPLIED {1}] $cell
    } err]} {
        puts "NIA_PROBE_MSIX_VEC_REJECTED $name"
        foreach line [split $err "\n"] { puts "NIA_PROBE_MSIX_VEC_REJECT_MSG $line" }
        continue
    }

    set got [get_property CONFIG.CPM_CONFIG $cell]
    foreach key $readback_keys {
        set i [lsearch -exact $got $key]
        if {$i >= 0} { puts "NIA_PROBE_MSIX_VEC_CFG $name $key = [lindex $got [expr {$i+1}]]" } \
                else { puts "NIA_PROBE_MSIX_VEC_CFG $name $key = <absent>" }
    }

    foreach pin [lsort [get_bd_pins -quiet $cell/*]] {
        set pn [get_property NAME $pin]
        if {[string match -nocase "*msix*" $pn]} {
            set l [get_property -quiet LEFT $pin]
            set r [get_property -quiet RIGHT $pin]
            set w "1"
            if {$l ne "" && $r ne ""} { set w "[expr {$l - $r + 1}] \[$l:$r\]" }
            puts "NIA_PROBE_MSIX_VEC_PIN $name [get_property DIR $pin] $pn width=$w"
        }
    }
}

puts "NIA_PROBE_MSIX_VEC_END rc=0"
