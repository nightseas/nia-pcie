# ---------------------------------------------------------------------------
# File        : cips_cpm5_pcie_g5x8.tcl
# Description : Builds the CPM5 Gen5x8 block design and checks every value it set,
#               comparing what the IP reports against what was requested, so a
#               silently ignored configuration is reported rather than assumed.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Tcl
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

proc nia_cfg_get { cfg name } {
    set i [lsearch -exact $cfg $name]
    if {$i < 0 || $i + 1 >= [llength $cfg]} { return "<ABSENT>" }
    return [lindex $cfg [expr {$i + 1}]]
}

proc nia_hexeq { a b } {
    if {[scan $a %x x] != 1} { return 0 }
    if {[scan $b %x y] != 1} { return 0 }
    return [expr {$x == $y}]
}

proc nia_cips_bd_name { } {
    return "cips_cpm5_pcie_g5x8"
}

proc nia_cips_cpm_config { } {
    return [list \
        CPM_PCIE0_MODES {None} \
        CPM_PCIE1_MODES {PCIE} \
        CPM_PCIE1_MODE_SELECTION {Advanced} \
        CPM_PCIE1_MAX_LINK_SPEED {32.0_GT/s} \
        CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
        CPM_PCIE1_REF_CLK_FREQ {100_MHz} \
        CPM_PCIE1_AXISTEN_IF_ENABLE_CLIENT_TAG {1} \
        CPM_PCIE1_CFG_CTL_IF {1} \
        CPM_PCIE1_CFG_EXT_IF {1} \
        CPM_PCIE1_CFG_FC_IF {1} \
        CPM_PCIE1_CFG_MGMT_IF {1} \
        CPM_PCIE1_CFG_STS_IF {1} \
        CPM_PCIE1_MESG_RSVD_IF {1} \
        CPM_PCIE1_MESG_TRANSMIT_IF {1} \
        CPM_PCIE1_PASID_IF {1} \
        CPM_PCIE1_TX_FC_IF {1} \
        CPM_PCIE1_MSI_X_OPTIONS {MSI-X_Internal} \
        CPM_PCIE1_PF0_MSI_ENABLED {0} \
        CPM_PCIE1_PF0_CFG_DEV_ID {0001} \
        CPM_PCIE1_PF0_BAR0_ENABLED {1} \
        CPM_PCIE1_PF0_BAR0_TYPE {Memory} \
        CPM_PCIE1_PF0_BAR0_SIZE {16} \
        CPM_PCIE1_PF0_BAR0_SCALE {Megabytes} \
        CPM_PCIE1_PF0_BAR0_64BIT {1} \
        CPM_PCIE1_PF0_BAR0_PREFETCHABLE {1} \
        CPM_PCIE1_PF0_BAR2_ENABLED {1} \
        CPM_PCIE1_PF0_BAR2_TYPE {Memory} \
        CPM_PCIE1_PF0_BAR2_SIZE {16} \
        CPM_PCIE1_PF0_BAR2_SCALE {Megabytes} \
        CPM_PCIE1_PF0_BAR2_64BIT {1} \
        CPM_PCIE1_PF0_BAR2_PREFETCHABLE {1} \
        CPM_PCIE1_PF0_BAR4_ENABLED {1} \
        CPM_PCIE1_PF0_BAR4_TYPE {Memory} \
        CPM_PCIE1_PF0_BAR4_SIZE {64} \
        CPM_PCIE1_PF0_BAR4_SCALE {Kilobytes} \
        CPM_PCIE1_PF0_BAR4_64BIT {1} \
        CPM_PCIE1_PF0_BAR4_PREFETCHABLE {1} \
        CPM_PCIE1_PF0_DEV_CAP_MAX_PAYLOAD {1024_bytes} \
        CPM_PCIE1_PF0_MSIX_CAP_TABLE_BIR {BAR_5:4} \
        CPM_PCIE1_PF0_MSIX_CAP_PBA_BIR {BAR_5:4} \
        CPM_PCIE1_PF0_MSIX_CAP_TABLE_OFFSET {0} \
        CPM_PCIE1_PF0_MSIX_CAP_PBA_OFFSET {8000} \
        CPM_PCIE1_PF0_DEV_CAP_EXT_TAG_EN {1} \
        CPM_PCIE1_EN_PARITY {0} \
        CPM_PCIE1_AXISTEN_IF_TX_PARITY_EN {0} \
        CPM_PCIE1_AXISTEN_IF_EXT_512_RQ_STRADDLE {1} \
        CPM_PCIE1_AXISTEN_IF_EXT_512_RC_STRADDLE {1} \
        CPM_PCIE1_AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE {1} \
        CPM_PCIE1_AXISTEN_IF_EXT_512_CQ_STRADDLE {1} \
        CPM_PCIE1_AXISTEN_IF_EXT_512_CC_STRADDLE {1} \
        CPM_PCIE1_RQ_STRADDLE_SIZE {4_TLP} \
        CPM_PCIE1_CQ_STRADDLE_SIZE {2_TLP} \
        CPM_PCIE1_CC_STRADDLE_SIZE {2_TLP} \
        CPM_PCIE1_RC_STRADDLE_SIZE {8_TLP} \
    ]
}

