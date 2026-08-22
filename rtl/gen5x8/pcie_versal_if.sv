// ---------------------------------------------------------------------------
// File        : pcie_versal_if.sv
// Description : The CPM5 PCIe interface at 1024-bit AXI4-Stream. Instantiates the
//               requester request and completion paths, the completer gearbox,
//               and the completer interfaces of the DMA library.
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_if #
(

    parameter AXIS_PCIE_DATA_WIDTH = 1024,

    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32),

    parameter AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 337 : 161,

    parameter AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 373 : 137,

    parameter AXIS_PCIE_CQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 465 : 183,

    parameter AXIS_PCIE_CC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 165 : 81,

    parameter RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256,

    parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,

    parameter CQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,

    parameter CC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512,

    parameter CQ_SOP_PTR_DW = 8,
    parameter CC_SOP_PTR_DW = 8,

    parameter RQ_SEQ_NUM_WIDTH = AXIS_PCIE_DATA_WIDTH >= 512 ? 6 : 4,

    parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH,
    parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32,

    parameter TLP_CPL_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 512 : AXIS_PCIE_DATA_WIDTH,
    parameter TLP_CPL_STRB_WIDTH = TLP_CPL_DATA_WIDTH/32,

    parameter TLP_HDR_WIDTH = 128,

    parameter TLP_SEG_COUNT = 1,

    parameter TX_SEQ_NUM_COUNT = AXIS_PCIE_DATA_WIDTH >= 1024 ? 4 : 2,
    parameter TX_SEQ_NUM_WIDTH = RQ_SEQ_NUM_WIDTH-1,

    parameter RQ_STRADDLE_ENC = 1,

    parameter RC_SOP_COMPACT = (AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE,

    parameter RC_FIFO_SEG_COUNT = ((AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE) ? 4 :
                                  ((RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) ? (AXIS_PCIE_DATA_WIDTH/128) : 1),

    parameter PF_COUNT = 1,
    parameter VF_COUNT = 0,
    parameter F_COUNT = PF_COUNT+VF_COUNT,

    parameter VF_OFFSET = AXIS_PCIE_DATA_WIDTH >= 512 ? 4 : 64,
    parameter PCIE_CAP_OFFSET = AXIS_PCIE_DATA_WIDTH >= 512 ? 12'h070 : 12'h0C0,
    parameter READ_EXT_TAG_ENABLE = 1,
    parameter READ_MAX_READ_REQ_SIZE = 1,
    parameter READ_MAX_PAYLOAD_SIZE = 1,

    parameter MSIX_ENABLE = 1,

    parameter MSI_ENABLE = 0,

    parameter MSI_COUNT = 32
)
(
    input  wire                                          clk,
    input  wire                                          rst,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]               s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]               s_axis_rc_tkeep,
    input  wire                                          s_axis_rc_tvalid,
    output wire                                          s_axis_rc_tready,
    input  wire                                          s_axis_rc_tlast,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0]            s_axis_rc_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]               m_axis_rq_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]               m_axis_rq_tkeep,
    output wire                                          m_axis_rq_tvalid,
    input  wire                                          m_axis_rq_tready,
    output wire                                          m_axis_rq_tlast,
    output wire [AXIS_PCIE_RQ_USER_WIDTH-1:0]            m_axis_rq_tuser,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]               s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]               s_axis_cq_tkeep,
    input  wire                                          s_axis_cq_tvalid,
    output wire                                          s_axis_cq_tready,
    input  wire                                          s_axis_cq_tlast,
    input  wire [AXIS_PCIE_CQ_USER_WIDTH-1:0]            s_axis_cq_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]               m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]               m_axis_cc_tkeep,
    output wire                                          m_axis_cc_tvalid,
    input  wire                                          m_axis_cc_tready,
    output wire                                          m_axis_cc_tlast,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0]            m_axis_cc_tuser,

    input  wire [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_0,
    input  wire                                          s_axis_rq_seq_num_valid_0,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_1,
    input  wire                                          s_axis_rq_seq_num_valid_1,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_2,
    input  wire                                          s_axis_rq_seq_num_valid_2,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]                   s_axis_rq_seq_num_3,
    input  wire                                          s_axis_rq_seq_num_valid_3,

    output wire [9:0]                                    cfg_mgmt_addr,
    output wire [7:0]                                    cfg_mgmt_function_number,
    output wire                                          cfg_mgmt_write,
    output wire [31:0]                                   cfg_mgmt_write_data,
    output wire [3:0]                                    cfg_mgmt_byte_enable,
    output wire                                          cfg_mgmt_read,
    input  wire [31:0]                                   cfg_mgmt_read_data,
    input  wire                                          cfg_mgmt_read_write_done,

    input  wire [2:0]                                    cfg_max_payload,
    input  wire [2:0]                                    cfg_max_read_req,

    input  wire [7:0]                                    cfg_fc_ph,
    input  wire [11:0]                                   cfg_fc_pd,
    input  wire [7:0]                                    cfg_fc_nph,
    input  wire [11:0]                                   cfg_fc_npd,
    input  wire [7:0]                                    cfg_fc_cplh,
    input  wire [11:0]                                   cfg_fc_cpld,
    output wire [2:0]                                    cfg_fc_sel,

    input  wire [3:0]                                    cfg_interrupt_msi_enable,
    input  wire [7:0]                                    cfg_interrupt_msi_vf_enable,
    input  wire [11:0]                                   cfg_interrupt_msi_mmenable,
    input  wire                                          cfg_interrupt_msi_mask_update,
    input  wire [31:0]                                   cfg_interrupt_msi_data,
    output wire [3:0]                                    cfg_interrupt_msi_select,
    output wire [31:0]                                   cfg_interrupt_msi_int,
    output wire [31:0]                                   cfg_interrupt_msi_pending_status,
    output wire                                          cfg_interrupt_msi_pending_status_data_enable,
    output wire [3:0]                                    cfg_interrupt_msi_pending_status_function_num,
    input  wire                                          cfg_interrupt_msi_sent,
    input  wire                                          cfg_interrupt_msi_fail,
    input  wire [3:0]                                    cfg_interrupt_msix_enable,
    input  wire [3:0]                                    cfg_interrupt_msix_mask,
    input  wire [251:0]                                  cfg_interrupt_msix_vf_enable,
    input  wire [251:0]                                  cfg_interrupt_msix_vf_mask,
    output wire [63:0]                                   cfg_interrupt_msix_address,
    output wire [31:0]                                   cfg_interrupt_msix_data,
    output wire                                          cfg_interrupt_msix_int,
    output wire [1:0]                                    cfg_interrupt_msix_vec_pending,
    input  wire                                          cfg_interrupt_msix_vec_pending_status,
    input  wire                                          cfg_interrupt_msix_sent,
    input  wire                                          cfg_interrupt_msix_fail,
    output wire [2:0]                                    cfg_interrupt_msi_attr,
    output wire                                          cfg_interrupt_msi_tph_present,
    output wire [1:0]                                    cfg_interrupt_msi_tph_type,
    output wire [8:0]                                    cfg_interrupt_msi_tph_st_tag,
    output wire [7:0]                                    cfg_interrupt_msi_function_number,

    output wire [TLP_CPL_DATA_WIDTH-1:0]                 rx_req_tlp_data,
    output wire [TLP_CPL_STRB_WIDTH-1:0]                 rx_req_tlp_strb,
    output wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        rx_req_tlp_hdr,
    output wire [TLP_SEG_COUNT*3-1:0]                    rx_req_tlp_bar_id,
    output wire [TLP_SEG_COUNT*8-1:0]                    rx_req_tlp_func_num,
    output wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                      rx_req_tlp_eop,
    input  wire                                          rx_req_tlp_ready,

    output wire [TLP_DATA_WIDTH-1:0]                     rx_cpl_tlp_data,
    output wire [TLP_STRB_WIDTH-1:0]                     rx_cpl_tlp_strb,
    output wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        rx_cpl_tlp_hdr,
    output wire [TLP_SEG_COUNT*4-1:0]                    rx_cpl_tlp_error,
    output wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                      rx_cpl_tlp_eop,
    input  wire                                          rx_cpl_tlp_ready,

    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_rd_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_rd_req_tlp_seq,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_rd_req_tlp_eop,
    output wire                                          tx_rd_req_tlp_ready,

    output wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  m_axis_rd_req_tx_seq_num,
    output wire [TX_SEQ_NUM_COUNT-1:0]                   m_axis_rd_req_tx_seq_num_valid,

    input  wire [TLP_DATA_WIDTH-1:0]                     tx_wr_req_tlp_data,
    input  wire [TLP_STRB_WIDTH-1:0]                     tx_wr_req_tlp_strb,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_wr_req_tlp_hdr,
    input  wire [TLP_SEG_COUNT*TX_SEQ_NUM_WIDTH-1:0]     tx_wr_req_tlp_seq,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_wr_req_tlp_eop,
    output wire                                          tx_wr_req_tlp_ready,

    output wire [TX_SEQ_NUM_COUNT*TX_SEQ_NUM_WIDTH-1:0]  m_axis_wr_req_tx_seq_num,
    output wire [TX_SEQ_NUM_COUNT-1:0]                   m_axis_wr_req_tx_seq_num_valid,

    input  wire [TLP_CPL_DATA_WIDTH-1:0]                 tx_cpl_tlp_data,
    input  wire [TLP_CPL_STRB_WIDTH-1:0]                 tx_cpl_tlp_strb,
    input  wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]        tx_cpl_tlp_hdr,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_valid,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_sop,
    input  wire [TLP_SEG_COUNT-1:0]                      tx_cpl_tlp_eop,
    output wire                                          tx_cpl_tlp_ready,

    input  wire [31:0]                                   tx_msix_wr_req_tlp_data,
    input  wire                                          tx_msix_wr_req_tlp_strb,
    input  wire [TLP_HDR_WIDTH-1:0]                      tx_msix_wr_req_tlp_hdr,
    input  wire                                          tx_msix_wr_req_tlp_valid,
    input  wire                                          tx_msix_wr_req_tlp_sop,
    input  wire                                          tx_msix_wr_req_tlp_eop,
    output wire                                          tx_msix_wr_req_tlp_ready,

    output wire [7:0]                                    tx_fc_ph_av,
    output wire [11:0]                                   tx_fc_pd_av,
    output wire [7:0]                                    tx_fc_nph_av,
    output wire [11:0]                                   tx_fc_npd_av,
    output wire [7:0]                                    tx_fc_cplh_av,
    output wire [11:0]                                   tx_fc_cpld_av,

    output wire [F_COUNT-1:0]                            ext_tag_enable,
    output wire [F_COUNT*3-1:0]                          max_read_request_size,
    output wire [F_COUNT*3-1:0]                          max_payload_size,
    output wire [F_COUNT-1:0]                            msix_enable,
    output wire [F_COUNT-1:0]                            msix_mask,

    input  wire [MSI_COUNT-1:0]                          msi_irq,

    output wire                                          status_error_cq_slot_overflow,
    output wire                                          status_error_cq_leading_gap,
    output wire                                          status_error_cc_sop_align,
    output wire [1:0]                                    sts_cq_poisoned_tlp,
    output wire                                          sts_cq_poisoned_seen
);

