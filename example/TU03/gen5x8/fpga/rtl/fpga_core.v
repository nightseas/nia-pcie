// ---------------------------------------------------------------------------
// File        : fpga_core.v
// Description : The board independent body of the Gen5 x8, 1024-bit AXIS, example: the
//               parameters and the example core, with no device pin of its own.
// Language    : Verilog 2001
//
//
// Copyright (c) 2020 Alex Forencich
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: MIT
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module fpga_core #
(

    parameter AXIS_PCIE_DATA_WIDTH = 1024,
    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32),

    parameter AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 337 : 161,
    parameter AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 373 : 183,
    parameter AXIS_PCIE_CQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 465 : 231,
    parameter AXIS_PCIE_CC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 165 : 81,

    parameter RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256,
    parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,
    parameter CQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,
    parameter CC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,

    parameter CQ_SOP_PTR_DW = 8,
    parameter CC_SOP_PTR_DW = 8,

    parameter RQ_SEQ_NUM_WIDTH = AXIS_PCIE_DATA_WIDTH >= 512 ? 6 : 4,
    parameter RQ_SEQ_NUM_ENABLE = 1,

    parameter RQ_STRADDLE_ENC = 1,
    parameter RC_SOP_COMPACT = (AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE,
    parameter RC_FIFO_SEG_COUNT = ((AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE) ? 4 :
                                 ((RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) ? (AXIS_PCIE_DATA_WIDTH/128) : 1),

    parameter IMM_ENABLE = 1,
    parameter IMM_WIDTH = 32,

    parameter PCIE_TAG_COUNT = 256,

    parameter BAR0_APERTURE = 24,
    parameter BAR2_APERTURE = 24,
    parameter BAR4_APERTURE = 16
)
(

    input  wire                               clk,
    input  wire                               rst,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_rq_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep,
    output wire                               m_axis_rq_tlast,
    input  wire                               m_axis_rq_tready,
    output wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] m_axis_rq_tuser,
    output wire                               m_axis_rq_tvalid,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_rc_tkeep,
    input  wire                               s_axis_rc_tlast,
    output wire                               s_axis_rc_tready,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0] s_axis_rc_tuser,
    input  wire                               s_axis_rc_tvalid,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]    s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]    s_axis_cq_tkeep,
    input  wire                               s_axis_cq_tlast,
    output wire                               s_axis_cq_tready,
    input  wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] s_axis_cq_tuser,
    input  wire                               s_axis_cq_tvalid,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_cc_tkeep,
    output wire                               m_axis_cc_tlast,
    input  wire                               m_axis_cc_tready,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0] m_axis_cc_tuser,
    output wire                               m_axis_cc_tvalid,

    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_0,
    input  wire                               s_axis_rq_seq_num_valid_0,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_1,
    input  wire                               s_axis_rq_seq_num_valid_1,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_2,
    input  wire                               s_axis_rq_seq_num_valid_2,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]        s_axis_rq_seq_num_3,
    input  wire                               s_axis_rq_seq_num_valid_3,

    input  wire [2:0]                         cfg_max_payload,
    input  wire [2:0]                         cfg_max_read_req,
    input  wire [3:0]                         cfg_rcb_status,

    output wire [9:0]                         cfg_mgmt_addr,
    output wire [7:0]                         cfg_mgmt_function_number,
    output wire                               cfg_mgmt_write,
    output wire [31:0]                        cfg_mgmt_write_data,
    output wire [3:0]                         cfg_mgmt_byte_enable,
    output wire                               cfg_mgmt_read,
    input  wire [31:0]                        cfg_mgmt_read_data,
    input  wire                               cfg_mgmt_read_write_done,

    input  wire [7:0]                         cfg_fc_ph,
    input  wire [11:0]                        cfg_fc_pd,
    input  wire [7:0]                         cfg_fc_nph,
    input  wire [11:0]                        cfg_fc_npd,
    input  wire [7:0]                         cfg_fc_cplh,
    input  wire [11:0]                        cfg_fc_cpld,
    output wire [2:0]                         cfg_fc_sel,

    input  wire [3:0]                         cfg_interrupt_msix_enable,
    input  wire [3:0]                         cfg_interrupt_msix_mask,
    input  wire [251:0]                       cfg_interrupt_msix_vf_enable,
    input  wire [251:0]                       cfg_interrupt_msix_vf_mask,
    output wire [63:0]                        cfg_interrupt_msix_address,
    output wire [31:0]                        cfg_interrupt_msix_data,
    output wire                               cfg_interrupt_msix_int,
    output wire [1:0]                         cfg_interrupt_msix_vec_pending,
    input  wire                               cfg_interrupt_msix_vec_pending_status,
    input  wire                               cfg_interrupt_msix_sent,
    input  wire                               cfg_interrupt_msix_fail,
    output wire [7:0]                         cfg_interrupt_msi_function_number,

    output wire                               status_error_cor,
    output wire                               status_error_uncor,

    output wire                               status_error_cq_slot_overflow,
    output wire                               status_error_cq_leading_gap,
    output wire                               status_error_cc_sop_align,
    output wire [1:0]                         sts_cq_poisoned_tlp,
    output wire                               sts_cq_poisoned_seen
);