proc nia_cips_ps_pmc_config { } {
    return [list \
        DESIGN_MODE {1} \
        PMC_REF_CLK_FREQMHZ {50} \
        PCIE_APERTURES_DUAL_ENABLE {0} \
        PCIE_APERTURES_SINGLE_ENABLE {0} \
        PS_BOARD_INTERFACE {Custom} \
        PS_PCIE1_PERIPHERAL_ENABLE {0} \
        PS_PCIE2_PERIPHERAL_ENABLE {1} \
        PS_PCIE_EP_RESET1_IO {PMC_MIO 24} \
        PS_PCIE_EP_RESET2_IO {PMC_MIO 25} \
        PS_PCIE_RESET {{ENABLE 1}} \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_ENABLE_TEMP_AVERAGING {0} \
        SMON_TEMP_AVERAGING_SAMPLES {0} \
    ]
}

proc nia_cips_axis_face { } {
    return [list \
        rq_tdata_num_bytes 128 \
        rq_tuser_width     373 \
        cc_tdata_num_bytes 128 \
        cc_tuser_width     165 \
        cq_tuser_width     465 \
        rc_tuser_width     337 \
        axis_data_width    1024 \
    ]
}

proc nia_cips_request { part } {
    set out {}
    lappend out "bd $part [nia_cips_bd_name] versal_cips:3.4"
    foreach {k v} [nia_cips_axis_face] {
        lappend out "face $k $v"
    }
    foreach {k v} [nia_cips_cpm_config] {
        lappend out "cpm $k $v"
    }
    foreach {k v} [nia_cips_ps_pmc_config] {
        lappend out "pspmc $k $v"
    }
    return [join [lsort $out] "\n"]
}