localparam RQ_USER_WIDTH_INT = AXIS_PCIE_DATA_WIDTH >= 1024 ? 373 : 137;

localparam RQ_USER_PAD = AXIS_PCIE_RQ_USER_WIDTH - RQ_USER_WIDTH_INT;

localparam CQCC_GEARBOX = AXIS_PCIE_DATA_WIDTH >= 1024 ? 1 : 0;

localparam CQ_USER_WIDTH_GB = 231;
localparam CC_USER_WIDTH_GB = 81;

localparam CQ_USER_WIDTH_US = 183;
localparam CC_USER_WIDTH_US = 81;

localparam CQ_USER_WIDTH_NARROW = CQCC_GEARBOX ? CQ_USER_WIDTH_GB : AXIS_PCIE_CQ_USER_WIDTH;
localparam CC_USER_WIDTH_NARROW = CQCC_GEARBOX ? CC_USER_WIDTH_GB : AXIS_PCIE_CC_USER_WIDTH;

localparam CQ_POISON_LO = 229;

localparam CQ_POISON_AVAIL = (CQ_USER_WIDTH_NARROW > CQ_USER_WIDTH_US) &&
                             (CQ_USER_WIDTH_NARROW >= CQ_POISON_LO+2) ? 1 : 0;

localparam CPL_AXIS_KEEP_WIDTH = TLP_CPL_DATA_WIDTH/32;