example_core_pcie_versal #(
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_RC_USER_WIDTH(AXIS_PCIE_RC_USER_WIDTH),
    .AXIS_PCIE_RQ_USER_WIDTH(AXIS_PCIE_RQ_USER_WIDTH),
    .AXIS_PCIE_CQ_USER_WIDTH(AXIS_PCIE_CQ_USER_WIDTH),
    .AXIS_PCIE_CC_USER_WIDTH(AXIS_PCIE_CC_USER_WIDTH),
    .RC_STRADDLE(RC_STRADDLE),
    .RQ_STRADDLE(RQ_STRADDLE),
    .CQ_STRADDLE(CQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE),
    .CQ_SOP_PTR_DW(CQ_SOP_PTR_DW),
    .CC_SOP_PTR_DW(CC_SOP_PTR_DW),
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),
    .RQ_SEQ_NUM_ENABLE(RQ_SEQ_NUM_ENABLE),
    .RQ_STRADDLE_ENC(RQ_STRADDLE_ENC),
    .RC_SOP_COMPACT(RC_SOP_COMPACT),
    .RC_FIFO_SEG_COUNT(RC_FIFO_SEG_COUNT),
    .IMM_ENABLE(IMM_ENABLE),
    .IMM_WIDTH(IMM_WIDTH),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),

    .READ_OP_TABLE_SIZE(PCIE_TAG_COUNT),
    .READ_TX_LIMIT(2**(RQ_SEQ_NUM_WIDTH-1)),
    .READ_CPLH_FC_LIMIT(AXIS_PCIE_DATA_WIDTH >= 512 ? 256 : 64),
    .READ_CPLD_FC_LIMIT(AXIS_PCIE_DATA_WIDTH >= 512 ? 2048-256 : 1024-64),
    .WRITE_OP_TABLE_SIZE(2**(RQ_SEQ_NUM_WIDTH-1)),
    .WRITE_TX_LIMIT(2**(RQ_SEQ_NUM_WIDTH-1)),
    .BAR0_APERTURE(BAR0_APERTURE),
    .BAR2_APERTURE(BAR2_APERTURE),
    .BAR4_APERTURE(BAR4_APERTURE)
)
example_core_pcie_versal_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_rc_tdata(s_axis_rc_tdata),
    .s_axis_rc_tkeep(s_axis_rc_tkeep),
    .s_axis_rc_tvalid(s_axis_rc_tvalid),
    .s_axis_rc_tready(s_axis_rc_tready),
    .s_axis_rc_tlast(s_axis_rc_tlast),
    .s_axis_rc_tuser(s_axis_rc_tuser),

    .m_axis_rq_tdata(m_axis_rq_tdata),
    .m_axis_rq_tkeep(m_axis_rq_tkeep),
    .m_axis_rq_tvalid(m_axis_rq_tvalid),
    .m_axis_rq_tready(m_axis_rq_tready),
    .m_axis_rq_tlast(m_axis_rq_tlast),
    .m_axis_rq_tuser(m_axis_rq_tuser),

    .s_axis_cq_tdata(s_axis_cq_tdata),
    .s_axis_cq_tkeep(s_axis_cq_tkeep),
    .s_axis_cq_tvalid(s_axis_cq_tvalid),
    .s_axis_cq_tready(s_axis_cq_tready),
    .s_axis_cq_tlast(s_axis_cq_tlast),
    .s_axis_cq_tuser(s_axis_cq_tuser),

    .m_axis_cc_tdata(m_axis_cc_tdata),
    .m_axis_cc_tkeep(m_axis_cc_tkeep),
    .m_axis_cc_tvalid(m_axis_cc_tvalid),
    .m_axis_cc_tready(m_axis_cc_tready),
    .m_axis_cc_tlast(m_axis_cc_tlast),
    .m_axis_cc_tuser(m_axis_cc_tuser),

    .s_axis_rq_seq_num_0(s_axis_rq_seq_num_0),
    .s_axis_rq_seq_num_valid_0(s_axis_rq_seq_num_valid_0),
    .s_axis_rq_seq_num_1(s_axis_rq_seq_num_1),
    .s_axis_rq_seq_num_valid_1(s_axis_rq_seq_num_valid_1),
    .s_axis_rq_seq_num_2(s_axis_rq_seq_num_2),
    .s_axis_rq_seq_num_valid_2(s_axis_rq_seq_num_valid_2),
    .s_axis_rq_seq_num_3(s_axis_rq_seq_num_3),
    .s_axis_rq_seq_num_valid_3(s_axis_rq_seq_num_valid_3),

    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    .cfg_fc_sel(cfg_fc_sel),

    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),

    .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
    .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
    .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),
    .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),
    .cfg_interrupt_msix_address(cfg_interrupt_msix_address),
    .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
    .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
    .cfg_interrupt_msix_vec_pending(cfg_interrupt_msix_vec_pending),
    .cfg_interrupt_msix_vec_pending_status(cfg_interrupt_msix_vec_pending_status),
    .cfg_interrupt_msix_sent(cfg_interrupt_msix_sent),
    .cfg_interrupt_msix_fail(cfg_interrupt_msix_fail),
    .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),

    .cfg_max_read_req(cfg_max_read_req),
    .cfg_max_payload(cfg_max_payload),
    .cfg_rcb_status(cfg_rcb_status),

    .status_error_cor(status_error_cor),
    .status_error_uncor(status_error_uncor),
    .status_error_cq_slot_overflow(status_error_cq_slot_overflow),
    .status_error_cq_leading_gap(status_error_cq_leading_gap),
    .status_error_cc_sop_align(status_error_cc_sop_align),
    .sts_cq_poisoned_tlp(sts_cq_poisoned_tlp),
    .sts_cq_poisoned_seen(sts_cq_poisoned_seen)
);

endmodule

`resetall