proc nia_create_cips_cpm5_pcie_g5x8 { } {

  set bd [nia_cips_bd_name]

  create_bd_design $bd
  current_bd_design $bd

  set gt_refclk1 [ create_bd_intf_port -mode Slave \
      -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_refclk1 ]

  set PCIE1_GT [ create_bd_intf_port -mode Master \
      -vlnv xilinx.com:interface:gt_rtl:1.0 PCIE1_GT ]

  set pcie1_s_axis_rq [ create_bd_intf_port -mode Slave \
      -vlnv xilinx.com:interface:axis_rtl:1.0 pcie1_s_axis_rq ]
  set_property -dict [ list \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.LAYERED_METADATA {undef} \
    CONFIG.TDATA_NUM_BYTES {128} \
    CONFIG.TDEST_WIDTH {0} \
    CONFIG.TID_WIDTH {0} \
    CONFIG.TUSER_WIDTH {373} \
  ] $pcie1_s_axis_rq

  set pcie1_s_axis_cc [ create_bd_intf_port -mode Slave \
      -vlnv xilinx.com:interface:axis_rtl:1.0 pcie1_s_axis_cc ]
  set_property -dict [ list \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TREADY {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.LAYERED_METADATA {undef} \
    CONFIG.TDATA_NUM_BYTES {128} \
    CONFIG.TDEST_WIDTH {0} \
    CONFIG.TID_WIDTH {0} \
    CONFIG.TUSER_WIDTH {165} \
  ] $pcie1_s_axis_cc

  set pcie1_m_axis_cq [ create_bd_intf_port -mode Master \
      -vlnv xilinx.com:interface:axis_rtl:1.0 pcie1_m_axis_cq ]
  set pcie1_m_axis_rc [ create_bd_intf_port -mode Master \
      -vlnv xilinx.com:interface:axis_rtl:1.0 pcie1_m_axis_rc ]

  set pcie1_cfg_mgmt      [ create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:pcie4_cfg_mgmt_rtl:1.0      pcie1_cfg_mgmt ]
  set pcie1_cfg_control   [ create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:pcie5_cfg_control_rtl:1.0   pcie1_cfg_control ]
  set pcie1_cfg_status    [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie5_cfg_status_rtl:1.0    pcie1_cfg_status ]
  set pcie1_cfg_fc        [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_cfg_fc_rtl:1.1         pcie1_cfg_fc ]
  set pcie1_cfg_msix      [ create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:pcie4_cfg_msix_rtl:1.0      pcie1_cfg_msix ]
  set pcie1_cfg_interrupt [ create_bd_intf_port -mode Slave  -vlnv xilinx.com:interface:pcie3_cfg_interrupt_rtl:1.0 pcie1_cfg_interrupt ]
  set pcie1_transmit_fc   [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie3_transmit_fc_rtl:1.0   pcie1_transmit_fc ]
  set pcie1_cfg_ext       [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie3_cfg_ext_rtl:1.0       pcie1_cfg_ext ]

  set pcie1_user_lnk_up [ create_bd_port -dir O pcie1_user_lnk_up ]
  set pcie1_user_reset  [ create_bd_port -dir O -type rst pcie1_user_reset ]
  set pcie1_user_clk    [ create_bd_port -dir O -type clk pcie1_user_clk ]
  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {pcie1_s_axis_rq:pcie1_s_axis_cc:pcie1_m_axis_rc:pcie1_m_axis_cq} \
    CONFIG.ASSOCIATED_RESET {pcie1_user_reset} \
  ] $pcie1_user_clk

  set versal_cips_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0 ]

  set_property -dict [list \
    CONFIG.CPM_CONFIG [nia_cips_cpm_config] \
    CONFIG.PS_PMC_CONFIG [nia_cips_ps_pmc_config] \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \
  ] $versal_cips_0

  connect_bd_intf_net [get_bd_intf_ports gt_refclk1]          [get_bd_intf_pins versal_cips_0/gt_refclk1]
  connect_bd_intf_net [get_bd_intf_ports PCIE1_GT]            [get_bd_intf_pins versal_cips_0/PCIE1_GT]
  connect_bd_intf_net [get_bd_intf_ports pcie1_s_axis_rq]     [get_bd_intf_pins versal_cips_0/pcie1_s_axis_rq]
  connect_bd_intf_net [get_bd_intf_ports pcie1_s_axis_cc]     [get_bd_intf_pins versal_cips_0/pcie1_s_axis_cc]
  connect_bd_intf_net [get_bd_intf_ports pcie1_m_axis_cq]     [get_bd_intf_pins versal_cips_0/pcie1_m_axis_cq]
  connect_bd_intf_net [get_bd_intf_ports pcie1_m_axis_rc]     [get_bd_intf_pins versal_cips_0/pcie1_m_axis_rc]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_mgmt]      [get_bd_intf_pins versal_cips_0/pcie1_cfg_mgmt]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_control]   [get_bd_intf_pins versal_cips_0/pcie1_cfg_control]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_status]    [get_bd_intf_pins versal_cips_0/pcie1_cfg_status]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_fc]        [get_bd_intf_pins versal_cips_0/pcie1_cfg_fc]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_msix]      [get_bd_intf_pins versal_cips_0/pcie1_cfg_msix]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_interrupt] [get_bd_intf_pins versal_cips_0/pcie1_cfg_interrupt]
  connect_bd_intf_net [get_bd_intf_ports pcie1_transmit_fc]   [get_bd_intf_pins versal_cips_0/pcie1_transmit_fc]
  connect_bd_intf_net [get_bd_intf_ports pcie1_cfg_ext]       [get_bd_intf_pins versal_cips_0/pcie1_cfg_ext]

  connect_bd_net [get_bd_pins versal_cips_0/pcie1_user_clk]    [get_bd_ports pcie1_user_clk]
  connect_bd_net [get_bd_pins versal_cips_0/pcie1_user_reset]  [get_bd_ports pcie1_user_reset]
  connect_bd_net [get_bd_pins versal_cips_0/pcie1_user_lnk_up] [get_bd_ports pcie1_user_lnk_up]

  assign_bd_address
  validate_bd_design

  set expect [list \
      CPM_PCIE1_MODES                      PCIE \
      CPM_PCIE1_MAX_LINK_SPEED             32.0_GT/s \
      CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH X8 \
      CPM_PCIE1_REF_CLK_FREQ               100_MHz \
      CPM_PCIE1_RQ_STRADDLE_SIZE           4_TLP \
      CPM_PCIE1_RC_STRADDLE_SIZE           8_TLP \
      CPM_PCIE1_PASID_IF                   1 \
      CPM_PCIE1_CFG_EXT_IF                 1 \
      CPM_PCIE1_PF0_BAR0_ENABLED           1 \
      CPM_PCIE1_PF0_BAR0_SIZE              16 \
      CPM_PCIE1_PF0_BAR0_SCALE             Megabytes \
      CPM_PCIE1_PF0_BAR0_64BIT             1 \
      CPM_PCIE1_PF0_BAR0_PREFETCHABLE      1 \
      CPM_PCIE1_PF0_BAR2_ENABLED           1 \
      CPM_PCIE1_PF0_BAR2_SIZE              16 \
      CPM_PCIE1_PF0_BAR2_SCALE             Megabytes \
      CPM_PCIE1_PF0_BAR2_64BIT             1 \
      CPM_PCIE1_PF0_BAR4_ENABLED           1 \
      CPM_PCIE1_PF0_BAR4_SIZE              64 \
      CPM_PCIE1_PF0_BAR4_SCALE             Kilobytes \
      CPM_PCIE1_PF0_BAR4_64BIT             1 \
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_BIR     BAR_5:4 \
      CPM_PCIE1_PF0_MSIX_CAP_PBA_BIR       BAR_5:4 \
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_OFFSET  0 \
      CPM_PCIE1_PF0_MSIX_CAP_PBA_OFFSET    8000 \
      CPM_PCIE1_MSI_X_OPTIONS              MSI-X_Internal \
      CPM_PCIE1_PF0_DEV_CAP_MAX_PAYLOAD    1024_bytes \
      CPM_PCIE1_EN_PARITY                  0 \
      CPM_PCIE1_AXISTEN_IF_TX_PARITY_EN    0 \
  ]

  set cfg [get_property CONFIG.CPM_CONFIG [get_bd_cells versal_cips_0]]

  set bad 0
  puts "NIA_BARMAP_BEGIN"
  puts "NIA_BARMAP tokens=[llength $cfg]"
  foreach {name want} $expect {
      set have [nia_cfg_get $cfg $name]
      if {[string equal -nocase $have $want] || [nia_hexeq $have $want]} {
          puts "NIA_BARMAP OK       $name = $have"
      } else {
          puts "NIA_BARMAP MISMATCH $name = $have   (wanted $want)"
          incr bad
      }
  }
  foreach n {CPM_PCIE1_AXISTEN_IF_EXT_512_RQ_STRADDLE \
             CPM_PCIE1_AXISTEN_IF_EXT_512_RC_STRADDLE \
             CPM_PCIE1_AXISTEN_IF_EXT_512_RC_4TLP_STRADDLE \
             CPM_PCIE1_AXISTEN_IF_EXT_512_CQ_STRADDLE \
             CPM_PCIE1_AXISTEN_IF_EXT_512_CC_STRADDLE \
             CPM_PCIE1_CQ_STRADDLE_SIZE \
             CPM_PCIE1_CC_STRADDLE_SIZE} {
      puts "NIA_BARMAP REPORT   $n = [nia_cfg_get $cfg $n]"
  }
  puts "NIA_BARMAP_END bad=$bad"
  set ::nia_barmap_bad $bad

  if {$bad != 0} {
      error "NIA_BARMAP FAILED: $bad CPM_CONFIG word(s) did not reach the generated IP."
  }

  save_bd_design
}

