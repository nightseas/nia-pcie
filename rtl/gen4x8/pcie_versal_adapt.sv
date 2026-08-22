// ---------------------------------------------------------------------------
// File        : pcie_versal_adapt.sv
// Description : Adapts CPM5 in PCIE mode to a PCIe DMA library that expects the
//               UltraScale+ integrated block interface: RQ tuser 137 to 183, CQ
//               231 to 183 with poisoned_tlp surfaced. Combinational.
// Author      : Xiaohai Li <haixiaolee@gmail.com>
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_adapt #
(
    parameter DATA_W         = 512,
    parameter KEEP_W         = DATA_W/32,

    parameter CPM5_RQ_USER_W = 183,
    parameter CPM5_CQ_USER_W = 231,

    parameter US_RQ_USER_W   = 137,
    parameter US_CQ_USER_W   = 183,

    parameter RC_USER_W      = 161,
    parameter CC_USER_W      = 81
)
(
    input  wire                        clk,
    input  wire                        rst,

    input  wire [DATA_W-1:0]           us_rq_tdata,
    input  wire [KEEP_W-1:0]           us_rq_tkeep,
    input  wire                        us_rq_tvalid,
    output wire                        us_rq_tready,
    input  wire                        us_rq_tlast,
    input  wire [US_RQ_USER_W-1:0]     us_rq_tuser,

    output wire [DATA_W-1:0]           cpm_rq_tdata,
    output wire [KEEP_W-1:0]           cpm_rq_tkeep,
    output wire                        cpm_rq_tvalid,
    input  wire                        cpm_rq_tready,
    output wire                        cpm_rq_tlast,
    output wire [CPM5_RQ_USER_W-1:0]   cpm_rq_tuser,

    input  wire [DATA_W-1:0]           cpm_rc_tdata,
    input  wire [KEEP_W-1:0]           cpm_rc_tkeep,
    input  wire                        cpm_rc_tvalid,
    output wire                        cpm_rc_tready,
    input  wire                        cpm_rc_tlast,
    input  wire [RC_USER_W-1:0]        cpm_rc_tuser,

    output wire [DATA_W-1:0]           us_rc_tdata,
    output wire [KEEP_W-1:0]           us_rc_tkeep,
    output wire                        us_rc_tvalid,
    input  wire                        us_rc_tready,
    output wire                        us_rc_tlast,
    output wire [RC_USER_W-1:0]        us_rc_tuser,

    input  wire [DATA_W-1:0]           cpm_cq_tdata,
    input  wire [KEEP_W-1:0]           cpm_cq_tkeep,
    input  wire                        cpm_cq_tvalid,
    output wire                        cpm_cq_tready,
    input  wire                        cpm_cq_tlast,
    input  wire [CPM5_CQ_USER_W-1:0]   cpm_cq_tuser,

    output wire [DATA_W-1:0]           us_cq_tdata,
    output wire [KEEP_W-1:0]           us_cq_tkeep,
    output wire                        us_cq_tvalid,
    input  wire                        us_cq_tready,
    output wire                        us_cq_tlast,
    output wire [US_CQ_USER_W-1:0]     us_cq_tuser,

    input  wire [DATA_W-1:0]           us_cc_tdata,
    input  wire [KEEP_W-1:0]           us_cc_tkeep,
    input  wire                        us_cc_tvalid,
    output wire                        us_cc_tready,
    input  wire                        us_cc_tlast,
    input  wire [CC_USER_W-1:0]        us_cc_tuser,

    output wire [DATA_W-1:0]           cpm_cc_tdata,
    output wire [KEEP_W-1:0]           cpm_cc_tkeep,
    output wire                        cpm_cc_tvalid,
    input  wire                        cpm_cc_tready,
    output wire                        cpm_cc_tlast,
    output wire [CC_USER_W-1:0]        cpm_cc_tuser,

    output wire [1:0]                  sts_cq_poisoned_tlp,
    output wire                        sts_cq_poisoned_seen
);

localparam CQ_POISON_LO = 229;

