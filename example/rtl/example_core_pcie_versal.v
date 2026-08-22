// ---------------------------------------------------------------------------
// File        : example_core_pcie_versal.v
// Description : The example core on the Versal PCIe interface. Wires
//               pcie_versal_if to the split width example core, and sets the
//               read and write engine limits the CPM5 face allows.
// Language    : Verilog 2001
//
//
// Copyright (c) 2021 Alex Forencich
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: MIT
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module example_core_pcie_versal #
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

    parameter READ_OP_TABLE_SIZE = PCIE_TAG_COUNT,

    parameter READ_TX_LIMIT = 2**(RQ_SEQ_NUM_WIDTH-1),

    parameter READ_CPLH_FC_LIMIT = AXIS_PCIE_DATA_WIDTH >= 512 ? 256 : 64,
    parameter READ_CPLD_FC_LIMIT = AXIS_PCIE_DATA_WIDTH >= 512 ? 2048-256 : 1024-64,

    parameter WRITE_OP_TABLE_SIZE = 2**(RQ_SEQ_NUM_WIDTH-1),
    parameter WRITE_TX_LIMIT = 2**(RQ_SEQ_NUM_WIDTH-1),

    parameter BAR0_APERTURE = 24,
    parameter BAR2_APERTURE = 24,
    parameter BAR4_APERTURE = 16
)
(
    input  wire                                clk,
    input  wire                                rst,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]     s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]     s_axis_rc_tkeep,
    input  wire                                s_axis_rc_tvalid,
    output wire                                s_axis_rc_tready,
    input  wire                                s_axis_rc_tlast,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0]  s_axis_rc_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]     m_axis_rq_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]     m_axis_rq_tkeep,
    output wire                                m_axis_rq_tvalid,
    input  wire                                m_axis_rq_tready,
    output wire                                m_axis_rq_tlast,
    output wire [AXIS_PCIE_RQ_USER_WIDTH-1:0]  m_axis_rq_tuser,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]     s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]     s_axis_cq_tkeep,
    input  wire                                s_axis_cq_tvalid,
    output wire                                s_axis_cq_tready,
    input  wire                                s_axis_cq_tlast,
    input  wire [AXIS_PCIE_CQ_USER_WIDTH-1:0]  s_axis_cq_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]     m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]     m_axis_cc_tkeep,
    output wire                                m_axis_cc_tvalid,
    input  wire                                m_axis_cc_tready,
    output wire                                m_axis_cc_tlast,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0]  m_axis_cc_tuser,

    input  wire [RQ_SEQ_NUM_WIDTH-1:0]         s_axis_rq_seq_num_0,
    input  wire                                s_axis_rq_seq_num_valid_0,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]         s_axis_rq_seq_num_1,
    input  wire                                s_axis_rq_seq_num_valid_1,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]         s_axis_rq_seq_num_2,
    input  wire                                s_axis_rq_seq_num_valid_2,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]         s_axis_rq_seq_num_3,
    input  wire                                s_axis_rq_seq_num_valid_3,

    output wire [9:0]                          cfg_mgmt_addr,
    output wire [7:0]                          cfg_mgmt_function_number,
    output wire                                cfg_mgmt_write,
    output wire [31:0]                         cfg_mgmt_write_data,
    output wire [3:0]                          cfg_mgmt_byte_enable,
    output wire                                cfg_mgmt_read,
    input  wire [31:0]                         cfg_mgmt_read_data,
    input  wire                                cfg_mgmt_read_write_done,

    input  wire [2:0]                          cfg_max_read_req,
    input  wire [2:0]                          cfg_max_payload,
    input  wire [3:0]                          cfg_rcb_status,

    input  wire [7:0]                          cfg_fc_ph,
    input  wire [11:0]                         cfg_fc_pd,
    input  wire [7:0]                          cfg_fc_nph,
    input  wire [11:0]                         cfg_fc_npd,
    input  wire [7:0]                          cfg_fc_cplh,
    input  wire [11:0]                         cfg_fc_cpld,
    output wire [2:0]                          cfg_fc_sel,

    input  wire [3:0]                          cfg_interrupt_msix_enable,
    input  wire [3:0]                          cfg_interrupt_msix_mask,
    input  wire [251:0]                        cfg_interrupt_msix_vf_enable,
    input  wire [251:0]                        cfg_interrupt_msix_vf_mask,
    output wire [63:0]                         cfg_interrupt_msix_address,
    output wire [31:0]                         cfg_interrupt_msix_data,
    output wire                                cfg_interrupt_msix_int,
    output wire [1:0]                          cfg_interrupt_msix_vec_pending,
    input  wire                                cfg_interrupt_msix_vec_pending_status,
    input  wire                                cfg_interrupt_msix_sent,
    input  wire                                cfg_interrupt_msix_fail,
    output wire [7:0]                          cfg_interrupt_msi_function_number,

    output wire                                status_error_cor,
    output wire                                status_error_uncor,

    output wire                                status_error_cq_slot_overflow,
    output wire                                status_error_cq_leading_gap,
    output wire                                status_error_cc_sop_align,
    output wire [1:0]                          sts_cq_poisoned_tlp,
    output wire                                sts_cq_poisoned_seen
);

parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH;
parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32;

parameter TLP_CPL_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 512 : AXIS_PCIE_DATA_WIDTH;
parameter TLP_CPL_STRB_WIDTH = TLP_CPL_DATA_WIDTH/32;

parameter CORE_TLP_DATA_WIDTH = TLP_DATA_WIDTH;
parameter CORE_TLP_STRB_WIDTH = CORE_TLP_DATA_WIDTH/32;

parameter CQCC_AXIS_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 512 : AXIS_PCIE_DATA_WIDTH;

parameter TLP_HDR_WIDTH = 128;
parameter TLP_SEG_COUNT = 1;

parameter TX_SEQ_NUM_COUNT = AXIS_PCIE_DATA_WIDTH >= 1024 ? 4 : 2;
parameter TX_SEQ_NUM_WIDTH = RQ_SEQ_NUM_WIDTH-1;
parameter TX_SEQ_NUM_ENABLE = RQ_SEQ_NUM_ENABLE;
parameter PF_COUNT = 1;
parameter VF_COUNT = 0;
parameter F_COUNT = PF_COUNT+VF_COUNT;

wire [TLP_CPL_DATA_WIDTH-1:0]                 pcie_rx_req_tlp_data;
wire [TLP_CPL_STRB_WIDTH-1:0]                 pcie_rx_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_rx_req_tlp_hdr;
wire [TLP_SEG_COUNT*3-1:0]                    pcie_rx_req_tlp_bar_id;
wire [TLP_SEG_COUNT*8-1:0]                    pcie_rx_req_tlp_func_num;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_req_tlp_eop;
wire                                          pcie_rx_req_tlp_ready;

wire [TLP_CPL_DATA_WIDTH-1:0]                 pcie_tx_cpl_tlp_data;
wire [TLP_CPL_STRB_WIDTH-1:0]                 pcie_tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_cpl_tlp_eop;
wire                                          pcie_tx_cpl_tlp_ready;

wire [TLP_CPL_DATA_WIDTH-1:0]                 core_rx_req_tlp_data;
wire [TLP_CPL_STRB_WIDTH-1:0]                 core_rx_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        core_rx_req_tlp_hdr;
wire [TLP_SEG_COUNT*3-1:0]                    core_rx_req_tlp_bar_id;
wire [TLP_SEG_COUNT*8-1:0]                    core_rx_req_tlp_func_num;
wire [TLP_SEG_COUNT-1:0]                      core_rx_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      core_rx_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      core_rx_req_tlp_eop;
wire                                          core_rx_req_tlp_ready;

wire [TLP_CPL_DATA_WIDTH-1:0]                 core_tx_cpl_tlp_data;
wire [TLP_CPL_STRB_WIDTH-1:0]                 core_tx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        core_tx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT-1:0]                      core_tx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      core_tx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      core_tx_cpl_tlp_eop;
wire                                          core_tx_cpl_tlp_ready;

wire [TLP_DATA_WIDTH-1:0]                     pcie_rx_cpl_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_rx_cpl_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_rx_cpl_tlp_hdr;
wire [TLP_SEG_COUNT*4-1:0]                    pcie_rx_cpl_tlp_error;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_rx_cpl_tlp_eop;
wire                                          pcie_rx_cpl_tlp_ready;

wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_rd_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     pcie_tx_rd_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_rd_req_tlp_eop;
wire                                          pcie_tx_rd_req_tlp_ready;

wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  axis_pcie_rd_req_tx_seq_num;
wire [TX_SEQ_NUM_COUNT-1:0]                   axis_pcie_rd_req_tx_seq_num_valid;

wire [TLP_DATA_WIDTH-1:0]                     pcie_tx_wr_req_tlp_data;
wire [TLP_STRB_WIDTH-1:0]                     pcie_tx_wr_req_tlp_strb;
wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        pcie_tx_wr_req_tlp_hdr;
wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     pcie_tx_wr_req_tlp_seq;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_valid;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_sop;
wire [TLP_SEG_COUNT-1:0]                      pcie_tx_wr_req_tlp_eop;
wire                                          pcie_tx_wr_req_tlp_ready;

wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  axis_pcie_wr_req_tx_seq_num;
wire [TX_SEQ_NUM_COUNT-1:0]                   axis_pcie_wr_req_tx_seq_num_valid;

wire [31:0]                                   pcie_tx_msix_wr_req_tlp_data;
wire                                          pcie_tx_msix_wr_req_tlp_strb;
wire [TLP_HDR_WIDTH-1:0]                      pcie_tx_msix_wr_req_tlp_hdr;
wire                                          pcie_tx_msix_wr_req_tlp_valid;
wire                                          pcie_tx_msix_wr_req_tlp_sop;
wire                                          pcie_tx_msix_wr_req_tlp_eop;
wire                                          pcie_tx_msix_wr_req_tlp_ready;

wire ext_tag_enable;
wire msix_enable;
wire msix_mask;

wire rx_cpl_stall;

wire s_axis_rc_tvalid_int;
wire s_axis_rc_tready_int;

assign s_axis_rc_tvalid_int = s_axis_rc_tvalid & ~rx_cpl_stall;
assign s_axis_rc_tready = s_axis_rc_tready_int & ~rx_cpl_stall;

initial begin
    $display("T36C_EXCORE_WITNESS instance=%m AXIS_PCIE_DATA_WIDTH=%0d TLP_DATA_WIDTH=%0d TLP_CPL_DATA_WIDTH=%0d CORE_TLP_DATA_WIDTH=%0d CQCC_AXIS_DATA_WIDTH=%0d TX_SEQ_NUM_COUNT=%0d TX_SEQ_NUM_WIDTH=%0d RQ_SEQ_NUM_WIDTH=%0d RQ_STRADDLE_ENC=%0d RC_SOP_COMPACT=%0d RC_FIFO_SEG_COUNT=%0d",
        AXIS_PCIE_DATA_WIDTH, TLP_DATA_WIDTH, TLP_CPL_DATA_WIDTH, CORE_TLP_DATA_WIDTH,
        CQCC_AXIS_DATA_WIDTH, TX_SEQ_NUM_COUNT, TX_SEQ_NUM_WIDTH, RQ_SEQ_NUM_WIDTH,
        RQ_STRADDLE_ENC, RC_SOP_COMPACT, RC_FIFO_SEG_COUNT);

    if (TLP_SEG_COUNT != 1) begin
        $error("Error: TLP_SEG_COUNT must be 1 (V12) (instance %m)");
        $finish;
    end
    if (TLP_HDR_WIDTH != 128) begin
        $error("Error: TLP_HDR_WIDTH must be 128 (V12) (instance %m)");
        $finish;
    end

    if (TLP_CPL_DATA_WIDTH != CQCC_AXIS_DATA_WIDTH) begin
        $error("Error: TLP_CPL_DATA_WIDTH (%0d) must equal the CQ/CC AXIS width on the narrow side of pcie_versal_if_cqcc_gearbox (%0d) - pcie_us_if_cq.v:113 and pcie_us_if_cc.v:113 $error unless their TLP_DATA_WIDTH equals their AXIS_PCIE_DATA_WIDTH, and both are unmodified per contract section 1 (instance %m)",
            TLP_CPL_DATA_WIDTH, CQCC_AXIS_DATA_WIDTH);
        $finish;
    end

    if (TLP_CPL_STRB_WIDTH*32 != TLP_CPL_DATA_WIDTH ||
        CORE_TLP_STRB_WIDTH*32 != CORE_TLP_DATA_WIDTH) begin
        $error("Error: generic TLP interfaces require dword (32-bit) granularity: completer %0d/%0d, requester %0d/%0d (instance %m)",
            TLP_CPL_STRB_WIDTH*32, TLP_CPL_DATA_WIDTH,
            CORE_TLP_STRB_WIDTH*32, CORE_TLP_DATA_WIDTH);
        $finish;
    end