initial begin
    case (AXIS_PCIE_DATA_WIDTH)
        512: begin
            if (TLP_CPL_DATA_WIDTH != 512) begin
                $error("Error: TLP_CPL_DATA_WIDTH must be 512 when the CPM5 interface is 512 bits (instance %m)");
                $finish;
            end
        end
        1024: begin
            if (TLP_CPL_DATA_WIDTH != 512) begin
                $error("Error: TLP_CPL_DATA_WIDTH must be 512 - pcie_us_if_{cq,cc} are unmodified 512-bit shims behind the gearbox (contract section 1) (instance %m)");
                $finish;
            end
            if (RC_FIFO_SEG_COUNT != 8 && RC_FIFO_SEG_COUNT != 4 && RC_FIFO_SEG_COUNT != 2) begin
                $error("Error: RC_FIFO_SEG_COUNT must be 8, 4 or 2 at 1024 bits (contract section 3.4) (instance %m)");
                $finish;
            end
        end
        default: begin
            $error("Error: AXIS_PCIE_DATA_WIDTH must be 512 or 1024 - use corundum's unmodified pcie_us_if for 64/128/256 (instance %m)");
            $finish;
        end
    endcase

    if (AXIS_PCIE_KEEP_WIDTH * 32 != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: PCIe interface requires dword (32-bit) granularity (instance %m)");
        $finish;
    end

    if (AXIS_PCIE_RQ_USER_WIDTH < RQ_USER_WIDTH_INT) begin
        $error("Error: AXIS_PCIE_RQ_USER_WIDTH (%0d) is narrower than what pcie_versal_if_rq emits (%0d) - the flavour step may only zero-extend (instance %m)", AXIS_PCIE_RQ_USER_WIDTH, RQ_USER_WIDTH_INT);
        $finish;
    end

    if (CQ_USER_WIDTH_NARROW < CQ_USER_WIDTH_US) begin
        $error("Error: resolved CQ tuser (%0d) is narrower than the unmodified pcie_us_if_cq requires (%0d) (instance %m)", CQ_USER_WIDTH_NARROW, CQ_USER_WIDTH_US);
        $finish;
    end
    if (CQ_USER_WIDTH_NARROW > CQ_USER_WIDTH_US && CQ_USER_WIDTH_NARROW < CQ_POISON_LO+2) begin
        $error("Error: resolved CQ tuser (%0d) is wider than the UltraScale+ layout (%0d) but too narrow to carry poisoned_tlp at [%0d:%0d] - refusing rather than reading the wrong bits (R-0) (instance %m)", CQ_USER_WIDTH_NARROW, CQ_USER_WIDTH_US, CQ_POISON_LO+1, CQ_POISON_LO);
        $finish;
    end

    if (CC_USER_WIDTH_NARROW != CC_USER_WIDTH_US) begin
        $error("Error: resolved CC tuser (%0d) must be %0d - the CC layout is identical on the CPM5 and UltraScale+ faces (instance %m)", CC_USER_WIDTH_NARROW, CC_USER_WIDTH_US);
        $finish;
    end

    if (TLP_SEG_COUNT != 1) begin
        $error("Error: TLP_SEG_COUNT must be 1 (V12) (instance %m)");
        $finish;
    end
    if (TLP_HDR_WIDTH != 128) begin
        $error("Error: TLP_HDR_WIDTH must be 128 (V12) (instance %m)");
        $finish;
    end
    if (TLP_DATA_WIDTH != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: requester generic width must equal the CPM5 width - pcie_versal_if_{rq,rc} both assert it (instance %m)");
        $finish;
    end
    if (TLP_STRB_WIDTH * 32 != TLP_DATA_WIDTH || TLP_CPL_STRB_WIDTH * 32 != TLP_CPL_DATA_WIDTH) begin
        $error("Error: generic TLP interfaces require dword granularity (instance %m)");
        $finish;
    end

    if (RQ_STRADDLE_ENC != 0 && RQ_STRADDLE_ENC != 1) begin
        $error("Error: RQ_STRADDLE_ENC must be 0 or 1 (instance %m)");
        $finish;
    end
    if (RC_SOP_COMPACT != 0 && RC_SOP_COMPACT != 1) begin
        $error("Error: RC_SOP_COMPACT must be 0 or 1 (instance %m)");
        $finish;
    end

    if (RC_SOP_COMPACT == 0 && RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) begin
        if (RC_FIFO_SEG_COUNT != AXIS_PCIE_DATA_WIDTH/128) begin
            $error("Error: with RC_SOP_COMPACT = 0, RC_FIFO_SEG_COUNT (%0d) must equal INT_TLP_SEG_COUNT (%0d) (contract section 3.4) (instance %m)", RC_FIFO_SEG_COUNT, AXIS_PCIE_DATA_WIDTH/128);
            $finish;
        end
    end

    $display("T36C_AGG_WITNESS instance=%m AXIS_PCIE_DATA_WIDTH=%0d RQ_USER=%0d RQ_USER_INT=%0d RQ_USER_PAD=%0d RC_USER=%0d CQ_USER=%0d CC_USER=%0d CQ_USER_NARROW=%0d CC_USER_NARROW=%0d CQ_USER_US=%0d CQCC_GEARBOX=%0d CQ_POISON_AVAIL=%0d TLP_DATA_WIDTH=%0d TLP_CPL_DATA_WIDTH=%0d TLP_SEG_COUNT=%0d TLP_HDR_WIDTH=%0d TX_SEQ_NUM_COUNT=%0d TX_SEQ_NUM_WIDTH=%0d RQ_STRADDLE=%0d RC_STRADDLE=%0d CQ_STRADDLE=%0d CC_STRADDLE=%0d RQ_STRADDLE_ENC=%0d RC_SOP_COMPACT=%0d RC_FIFO_SEG_COUNT=%0d CQ_SOP_PTR_DW=%0d CC_SOP_PTR_DW=%0d",
        AXIS_PCIE_DATA_WIDTH, AXIS_PCIE_RQ_USER_WIDTH, RQ_USER_WIDTH_INT, RQ_USER_PAD,
        AXIS_PCIE_RC_USER_WIDTH, AXIS_PCIE_CQ_USER_WIDTH, AXIS_PCIE_CC_USER_WIDTH,
        CQ_USER_WIDTH_NARROW, CC_USER_WIDTH_NARROW, CQ_USER_WIDTH_US,
        CQCC_GEARBOX, CQ_POISON_AVAIL,
        TLP_DATA_WIDTH, TLP_CPL_DATA_WIDTH, TLP_SEG_COUNT, TLP_HDR_WIDTH,
        TX_SEQ_NUM_COUNT, TX_SEQ_NUM_WIDTH, RQ_STRADDLE, RC_STRADDLE, CQ_STRADDLE, CC_STRADDLE,
        RQ_STRADDLE_ENC, RC_SOP_COMPACT, RC_FIFO_SEG_COUNT, CQ_SOP_PTR_DW, CC_SOP_PTR_DW);
end

pcie_versal_if_rc #(
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_RC_USER_WIDTH(AXIS_PCIE_RC_USER_WIDTH),
    .RC_STRADDLE(RC_STRADDLE),

    .RC_SOP_COMPACT(RC_SOP_COMPACT),
    .RC_FIFO_SEG_COUNT(RC_FIFO_SEG_COUNT),
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT)
)
pcie_versal_if_rc_inst
(
    .clk(clk),
    .rst(rst),

    .s_axis_rc_tdata(s_axis_rc_tdata),
    .s_axis_rc_tkeep(s_axis_rc_tkeep),
    .s_axis_rc_tvalid(s_axis_rc_tvalid),
    .s_axis_rc_tready(s_axis_rc_tready),
    .s_axis_rc_tlast(s_axis_rc_tlast),
    .s_axis_rc_tuser(s_axis_rc_tuser),

    .rx_cpl_tlp_data(rx_cpl_tlp_data),
    .rx_cpl_tlp_strb(rx_cpl_tlp_strb),
    .rx_cpl_tlp_hdr(rx_cpl_tlp_hdr),
    .rx_cpl_tlp_error(rx_cpl_tlp_error),
    .rx_cpl_tlp_valid(rx_cpl_tlp_valid),
    .rx_cpl_tlp_sop(rx_cpl_tlp_sop),
    .rx_cpl_tlp_eop(rx_cpl_tlp_eop),
    .rx_cpl_tlp_ready(rx_cpl_tlp_ready)
);

