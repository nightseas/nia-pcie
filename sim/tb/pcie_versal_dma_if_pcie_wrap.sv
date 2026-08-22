// ---------------------------------------------------------------------------
// File        : pcie_versal_dma_if_pcie_wrap.sv
// Description : Testbench wrapper presenting a Versal shaped boundary over the
//               PCIe library's DMA interface module, so that engine is
//               exercised through pcie_versal_adapt without being edited.
// Author      : Xiaohai Li <haixiaolee@gmail.com>
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_dma_if_pcie_wrap #
(
    parameter AXIS_PCIE_DATA_WIDTH    = 512,
    parameter AXIS_PCIE_KEEP_WIDTH    = (AXIS_PCIE_DATA_WIDTH/32),

    parameter AXIS_PCIE_RC_USER_WIDTH = 161,
    parameter AXIS_PCIE_RQ_USER_WIDTH = 137,
    parameter AXIS_PCIE_CQ_USER_WIDTH = 183,
    parameter AXIS_PCIE_CC_USER_WIDTH = 81,

    parameter CPM5_RQ_USER_WIDTH      = 183,
    parameter CPM5_CQ_USER_WIDTH      = 231,

    parameter RQ_SEQ_NUM_WIDTH        = 6,
    parameter RQ_SEQ_NUM_ENABLE       = 1,
    parameter RAM_SEL_WIDTH           = 2,
    parameter RAM_ADDR_WIDTH          = 16,
    parameter SEG_COUNT               = 8,
    parameter SEG_DATA_WIDTH          = 128,
    parameter SEG_BE_WIDTH            = 16,
    parameter SEG_ADDR_WIDTH          = 9,
    parameter PCIE_ADDR_WIDTH         = 64,
    parameter PCIE_TAG_COUNT          = 256,
    parameter LEN_WIDTH               = 20,
    parameter TAG_WIDTH               = 8,
    parameter READ_OP_TABLE_SIZE      = 256,
    parameter READ_TX_LIMIT           = 32,
    parameter READ_TX_FC_ENABLE       = 1,
    parameter WRITE_OP_TABLE_SIZE     = 32,
    parameter WRITE_TX_LIMIT          = 32,
    parameter WRITE_TX_FC_ENABLE      = 1
)
(
    input  wire                                 clk,
    input  wire                                 rst,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]      s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]      s_axis_rc_tkeep,
    input  wire                                 s_axis_rc_tvalid,
    output wire                                 s_axis_rc_tready,
    input  wire                                 s_axis_rc_tlast,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0]   s_axis_rc_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]      m_axis_rq_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]      m_axis_rq_tkeep,
    output wire                                 m_axis_rq_tvalid,
    input  wire                                 m_axis_rq_tready,
    output wire                                 m_axis_rq_tlast,
    output wire [CPM5_RQ_USER_WIDTH-1:0]        m_axis_rq_tuser,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]      s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]      s_axis_cq_tkeep,
    input  wire                                 s_axis_cq_tvalid,
    output wire                                 s_axis_cq_tready,
    input  wire                                 s_axis_cq_tlast,
    input  wire [CPM5_CQ_USER_WIDTH-1:0]        s_axis_cq_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]      m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]      m_axis_cc_tkeep,
    output wire                                 m_axis_cc_tvalid,
    input  wire                                 m_axis_cc_tready,
    output wire                                 m_axis_cc_tlast,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0]   m_axis_cc_tuser,

    input  wire [RQ_SEQ_NUM_WIDTH-1:0]          s_axis_rq_seq_num_0,
    input  wire                                 s_axis_rq_seq_num_valid_0,
    input  wire [RQ_SEQ_NUM_WIDTH-1:0]          s_axis_rq_seq_num_1,
    input  wire                                 s_axis_rq_seq_num_valid_1,

    input  wire [7:0]                           pcie_tx_fc_nph_av,
    input  wire [7:0]                           pcie_tx_fc_ph_av,
    input  wire [11:0]                          pcie_tx_fc_pd_av,

    input  wire [PCIE_ADDR_WIDTH-1:0]           s_axis_read_desc_pcie_addr,
    input  wire [RAM_SEL_WIDTH-1:0]             s_axis_read_desc_ram_sel,
    input  wire [RAM_ADDR_WIDTH-1:0]            s_axis_read_desc_ram_addr,
    input  wire [LEN_WIDTH-1:0]                 s_axis_read_desc_len,
    input  wire [TAG_WIDTH-1:0]                 s_axis_read_desc_tag,
    input  wire                                 s_axis_read_desc_valid,
    output wire                                 s_axis_read_desc_ready,

    output wire [TAG_WIDTH-1:0]                 m_axis_read_desc_status_tag,
    output wire [3:0]                           m_axis_read_desc_status_error,
    output wire                                 m_axis_read_desc_status_valid,

    input  wire [PCIE_ADDR_WIDTH-1:0]           s_axis_write_desc_pcie_addr,
    input  wire [RAM_SEL_WIDTH-1:0]             s_axis_write_desc_ram_sel,
    input  wire [RAM_ADDR_WIDTH-1:0]            s_axis_write_desc_ram_addr,
    input  wire [LEN_WIDTH-1:0]                 s_axis_write_desc_len,
    input  wire [TAG_WIDTH-1:0]                 s_axis_write_desc_tag,
    input  wire                                 s_axis_write_desc_valid,
    output wire                                 s_axis_write_desc_ready,

    output wire [TAG_WIDTH-1:0]                 m_axis_write_desc_status_tag,
    output wire [3:0]                           m_axis_write_desc_status_error,
    output wire                                 m_axis_write_desc_status_valid,

    output wire [SEG_COUNT*RAM_SEL_WIDTH-1:0]   ram_wr_cmd_sel,
    output wire [SEG_COUNT*SEG_BE_WIDTH-1:0]    ram_wr_cmd_be,
    output wire [SEG_COUNT*SEG_ADDR_WIDTH-1:0]  ram_wr_cmd_addr,
    output wire [SEG_COUNT*SEG_DATA_WIDTH-1:0]  ram_wr_cmd_data,
    output wire [SEG_COUNT-1:0]                 ram_wr_cmd_valid,
    input  wire [SEG_COUNT-1:0]                 ram_wr_cmd_ready,
    input  wire [SEG_COUNT-1:0]                 ram_wr_done,
    output wire [SEG_COUNT*RAM_SEL_WIDTH-1:0]   ram_rd_cmd_sel,
    output wire [SEG_COUNT*SEG_ADDR_WIDTH-1:0]  ram_rd_cmd_addr,
    output wire [SEG_COUNT-1:0]                 ram_rd_cmd_valid,
    input  wire [SEG_COUNT-1:0]                 ram_rd_cmd_ready,
    input  wire [SEG_COUNT*SEG_DATA_WIDTH-1:0]  ram_rd_resp_data,
    input  wire [SEG_COUNT-1:0]                 ram_rd_resp_valid,
    output wire [SEG_COUNT-1:0]                 ram_rd_resp_ready,

    input  wire                                 read_enable,
    input  wire                                 write_enable,
    input  wire                                 ext_tag_enable,
    input  wire [15:0]                          requester_id,
    input  wire                                 requester_id_enable,
    input  wire [2:0]                           max_read_request_size,
    input  wire [2:0]                           max_payload_size,

    output wire                                 status_rd_busy,
    output wire                                 status_wr_busy,
    output wire                                 status_error_cor,
    output wire                                 status_error_uncor,

    output wire [1:0]                           sts_cq_poisoned_tlp,
    output wire                                 sts_cq_poisoned_seen
);