end

pcie_versal_if #(
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
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_CPL_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .TLP_CPL_STRB_WIDTH(TLP_CPL_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH),

    .RQ_STRADDLE_ENC(RQ_STRADDLE_ENC),
    .RC_SOP_COMPACT(RC_SOP_COMPACT),
    .RC_FIFO_SEG_COUNT(RC_FIFO_SEG_COUNT),
    .PF_COUNT(PF_COUNT),
    .VF_COUNT(VF_COUNT),
    .F_COUNT(F_COUNT),
    .READ_EXT_TAG_ENABLE(1),
    .READ_MAX_READ_REQ_SIZE(1),
    .READ_MAX_PAYLOAD_SIZE(1),
    .MSIX_ENABLE(1),
    .MSI_ENABLE(0)
)
pcie_versal_if_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_rc_tdata(s_axis_rc_tdata),
    .s_axis_rc_tkeep(s_axis_rc_tkeep),
    .s_axis_rc_tvalid(s_axis_rc_tvalid_int),
    .s_axis_rc_tready(s_axis_rc_tready_int),
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

    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),

    .cfg_max_payload(cfg_max_payload),
    .cfg_max_read_req(cfg_max_read_req),

    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    .cfg_fc_sel(cfg_fc_sel),

    .cfg_interrupt_msi_enable(),
    .cfg_interrupt_msi_vf_enable(),
    .cfg_interrupt_msi_mmenable(),
    .cfg_interrupt_msi_mask_update(),
    .cfg_interrupt_msi_data(),
    .cfg_interrupt_msi_select(),
    .cfg_interrupt_msi_int(),
    .cfg_interrupt_msi_pending_status(),
    .cfg_interrupt_msi_pending_status_data_enable(),
    .cfg_interrupt_msi_pending_status_function_num(),
    .cfg_interrupt_msi_sent(),
    .cfg_interrupt_msi_fail(),
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
    .cfg_interrupt_msi_attr(),
    .cfg_interrupt_msi_tph_present(),
    .cfg_interrupt_msi_tph_type(),
    .cfg_interrupt_msi_tph_st_tag(),
    .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),

    .rx_req_tlp_data(pcie_rx_req_tlp_data),
    .rx_req_tlp_strb(pcie_rx_req_tlp_strb),
    .rx_req_tlp_hdr(pcie_rx_req_tlp_hdr),
    .rx_req_tlp_bar_id(pcie_rx_req_tlp_bar_id),
    .rx_req_tlp_func_num(pcie_rx_req_tlp_func_num),
    .rx_req_tlp_valid(pcie_rx_req_tlp_valid),
    .rx_req_tlp_sop(pcie_rx_req_tlp_sop),
    .rx_req_tlp_eop(pcie_rx_req_tlp_eop),
    .rx_req_tlp_ready(pcie_rx_req_tlp_ready),

    .rx_cpl_tlp_data(pcie_rx_cpl_tlp_data),
    .rx_cpl_tlp_strb(pcie_rx_cpl_tlp_strb),
    .rx_cpl_tlp_hdr(pcie_rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(pcie_rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(pcie_rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop(pcie_rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(pcie_rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(pcie_rx_cpl_tlp_ready),

    .tx_rd_req_tlp_hdr(pcie_tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(pcie_tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(pcie_tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(pcie_tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(pcie_tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(pcie_tx_rd_req_tlp_ready),

    .m_axis_rd_req_tx_seq_num(axis_pcie_rd_req_tx_seq_num),
    .m_axis_rd_req_tx_seq_num_valid(axis_pcie_rd_req_tx_seq_num_valid),

    .tx_wr_req_tlp_data(pcie_tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(pcie_tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(pcie_tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(pcie_tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(pcie_tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(pcie_tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(pcie_tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(pcie_tx_wr_req_tlp_ready),

    .m_axis_wr_req_tx_seq_num(axis_pcie_wr_req_tx_seq_num),
    .m_axis_wr_req_tx_seq_num_valid(axis_pcie_wr_req_tx_seq_num_valid),

    .tx_cpl_tlp_data(pcie_tx_cpl_tlp_data),
    .tx_cpl_tlp_strb(pcie_tx_cpl_tlp_strb),
    .tx_cpl_tlp_hdr(pcie_tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(pcie_tx_cpl_tlp_valid),
    .tx_cpl_tlp_sop(pcie_tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(pcie_tx_cpl_tlp_eop),
    .tx_cpl_tlp_ready(pcie_tx_cpl_tlp_ready),

    .tx_msix_wr_req_tlp_data(pcie_tx_msix_wr_req_tlp_data),
    .tx_msix_wr_req_tlp_strb(pcie_tx_msix_wr_req_tlp_strb),
    .tx_msix_wr_req_tlp_hdr(pcie_tx_msix_wr_req_tlp_hdr),
    .tx_msix_wr_req_tlp_valid(pcie_tx_msix_wr_req_tlp_valid),
    .tx_msix_wr_req_tlp_sop(pcie_tx_msix_wr_req_tlp_sop),
    .tx_msix_wr_req_tlp_eop(pcie_tx_msix_wr_req_tlp_eop),
    .tx_msix_wr_req_tlp_ready(pcie_tx_msix_wr_req_tlp_ready),

    .tx_fc_ph_av(),
    .tx_fc_pd_av(),
    .tx_fc_nph_av(),
    .tx_fc_npd_av(),
    .tx_fc_cplh_av(),
    .tx_fc_cpld_av(),

    .ext_tag_enable(ext_tag_enable),
    .max_read_request_size(),
    .max_payload_size(),
    .msix_enable(msix_enable),
    .msix_mask(msix_mask),

    .msi_irq(0),

    .status_error_cq_slot_overflow(status_error_cq_slot_overflow),
    .status_error_cq_leading_gap(status_error_cq_leading_gap),
    .status_error_cc_sop_align(status_error_cc_sop_align),
    .sts_cq_poisoned_tlp(sts_cq_poisoned_tlp),
    .sts_cq_poisoned_seen(sts_cq_poisoned_seen)
);

assign core_rx_req_tlp_data     = pcie_rx_req_tlp_data;
assign core_rx_req_tlp_strb     = pcie_rx_req_tlp_strb;
assign core_rx_req_tlp_hdr      = pcie_rx_req_tlp_hdr;
assign core_rx_req_tlp_bar_id   = pcie_rx_req_tlp_bar_id;
assign core_rx_req_tlp_func_num = pcie_rx_req_tlp_func_num;
assign core_rx_req_tlp_valid    = pcie_rx_req_tlp_valid;
assign core_rx_req_tlp_sop      = pcie_rx_req_tlp_sop;
assign core_rx_req_tlp_eop      = pcie_rx_req_tlp_eop;
assign pcie_rx_req_tlp_ready    = core_rx_req_tlp_ready;

assign pcie_tx_cpl_tlp_data     = core_tx_cpl_tlp_data;
assign pcie_tx_cpl_tlp_strb     = core_tx_cpl_tlp_strb;
assign pcie_tx_cpl_tlp_hdr      = core_tx_cpl_tlp_hdr;
assign pcie_tx_cpl_tlp_valid    = core_tx_cpl_tlp_valid;
assign pcie_tx_cpl_tlp_sop      = core_tx_cpl_tlp_sop;
assign pcie_tx_cpl_tlp_eop      = core_tx_cpl_tlp_eop;
assign core_tx_cpl_tlp_ready    = pcie_tx_cpl_tlp_ready;

example_core_pcie_split_width #(

    .TLP_DATA_WIDTH(CORE_TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(CORE_TLP_STRB_WIDTH),

    .TLP_CPL_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .TLP_CPL_STRB_WIDTH(TLP_CPL_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH),
    .TX_SEQ_NUM_ENABLE(TX_SEQ_NUM_ENABLE),
    .IMM_ENABLE(IMM_ENABLE),
    .IMM_WIDTH(IMM_WIDTH),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),
    .READ_OP_TABLE_SIZE(READ_OP_TABLE_SIZE),
    .READ_TX_LIMIT(READ_TX_LIMIT),
    .READ_CPLH_FC_LIMIT(READ_CPLH_FC_LIMIT),
    .READ_CPLD_FC_LIMIT(READ_CPLD_FC_LIMIT),
    .WRITE_OP_TABLE_SIZE(WRITE_OP_TABLE_SIZE),
    .WRITE_TX_LIMIT(WRITE_TX_LIMIT),
    .TLP_FORCE_64_BIT_ADDR(1),
    .CHECK_BUS_NUMBER(0),
    .BAR0_APERTURE(BAR0_APERTURE),
    .BAR2_APERTURE(BAR2_APERTURE),
    .BAR4_APERTURE(BAR4_APERTURE)
)
core_pcie_inst (
    .clk(clk),
    .rst(rst),

    .rx_req_tlp_data(core_rx_req_tlp_data),
    .rx_req_tlp_strb(core_rx_req_tlp_strb),
    .rx_req_tlp_hdr(core_rx_req_tlp_hdr),
    .rx_req_tlp_valid(core_rx_req_tlp_valid),
    .rx_req_tlp_bar_id(core_rx_req_tlp_bar_id),
    .rx_req_tlp_func_num(core_rx_req_tlp_func_num),
    .rx_req_tlp_sop(core_rx_req_tlp_sop),
    .rx_req_tlp_eop(core_rx_req_tlp_eop),
    .rx_req_tlp_ready(core_rx_req_tlp_ready),

    .tx_cpl_tlp_data(core_tx_cpl_tlp_data),
    .tx_cpl_tlp_strb(core_tx_cpl_tlp_strb),
    .tx_cpl_tlp_hdr(core_tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(core_tx_cpl_tlp_valid),
    .tx_cpl_tlp_sop(core_tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(core_tx_cpl_tlp_eop),
    .tx_cpl_tlp_ready(core_tx_cpl_tlp_ready),

    .rx_cpl_tlp_data(pcie_rx_cpl_tlp_data),
    .rx_cpl_tlp_strb(pcie_rx_cpl_tlp_strb),
    .rx_cpl_tlp_hdr(pcie_rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(pcie_rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(pcie_rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop(pcie_rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(pcie_rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(pcie_rx_cpl_tlp_ready),

    .tx_rd_req_tlp_hdr(pcie_tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(pcie_tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(pcie_tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(pcie_tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(pcie_tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(pcie_tx_rd_req_tlp_ready),

    .tx_wr_req_tlp_data(pcie_tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(pcie_tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(pcie_tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(pcie_tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(pcie_tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(pcie_tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(pcie_tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(pcie_tx_wr_req_tlp_ready),

    .s_axis_rd_req_tx_seq_num(axis_pcie_rd_req_tx_seq_num),
    .s_axis_rd_req_tx_seq_num_valid(axis_pcie_rd_req_tx_seq_num_valid),
    .s_axis_wr_req_tx_seq_num(axis_pcie_wr_req_tx_seq_num),
    .s_axis_wr_req_tx_seq_num_valid(axis_pcie_wr_req_tx_seq_num_valid),

    .tx_msix_wr_req_tlp_data(pcie_tx_msix_wr_req_tlp_data),
    .tx_msix_wr_req_tlp_strb(pcie_tx_msix_wr_req_tlp_strb),
    .tx_msix_wr_req_tlp_hdr(pcie_tx_msix_wr_req_tlp_hdr),
    .tx_msix_wr_req_tlp_valid(pcie_tx_msix_wr_req_tlp_valid),
    .tx_msix_wr_req_tlp_sop(pcie_tx_msix_wr_req_tlp_sop),
    .tx_msix_wr_req_tlp_eop(pcie_tx_msix_wr_req_tlp_eop),
    .tx_msix_wr_req_tlp_ready(pcie_tx_msix_wr_req_tlp_ready),

    .bus_num(8'd0),
    .ext_tag_enable(ext_tag_enable),
    .rcb_128b(cfg_rcb_status[0]),
    .max_read_request_size(cfg_max_read_req),
    .max_payload_size(cfg_max_payload),
    .msix_enable(msix_enable),
    .msix_mask(msix_mask),

    .status_error_cor(status_error_cor),
    .status_error_uncor(status_error_uncor),

    .rx_cpl_stall(rx_cpl_stall)
);

endmodule

`resetall