proc nia_cips_width_probe { } {
  set bd [nia_cips_bd_name]
  set w [get_files -quiet ${bd}_wrapper.v]
  if {$w eq ""} { set w [get_files -quiet ${bd}_wrapper.sv] }
  set bad 0
  puts "NIA_WIDTHPROBE_BEGIN"
  puts "NIA_WIDTHPROBE wrapper = $w"
  if {$w ne "" && [file exists $w]} {
      set fh [open $w r]; set txt [read $fh]; close $fh
      foreach {sig want} {pcie1_s_axis_rq_tuser 373 pcie1_m_axis_rc_tuser 337 \
                          pcie1_m_axis_cq_tuser 465 pcie1_s_axis_cc_tuser 165 \
                          pcie1_s_axis_rq_tdata 1024 pcie1_m_axis_rc_tdata 1024 \
                          pcie1_m_axis_cq_tdata 1024 pcie1_s_axis_cc_tdata 1024} {
          set hi "?"
          foreach line [split $txt "\n"] {
              if {[string first $sig $line] >= 0} {
                  if {[regexp {\[(\d+):0\]} $line -> h]} { set hi $h; break }
              }
          }
          if {$hi eq "?"} {
              puts "NIA_WIDTHPROBE $sig = NOT_FOUND (wanted $want)"
              incr bad
          } elseif {[expr {$hi + 1}] == $want} {
              puts "NIA_WIDTHPROBE $sig = [expr {$hi + 1}] OK"
          } else {
              puts "NIA_WIDTHPROBE $sig = [expr {$hi + 1}] MISMATCH (wanted $want)"
              incr bad
          }
      }
  } else {
      puts "NIA_WIDTHPROBE wrapper file not found"
      incr bad
  }
  puts "NIA_WIDTHPROBE_END bad=$bad"
  return $bad
}

if {![info exists ::nia_cips_define_only]} {
    nia_create_cips_cpm5_pcie_g5x8
    make_wrapper -files [get_files [nia_cips_bd_name].bd] -top -import
    nia_cips_width_probe
}