wire [RQ_USER_WIDTH_INT-1:0] m_axis_rq_tuser_int;

pcie_versal_if_rq #(
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),

    .AXIS_PCIE_RQ_USER_WIDTH(RQ_USER_WIDTH_INT),
    .RQ_STRADDLE(RQ_STRADDLE),
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),

    .RQ_STRADDLE_ENC(RQ_STRADDLE_ENC),
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT),
    .TX_SEQ_NUM_COUNT(TX_SEQ_NUM_COUNT),
    .TX_SEQ_NUM_WIDTH(TX_SEQ_NUM_WIDTH)
)
pcie_versal_if_rq_inst
(
    .clk(clk),
    .rst(rst),

    .m_axis_rq_tdata(m_axis_rq_tdata),
    .m_axis_rq_tkeep(m_axis_rq_tkeep),
    .m_axis_rq_tvalid(m_axis_rq_tvalid),
    .m_axis_rq_tready(m_axis_rq_tready),
    .m_axis_rq_tlast(m_axis_rq_tlast),
    .m_axis_rq_tuser(m_axis_rq_tuser_int),

    .s_axis_rq_seq_num_0(s_axis_rq_seq_num_0),
    .s_axis_rq_seq_num_valid_0(s_axis_rq_seq_num_valid_0),
    .s_axis_rq_seq_num_1(s_axis_rq_seq_num_1),
    .s_axis_rq_seq_num_valid_1(s_axis_rq_seq_num_valid_1),
    .s_axis_rq_seq_num_2(s_axis_rq_seq_num_2),
    .s_axis_rq_seq_num_valid_2(s_axis_rq_seq_num_valid_2),
    .s_axis_rq_seq_num_3(s_axis_rq_seq_num_3),
    .s_axis_rq_seq_num_valid_3(s_axis_rq_seq_num_valid_3),

    .tx_rd_req_tlp_hdr(tx_rd_req_tlp_hdr),
    .tx_rd_req_tlp_seq(tx_rd_req_tlp_seq),
    .tx_rd_req_tlp_valid(tx_rd_req_tlp_valid),
    .tx_rd_req_tlp_sop(tx_rd_req_tlp_sop),
    .tx_rd_req_tlp_eop(tx_rd_req_tlp_eop),
    .tx_rd_req_tlp_ready(tx_rd_req_tlp_ready),

    .m_axis_rd_req_tx_seq_num(m_axis_rd_req_tx_seq_num),
    .m_axis_rd_req_tx_seq_num_valid(m_axis_rd_req_tx_seq_num_valid),

    .tx_wr_req_tlp_data(tx_wr_req_tlp_data),
    .tx_wr_req_tlp_strb(tx_wr_req_tlp_strb),
    .tx_wr_req_tlp_hdr(tx_wr_req_tlp_hdr),
    .tx_wr_req_tlp_seq(tx_wr_req_tlp_seq),
    .tx_wr_req_tlp_valid(tx_wr_req_tlp_valid),
    .tx_wr_req_tlp_sop(tx_wr_req_tlp_sop),
    .tx_wr_req_tlp_eop(tx_wr_req_tlp_eop),
    .tx_wr_req_tlp_ready(tx_wr_req_tlp_ready),

    .m_axis_wr_req_tx_seq_num(m_axis_wr_req_tx_seq_num),
    .m_axis_wr_req_tx_seq_num_valid(m_axis_wr_req_tx_seq_num_valid),

    .tx_fc_ph_av(tx_fc_ph_av),
    .tx_fc_pd_av(tx_fc_pd_av),
    .tx_fc_nph_av(tx_fc_nph_av),
    .tx_fc_npd_av(tx_fc_npd_av),

    .max_payload_size(cfg_max_payload)
);