initial begin
    if (DATA_W != 512) begin
        $error("Error: pcie_versal_adapt supports DATA_W = 512 only; the CPM5 field maps are 512-bit maps (instance %m)");
        $finish;
    end
    if (KEEP_W * 32 != DATA_W) begin
        $error("Error: KEEP_W must be DATA_W/32 (instance %m)");
        $finish;
    end
    if (US_RQ_USER_W != 137) begin
        $error("Error: US RQ tuser width must be 137 - both libraries assert it (instance %m)");
        $finish;
    end
    if (US_CQ_USER_W != 183) begin
        $error("Error: US CQ tuser width must be 183 (instance %m)");
        $finish;
    end
    if (RC_USER_W != 161) begin
        $error("Error: RC tuser width must be 161 on both faces (instance %m)");
        $finish;
    end
    if (CC_USER_W != 81) begin
        $error("Error: CC tuser width must be 81 on both faces (instance %m)");
        $finish;
    end
    if (CPM5_RQ_USER_W < US_RQ_USER_W) begin
        $error("Error: CPM5 RQ tuser (%0d) must be >= US RQ tuser (%0d) (instance %m)", CPM5_RQ_USER_W, US_RQ_USER_W);
        $finish;
    end
    if (CPM5_CQ_USER_W < CQ_POISON_LO+2) begin
        $error("Error: CPM5 CQ tuser (%0d) too narrow to carry poisoned_tlp at [%0d:%0d] (instance %m)", CPM5_CQ_USER_W, CQ_POISON_LO+1, CQ_POISON_LO);
        $finish;
    end
end

assign cpm_rq_tdata  = us_rq_tdata;
assign cpm_rq_tkeep  = us_rq_tkeep;
assign cpm_rq_tvalid = us_rq_tvalid;
assign cpm_rq_tlast  = us_rq_tlast;
assign us_rq_tready  = cpm_rq_tready;

assign cpm_rq_tuser  = {{(CPM5_RQ_USER_W-US_RQ_USER_W){1'b0}}, us_rq_tuser};

assign us_rc_tdata   = cpm_rc_tdata;
assign us_rc_tkeep   = cpm_rc_tkeep;
assign us_rc_tvalid  = cpm_rc_tvalid;
assign us_rc_tlast   = cpm_rc_tlast;
assign us_rc_tuser   = cpm_rc_tuser;
assign cpm_rc_tready = us_rc_tready;

assign us_cq_tdata   = cpm_cq_tdata;
assign us_cq_tkeep   = cpm_cq_tkeep;
assign us_cq_tvalid  = cpm_cq_tvalid;
assign us_cq_tlast   = cpm_cq_tlast;
assign us_cq_tuser   = cpm_cq_tuser[US_CQ_USER_W-1:0];
assign cpm_cq_tready = us_cq_tready;

assign cpm_cc_tdata  = us_cc_tdata;
assign cpm_cc_tkeep  = us_cc_tkeep;
assign cpm_cc_tvalid = us_cc_tvalid;
assign cpm_cc_tlast  = us_cc_tlast;
assign cpm_cc_tuser  = us_cc_tuser;
assign us_cc_tready  = cpm_cc_tready;

logic [1:0] sts_cq_poisoned_tlp_reg  = 2'b00;
logic     sts_cq_poisoned_seen_reg = 1'b0;

assign sts_cq_poisoned_tlp  = sts_cq_poisoned_tlp_reg;
assign sts_cq_poisoned_seen = sts_cq_poisoned_seen_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        sts_cq_poisoned_tlp_reg  <= 2'b00;
        sts_cq_poisoned_seen_reg <= 1'b0;
    end else begin
        sts_cq_poisoned_tlp_reg <= cpm_cq_tuser[CQ_POISON_LO +: 2];
        if (cpm_cq_tuser[CQ_POISON_LO +: 2] != 2'b00) begin
            sts_cq_poisoned_seen_reg <= 1'b1;
        end
    end
end

endmodule

`resetall