wire [AXIS_PCIE_DATA_WIDTH-1:0]    us_rq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    us_rq_tkeep;
wire                               us_rq_tvalid;
wire                               us_rq_tready;
wire                               us_rq_tlast;
wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] us_rq_tuser;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    us_rc_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    us_rc_tkeep;
wire                               us_rc_tvalid;
wire                               us_rc_tready;
wire                               us_rc_tlast;
wire [AXIS_PCIE_RC_USER_WIDTH-1:0] us_rc_tuser;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    us_cq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    us_cq_tkeep;
wire                               us_cq_tvalid;
wire                               us_cq_tlast;
wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] us_cq_tuser;

wire                               us_cc_tready;

pcie_versal_adapt #(
    .DATA_W(AXIS_PCIE_DATA_WIDTH),
    .KEEP_W(AXIS_PCIE_KEEP_WIDTH),
    .CPM5_RQ_USER_W(CPM5_RQ_USER_WIDTH),
    .CPM5_CQ_USER_W(CPM5_CQ_USER_WIDTH),
    .US_RQ_USER_W(AXIS_PCIE_RQ_USER_WIDTH),
    .US_CQ_USER_W(AXIS_PCIE_CQ_USER_WIDTH),
    .RC_USER_W(AXIS_PCIE_RC_USER_WIDTH),
    .CC_USER_W(AXIS_PCIE_CC_USER_WIDTH)
)
adapt_inst (
    .clk(clk),
    .rst(rst),

    .us_rq_tdata(us_rq_tdata),
    .us_rq_tkeep(us_rq_tkeep),
    .us_rq_tvalid(us_rq_tvalid),
    .us_rq_tready(us_rq_tready),
    .us_rq_tlast(us_rq_tlast),
    .us_rq_tuser(us_rq_tuser),
    .cpm_rq_tdata(m_axis_rq_tdata),
    .cpm_rq_tkeep(m_axis_rq_tkeep),
    .cpm_rq_tvalid(m_axis_rq_tvalid),
    .cpm_rq_tready(m_axis_rq_tready),
    .cpm_rq_tlast(m_axis_rq_tlast),
    .cpm_rq_tuser(m_axis_rq_tuser),

    .cpm_rc_tdata(s_axis_rc_tdata),
    .cpm_rc_tkeep(s_axis_rc_tkeep),
    .cpm_rc_tvalid(s_axis_rc_tvalid),
    .cpm_rc_tready(s_axis_rc_tready),
    .cpm_rc_tlast(s_axis_rc_tlast),
    .cpm_rc_tuser(s_axis_rc_tuser),
    .us_rc_tdata(us_rc_tdata),
    .us_rc_tkeep(us_rc_tkeep),
    .us_rc_tvalid(us_rc_tvalid),
    .us_rc_tready(us_rc_tready),
    .us_rc_tlast(us_rc_tlast),
    .us_rc_tuser(us_rc_tuser),

    .cpm_cq_tdata(s_axis_cq_tdata),
    .cpm_cq_tkeep(s_axis_cq_tkeep),
    .cpm_cq_tvalid(s_axis_cq_tvalid),
    .cpm_cq_tready(s_axis_cq_tready),
    .cpm_cq_tlast(s_axis_cq_tlast),
    .cpm_cq_tuser(s_axis_cq_tuser),
    .us_cq_tdata(us_cq_tdata),
    .us_cq_tkeep(us_cq_tkeep),
    .us_cq_tvalid(us_cq_tvalid),
    .us_cq_tready(1'b1),
    .us_cq_tlast(us_cq_tlast),
    .us_cq_tuser(us_cq_tuser),

    .us_cc_tdata({AXIS_PCIE_DATA_WIDTH{1'b0}}),
    .us_cc_tkeep({AXIS_PCIE_KEEP_WIDTH{1'b0}}),
    .us_cc_tvalid(1'b0),
    .us_cc_tready(us_cc_tready),
    .us_cc_tlast(1'b0),
    .us_cc_tuser({AXIS_PCIE_CC_USER_WIDTH{1'b0}}),
    .cpm_cc_tdata(m_axis_cc_tdata),
    .cpm_cc_tkeep(m_axis_cc_tkeep),
    .cpm_cc_tvalid(m_axis_cc_tvalid),
    .cpm_cc_tready(m_axis_cc_tready),
    .cpm_cc_tlast(m_axis_cc_tlast),
    .cpm_cc_tuser(m_axis_cc_tuser),

    .sts_cq_poisoned_tlp(sts_cq_poisoned_tlp),
    .sts_cq_poisoned_seen(sts_cq_poisoned_seen)
);

dma_if_pcie_us #(
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_RC_USER_WIDTH(AXIS_PCIE_RC_USER_WIDTH),
    .AXIS_PCIE_RQ_USER_WIDTH(AXIS_PCIE_RQ_USER_WIDTH),
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),
    .RQ_SEQ_NUM_ENABLE(RQ_SEQ_NUM_ENABLE),
    .RAM_SEL_WIDTH(RAM_SEL_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .SEG_COUNT(SEG_COUNT),
    .SEG_DATA_WIDTH(SEG_DATA_WIDTH),
    .SEG_BE_WIDTH(SEG_BE_WIDTH),
    .SEG_ADDR_WIDTH(SEG_ADDR_WIDTH),
    .PCIE_ADDR_WIDTH(PCIE_ADDR_WIDTH),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),
    .LEN_WIDTH(LEN_WIDTH),
    .TAG_WIDTH(TAG_WIDTH),
    .READ_OP_TABLE_SIZE(READ_OP_TABLE_SIZE),
    .READ_TX_LIMIT(READ_TX_LIMIT),
    .READ_TX_FC_ENABLE(READ_TX_FC_ENABLE),
    .WRITE_OP_TABLE_SIZE(WRITE_OP_TABLE_SIZE),
    .WRITE_TX_LIMIT(WRITE_TX_LIMIT),
    .WRITE_TX_FC_ENABLE(WRITE_TX_FC_ENABLE)
)
dma_if_pcie_us_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_rc_tdata(us_rc_tdata),
    .s_axis_rc_tkeep(us_rc_tkeep),
    .s_axis_rc_tvalid(us_rc_tvalid),
    .s_axis_rc_tready(us_rc_tready),
    .s_axis_rc_tlast(us_rc_tlast),
    .s_axis_rc_tuser(us_rc_tuser),

    .m_axis_rq_tdata(us_rq_tdata),
    .m_axis_rq_tkeep(us_rq_tkeep),
    .m_axis_rq_tvalid(us_rq_tvalid),
    .m_axis_rq_tready(us_rq_tready),
    .m_axis_rq_tlast(us_rq_tlast),
    .m_axis_rq_tuser(us_rq_tuser),

    .s_axis_rq_seq_num_0(s_axis_rq_seq_num_0),
    .s_axis_rq_seq_num_valid_0(s_axis_rq_seq_num_valid_0),
    .s_axis_rq_seq_num_1(s_axis_rq_seq_num_1),
    .s_axis_rq_seq_num_valid_1(s_axis_rq_seq_num_valid_1),

    .pcie_tx_fc_nph_av(pcie_tx_fc_nph_av),
    .pcie_tx_fc_ph_av(pcie_tx_fc_ph_av),
    .pcie_tx_fc_pd_av(pcie_tx_fc_pd_av),

    .s_axis_read_desc_pcie_addr(s_axis_read_desc_pcie_addr),
    .s_axis_read_desc_ram_sel(s_axis_read_desc_ram_sel),
    .s_axis_read_desc_ram_addr(s_axis_read_desc_ram_addr),
    .s_axis_read_desc_len(s_axis_read_desc_len),
    .s_axis_read_desc_tag(s_axis_read_desc_tag),
    .s_axis_read_desc_valid(s_axis_read_desc_valid),
    .s_axis_read_desc_ready(s_axis_read_desc_ready),

    .m_axis_read_desc_status_tag(m_axis_read_desc_status_tag),
    .m_axis_read_desc_status_error(m_axis_read_desc_status_error),
    .m_axis_read_desc_status_valid(m_axis_read_desc_status_valid),

    .s_axis_write_desc_pcie_addr(s_axis_write_desc_pcie_addr),
    .s_axis_write_desc_ram_sel(s_axis_write_desc_ram_sel),
    .s_axis_write_desc_ram_addr(s_axis_write_desc_ram_addr),
    .s_axis_write_desc_len(s_axis_write_desc_len),
    .s_axis_write_desc_tag(s_axis_write_desc_tag),
    .s_axis_write_desc_valid(s_axis_write_desc_valid),
    .s_axis_write_desc_ready(s_axis_write_desc_ready),

    .m_axis_write_desc_status_tag(m_axis_write_desc_status_tag),
    .m_axis_write_desc_status_error(m_axis_write_desc_status_error),
    .m_axis_write_desc_status_valid(m_axis_write_desc_status_valid),

    .ram_wr_cmd_sel(ram_wr_cmd_sel),
    .ram_wr_cmd_be(ram_wr_cmd_be),
    .ram_wr_cmd_addr(ram_wr_cmd_addr),
    .ram_wr_cmd_data(ram_wr_cmd_data),
    .ram_wr_cmd_valid(ram_wr_cmd_valid),
    .ram_wr_cmd_ready(ram_wr_cmd_ready),
    .ram_wr_done(ram_wr_done),
    .ram_rd_cmd_sel(ram_rd_cmd_sel),
    .ram_rd_cmd_addr(ram_rd_cmd_addr),
    .ram_rd_cmd_valid(ram_rd_cmd_valid),
    .ram_rd_cmd_ready(ram_rd_cmd_ready),
    .ram_rd_resp_data(ram_rd_resp_data),
    .ram_rd_resp_valid(ram_rd_resp_valid),
    .ram_rd_resp_ready(ram_rd_resp_ready),

    .read_enable(read_enable),
    .write_enable(write_enable),
    .ext_tag_enable(ext_tag_enable),
    .requester_id(requester_id),
    .requester_id_enable(requester_id_enable),
    .max_read_request_size(max_read_request_size),
    .max_payload_size(max_payload_size),

    .status_rd_busy(status_rd_busy),
    .status_wr_busy(status_wr_busy),
    .status_error_cor(status_error_cor),
    .status_error_uncor(status_error_uncor)
);

wire _unused_ok = &{1'b0, us_cq_tdata, us_cq_tkeep, us_cq_tvalid, us_cq_tlast, us_cq_tuser,
                    us_cc_tready, 1'b0};

endmodule

`resetall