if (RQ_USER_PAD > 0) begin : gen_rq_tuser_cpm5_extend

    assign m_axis_rq_tuser = {{RQ_USER_PAD{1'b0}}, m_axis_rq_tuser_int};

end else begin : gen_rq_tuser_direct

    assign m_axis_rq_tuser = m_axis_rq_tuser_int;

end

wire [TLP_CPL_DATA_WIDTH-1:0]     axis_cq_tdata_cpl;
wire [CPL_AXIS_KEEP_WIDTH-1:0]    axis_cq_tkeep_cpl;
wire                              axis_cq_tvalid_cpl;
wire                              axis_cq_tready_cpl;
wire                              axis_cq_tlast_cpl;
wire [CQ_USER_WIDTH_NARROW-1:0]   axis_cq_tuser_narrow;

wire [TLP_CPL_DATA_WIDTH-1:0]     axis_cc_tdata_cpl;
wire [CPL_AXIS_KEEP_WIDTH-1:0]    axis_cc_tkeep_cpl;
wire                              axis_cc_tvalid_cpl;
wire                              axis_cc_tready_cpl;
wire                              axis_cc_tlast_cpl;
wire [CC_USER_WIDTH_NARROW-1:0]   axis_cc_tuser_narrow;

if (CQCC_GEARBOX) begin : gen_cqcc_gearbox

pcie_versal_if_cqcc_gearbox #(

    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_CQ_USER_WIDTH(AXIS_PCIE_CQ_USER_WIDTH),
    .AXIS_PCIE_CC_USER_WIDTH(AXIS_PCIE_CC_USER_WIDTH),

    .USER_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .USER_KEEP_WIDTH(CPL_AXIS_KEEP_WIDTH),
    .USER_CQ_USER_WIDTH(CQ_USER_WIDTH_GB),
    .USER_CC_USER_WIDTH(CC_USER_WIDTH_GB),

    .CQ_STRADDLE(CQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE),
    .CQ_SOP_PTR_DW(CQ_SOP_PTR_DW),
    .CC_SOP_PTR_DW(CC_SOP_PTR_DW)
)
pcie_versal_if_cqcc_gearbox_inst
(
    .clk(clk),
    .rst(rst),

    .s_axis_cq_tdata(s_axis_cq_tdata),
    .s_axis_cq_tkeep(s_axis_cq_tkeep),
    .s_axis_cq_tvalid(s_axis_cq_tvalid),
    .s_axis_cq_tready(s_axis_cq_tready),
    .s_axis_cq_tlast(s_axis_cq_tlast),
    .s_axis_cq_tuser(s_axis_cq_tuser),

    .m_axis_cq_tdata(axis_cq_tdata_cpl),
    .m_axis_cq_tkeep(axis_cq_tkeep_cpl),
    .m_axis_cq_tvalid(axis_cq_tvalid_cpl),
    .m_axis_cq_tready(axis_cq_tready_cpl),
    .m_axis_cq_tlast(axis_cq_tlast_cpl),
    .m_axis_cq_tuser(axis_cq_tuser_narrow),

    .s_axis_cc_tdata(axis_cc_tdata_cpl),
    .s_axis_cc_tkeep(axis_cc_tkeep_cpl),
    .s_axis_cc_tvalid(axis_cc_tvalid_cpl),
    .s_axis_cc_tready(axis_cc_tready_cpl),
    .s_axis_cc_tlast(axis_cc_tlast_cpl),
    .s_axis_cc_tuser(axis_cc_tuser_narrow),

    .m_axis_cc_tdata(m_axis_cc_tdata),
    .m_axis_cc_tkeep(m_axis_cc_tkeep),
    .m_axis_cc_tvalid(m_axis_cc_tvalid),
    .m_axis_cc_tready(m_axis_cc_tready),
    .m_axis_cc_tlast(m_axis_cc_tlast),
    .m_axis_cc_tuser(m_axis_cc_tuser),

    .status_error_cq_slot_overflow(status_error_cq_slot_overflow),
    .status_error_cq_leading_gap(status_error_cq_leading_gap),
    .status_error_cc_sop_align(status_error_cc_sop_align)
);

end else begin : gen_cqcc_direct

    assign axis_cq_tdata_cpl   = s_axis_cq_tdata;
    assign axis_cq_tkeep_cpl   = s_axis_cq_tkeep;
    assign axis_cq_tvalid_cpl  = s_axis_cq_tvalid;
    assign s_axis_cq_tready    = axis_cq_tready_cpl;
    assign axis_cq_tlast_cpl   = s_axis_cq_tlast;
    assign axis_cq_tuser_narrow = s_axis_cq_tuser;

    assign m_axis_cc_tdata     = axis_cc_tdata_cpl;
    assign m_axis_cc_tkeep     = axis_cc_tkeep_cpl;
    assign m_axis_cc_tvalid    = axis_cc_tvalid_cpl;
    assign axis_cc_tready_cpl  = m_axis_cc_tready;
    assign m_axis_cc_tlast     = axis_cc_tlast_cpl;
    assign m_axis_cc_tuser     = axis_cc_tuser_narrow;

    assign status_error_cq_slot_overflow = 1'b0;
    assign status_error_cq_leading_gap   = 1'b0;
    assign status_error_cc_sop_align     = 1'b0;

end

wire [CQ_USER_WIDTH_US-1:0] axis_cq_tuser_us;

if (CQ_POISON_AVAIL) begin : gen_cq_tuser_flavour_cpm5

    assign axis_cq_tuser_us = axis_cq_tuser_narrow[CQ_USER_WIDTH_US-1:0];

    logic [1:0] sts_cq_poisoned_tlp_reg  = 2'b00;
    logic     sts_cq_poisoned_seen_reg = 1'b0;

    assign sts_cq_poisoned_tlp  = sts_cq_poisoned_tlp_reg;
    assign sts_cq_poisoned_seen = sts_cq_poisoned_seen_reg;

    always_ff @(posedge clk) begin
        sts_cq_poisoned_tlp_reg <= axis_cq_tuser_narrow[CQ_POISON_LO +: 2];
        if (axis_cq_tuser_narrow[CQ_POISON_LO +: 2] != 2'b00) begin
            sts_cq_poisoned_seen_reg <= 1'b1;
        end

        if (rst) begin
            sts_cq_poisoned_tlp_reg  <= 2'b00;
            sts_cq_poisoned_seen_reg <= 1'b0;
        end
    end

end else begin : gen_cq_tuser_direct

    assign axis_cq_tuser_us = axis_cq_tuser_narrow;

    assign sts_cq_poisoned_tlp  = 2'b00;
    assign sts_cq_poisoned_seen = 1'b0;

end

pcie_us_if_cq #(
    .AXIS_PCIE_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(CPL_AXIS_KEEP_WIDTH),
    .AXIS_PCIE_CQ_USER_WIDTH(CQ_USER_WIDTH_US),
    .CQ_STRADDLE(CQ_STRADDLE),
    .TLP_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_CPL_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT)
)
pcie_us_if_cq_inst
(
    .clk(clk),
    .rst(rst),

    .s_axis_cq_tdata(axis_cq_tdata_cpl),
    .s_axis_cq_tkeep(axis_cq_tkeep_cpl),
    .s_axis_cq_tvalid(axis_cq_tvalid_cpl),
    .s_axis_cq_tready(axis_cq_tready_cpl),
    .s_axis_cq_tlast(axis_cq_tlast_cpl),
    .s_axis_cq_tuser(axis_cq_tuser_us),

    .rx_req_tlp_data(rx_req_tlp_data),
    .rx_req_tlp_strb(rx_req_tlp_strb),
    .rx_req_tlp_hdr(rx_req_tlp_hdr),
    .rx_req_tlp_bar_id(rx_req_tlp_bar_id),
    .rx_req_tlp_func_num(rx_req_tlp_func_num),
    .rx_req_tlp_valid(rx_req_tlp_valid),
    .rx_req_tlp_sop(rx_req_tlp_sop),
    .rx_req_tlp_eop(rx_req_tlp_eop),
    .rx_req_tlp_ready(rx_req_tlp_ready)
);

pcie_us_if_cc #(
    .AXIS_PCIE_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(CPL_AXIS_KEEP_WIDTH),
    .AXIS_PCIE_CC_USER_WIDTH(CC_USER_WIDTH_US),
    .CC_STRADDLE(CC_STRADDLE),
    .TLP_DATA_WIDTH(TLP_CPL_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_CPL_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .TLP_SEG_COUNT(TLP_SEG_COUNT)
)
pcie_us_if_cc_inst
(
    .clk(clk),
    .rst(rst),

    .m_axis_cc_tdata(axis_cc_tdata_cpl),
    .m_axis_cc_tkeep(axis_cc_tkeep_cpl),
    .m_axis_cc_tvalid(axis_cc_tvalid_cpl),
    .m_axis_cc_tready(axis_cc_tready_cpl),
    .m_axis_cc_tlast(axis_cc_tlast_cpl),
    .m_axis_cc_tuser(axis_cc_tuser_narrow),

    .tx_cpl_tlp_data(tx_cpl_tlp_data),
    .tx_cpl_tlp_strb(tx_cpl_tlp_strb),
    .tx_cpl_tlp_hdr(tx_cpl_tlp_hdr),
    .tx_cpl_tlp_valid(tx_cpl_tlp_valid),
    .tx_cpl_tlp_sop(tx_cpl_tlp_sop),
    .tx_cpl_tlp_eop(tx_cpl_tlp_eop),
    .tx_cpl_tlp_ready(tx_cpl_tlp_ready)
);

assign tx_fc_ph_av = cfg_fc_ph;
assign tx_fc_pd_av = cfg_fc_pd;
assign tx_fc_nph_av = cfg_fc_nph;
assign tx_fc_npd_av = cfg_fc_npd;
assign tx_fc_cplh_av = cfg_fc_cplh;
assign tx_fc_cpld_av = cfg_fc_cpld;

assign cfg_fc_sel = 3'b100;

if (READ_EXT_TAG_ENABLE || READ_MAX_READ_REQ_SIZE || READ_MAX_PAYLOAD_SIZE) begin : gen_cfg

    pcie_us_cfg #(
        .PF_COUNT(PF_COUNT),
        .VF_COUNT(VF_COUNT),
        .VF_OFFSET(VF_OFFSET),
        .F_COUNT(F_COUNT),
        .READ_EXT_TAG_ENABLE(READ_EXT_TAG_ENABLE),
        .READ_MAX_READ_REQ_SIZE(READ_MAX_READ_REQ_SIZE),
        .READ_MAX_PAYLOAD_SIZE(READ_MAX_PAYLOAD_SIZE),
        .PCIE_CAP_OFFSET(PCIE_CAP_OFFSET)
    )
    pcie_us_cfg_inst (
        .clk(clk),
        .rst(rst),

        .ext_tag_enable(ext_tag_enable),
        .max_read_request_size(max_read_request_size),
        .max_payload_size(max_payload_size),

        .cfg_mgmt_addr(cfg_mgmt_addr),
        .cfg_mgmt_function_number(cfg_mgmt_function_number),
        .cfg_mgmt_write(cfg_mgmt_write),
        .cfg_mgmt_write_data(cfg_mgmt_write_data),
        .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
        .cfg_mgmt_read(cfg_mgmt_read),
        .cfg_mgmt_read_data(cfg_mgmt_read_data),
        .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done)
    );

end else begin : gen_no_cfg

    assign ext_tag_enable = 0;
    assign max_read_request_size = 0;
    assign max_payload_size = 0;

    assign cfg_mgmt_addr = 0;
    assign cfg_mgmt_function_number = 0;
    assign cfg_mgmt_write = 0;
    assign cfg_mgmt_write_data = 0;
    assign cfg_mgmt_byte_enable = 0;
    assign cfg_mgmt_read = 0;

end

assign msix_enable = cfg_interrupt_msix_enable;
assign msix_mask = cfg_interrupt_msix_mask;

wire [7:0] cfg_interrupt_msi_function_number_msix;
wire [7:0] cfg_interrupt_msi_function_number_msi;

assign cfg_interrupt_msi_function_number = (MSI_ENABLE && (!MSIX_ENABLE || cfg_interrupt_msi_int)) ?
    cfg_interrupt_msi_function_number_msi : cfg_interrupt_msi_function_number_msix;

if (MSIX_ENABLE) begin : gen_msix

    logic cfg_interrupt_msix_int_reg = 1'b0;
    logic tx_msix_wr_req_tlp_ready_reg = 1'b0;

    logic msix_active_reg = 1'b0;

    assign tx_msix_wr_req_tlp_ready = tx_msix_wr_req_tlp_ready_reg;

    assign cfg_interrupt_msix_address = {tx_msix_wr_req_tlp_hdr[63:2], 2'b00};
    assign cfg_interrupt_msix_data = tx_msix_wr_req_tlp_data;
    assign cfg_interrupt_msix_int = cfg_interrupt_msix_int_reg;
    assign cfg_interrupt_msi_function_number_msix = tx_msix_wr_req_tlp_hdr[87:80];
    assign cfg_interrupt_msix_vec_pending = 0;

    always_ff @(posedge clk) begin
        cfg_interrupt_msix_int_reg <= 1'b0;
        tx_msix_wr_req_tlp_ready_reg <= 1'b0;

        if (!msix_active_reg) begin
            if (tx_msix_wr_req_tlp_valid && !tx_msix_wr_req_tlp_ready) begin
                cfg_interrupt_msix_int_reg <= 1'b1;
                msix_active_reg <= 1'b1;
            end
        end else begin
            if (cfg_interrupt_msix_sent || cfg_interrupt_msix_fail) begin
                tx_msix_wr_req_tlp_ready_reg <= tx_msix_wr_req_tlp_valid;
                msix_active_reg <= 1'b0;
            end
        end

        if (rst) begin
            cfg_interrupt_msix_int_reg <= 1'b0;
            tx_msix_wr_req_tlp_ready_reg <= 1'b0;
            msix_active_reg <= 1'b0;
        end
    end

end else begin : gen_no_msix

    assign tx_msix_wr_req_tlp_ready = 0;

    assign cfg_interrupt_msix_address = 0;
    assign cfg_interrupt_msix_data = 0;
    assign cfg_interrupt_msix_int = 0;
    assign cfg_interrupt_msix_vec_pending = 0;

    assign cfg_interrupt_msi_function_number_msix = 0;

end

if (MSI_ENABLE) begin : gen_msi

    pcie_us_msi #(
        .MSI_COUNT(MSI_COUNT)
    )
    pcie_us_msi_inst (
        .clk(clk),
        .rst(rst),

        .msi_irq(msi_irq),

        .cfg_interrupt_msi_enable(cfg_interrupt_msi_enable),
        .cfg_interrupt_msi_vf_enable(cfg_interrupt_msi_vf_enable),
        .cfg_interrupt_msi_mmenable(cfg_interrupt_msi_mmenable),
        .cfg_interrupt_msi_mask_update(cfg_interrupt_msi_mask_update),
        .cfg_interrupt_msi_data(cfg_interrupt_msi_data),
        .cfg_interrupt_msi_select(cfg_interrupt_msi_select),
        .cfg_interrupt_msi_int(cfg_interrupt_msi_int),
        .cfg_interrupt_msi_pending_status(cfg_interrupt_msi_pending_status),
        .cfg_interrupt_msi_pending_status_data_enable(cfg_interrupt_msi_pending_status_data_enable),
        .cfg_interrupt_msi_pending_status_function_num(cfg_interrupt_msi_pending_status_function_num),
        .cfg_interrupt_msi_sent(cfg_interrupt_msi_sent),
        .cfg_interrupt_msi_fail(cfg_interrupt_msi_fail),
        .cfg_interrupt_msi_attr(cfg_interrupt_msi_attr),
        .cfg_interrupt_msi_tph_present(cfg_interrupt_msi_tph_present),
        .cfg_interrupt_msi_tph_type(cfg_interrupt_msi_tph_type),
        .cfg_interrupt_msi_tph_st_tag(cfg_interrupt_msi_tph_st_tag),
        .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number_msi)
    );

end else begin : gen_no_msi

    assign cfg_interrupt_msi_select = 0;
    assign cfg_interrupt_msi_int = 0;
    assign cfg_interrupt_msi_pending_status = 0;
    assign cfg_interrupt_msi_pending_status_data_enable = 0;
    assign cfg_interrupt_msi_pending_status_function_num = 0;
    assign cfg_interrupt_msi_attr = 0;
    assign cfg_interrupt_msi_tph_present = 0;
    assign cfg_interrupt_msi_tph_type = 0;
    assign cfg_interrupt_msi_tph_st_tag = 0;

    assign cfg_interrupt_msi_function_number_msi = 0;

end

endmodule

`resetall
