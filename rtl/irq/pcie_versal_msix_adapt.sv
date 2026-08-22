// ---------------------------------------------------------------------------
// File        : pcie_versal_msix_adapt.sv
// Description : CPM5 to MSI-X adaptor
// Author      : Xiaohai Li <haixiaolee@gmail.com>
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_msix_adapt #
(
    parameter IRQ_INDEX_WIDTH = 5,

    parameter MSIX_VECTOR_COUNT = 8,

    parameter FUNCTION_NUMBER = 0,

    parameter FAIL_RETRY_LIMIT = 8,

    parameter STS_COUNT_WIDTH = 16
)
(
    input  wire                        clk,
    input  wire                        rst,

    input  wire [IRQ_INDEX_WIDTH-1:0]  irq_index,
    input  wire                        irq_valid,
    output wire                        irq_ready,

    output wire [31:0]                 cfg_msix_mint_vector,
    output wire                        cfg_msix_int_vector,
    output wire [15:0]                 cfg_msix_function_number,
    output wire [1:0]                  cfg_msix_vec_pending,
    input  wire                        cfg_msix_enable,
    input  wire                        cfg_msix_mask,
    input  wire                        cfg_msix_sent,
    input  wire                        cfg_msix_fail,
    input  wire                        cfg_msix_vec_pending_status,

    output wire [STS_COUNT_WIDTH-1:0]  sts_irq_sent_count,
    output wire [STS_COUNT_WIDTH-1:0]  sts_irq_fail_count,
    output wire [STS_COUNT_WIDTH-1:0]  sts_irq_drop_disabled,
    output wire [STS_COUNT_WIDTH-1:0]  sts_irq_drop_oor,
    output wire [STS_COUNT_WIDTH-1:0]  sts_irq_drop_retry,
    output wire                        sts_irq_masked_seen,
    output wire                        sts_busy
);

initial begin
    if (MSIX_VECTOR_COUNT < 1) begin
        $error("pcie_versal_msix_adapt: MSIX_VECTOR_COUNT must be >= 1");
        $finish;
    end
    if (IRQ_INDEX_WIDTH < 1 || IRQ_INDEX_WIDTH > 32) begin
        $error("pcie_versal_msix_adapt: IRQ_INDEX_WIDTH must be 1..32 (mint_vector is 32 bits)");
        $finish;
    end
    if (FAIL_RETRY_LIMIT < 1) begin
        $error("pcie_versal_msix_adapt: FAIL_RETRY_LIMIT must be >= 1");
        $finish;
    end
end

localparam RETRY_CNT_WIDTH = $clog2(FAIL_RETRY_LIMIT+1) + 1;

localparam [1:0]
    ST_IDLE  = 2'd0,
    ST_SETUP = 2'd1,
    ST_REQ   = 2'd2;

logic [1:0]                 state_reg = ST_IDLE, state_next;
logic [IRQ_INDEX_WIDTH-1:0] vec_reg = 0, vec_next;
logic [RETRY_CNT_WIDTH-1:0] retry_reg = 0, retry_next;

logic                     int_vector_reg = 1'b0, int_vector_next;
logic                     irq_ready_reg = 1'b0, irq_ready_next;
logic                     mint_valid_reg = 1'b0, mint_valid_next;

logic [STS_COUNT_WIDTH-1:0] c_sent_reg = 0, c_sent_next;
logic [STS_COUNT_WIDTH-1:0] c_fail_reg = 0, c_fail_next;
logic [STS_COUNT_WIDTH-1:0] c_dis_reg = 0, c_dis_next;
logic [STS_COUNT_WIDTH-1:0] c_oor_reg = 0, c_oor_next;
logic [STS_COUNT_WIDTH-1:0] c_rty_reg = 0, c_rty_next;
logic                     masked_seen_reg = 1'b0, masked_seen_next;

assign irq_ready                = irq_ready_reg;
assign cfg_msix_int_vector      = int_vector_reg;
assign cfg_msix_mint_vector     = mint_valid_reg ? {{(32-IRQ_INDEX_WIDTH){1'b0}}, vec_reg} : 32'd0;
assign cfg_msix_function_number = FUNCTION_NUMBER[15:0];
assign cfg_msix_vec_pending     = 2'b00;

assign sts_irq_sent_count    = c_sent_reg;
assign sts_irq_fail_count    = c_fail_reg;
assign sts_irq_drop_disabled = c_dis_reg;
assign sts_irq_drop_oor      = c_oor_reg;
assign sts_irq_drop_retry    = c_rty_reg;
assign sts_irq_masked_seen   = masked_seen_reg;
assign sts_busy              = state_reg != ST_IDLE;

wire index_in_range = irq_index < MSIX_VECTOR_COUNT;

always @* begin
    state_next       = state_reg;
    vec_next         = vec_reg;
    retry_next       = retry_reg;
    int_vector_next  = int_vector_reg;
    mint_valid_next  = mint_valid_reg;
    irq_ready_next   = 1'b0;
    c_sent_next      = c_sent_reg;
    c_fail_next      = c_fail_reg;
    c_dis_next       = c_dis_reg;
    c_oor_next       = c_oor_reg;
    c_rty_next       = c_rty_reg;
    masked_seen_next = masked_seen_reg;

    case (state_reg)
        ST_IDLE: begin
            int_vector_next = 1'b0;
            mint_valid_next = 1'b0;
            irq_ready_next = 1'b1;
            if (irq_valid && irq_ready) begin
                irq_ready_next = 1'b0;
                vec_next   = irq_index;
                retry_next = 0;
                if (!index_in_range) begin
                    if (c_oor_reg != {STS_COUNT_WIDTH{1'b1}}) c_oor_next = c_oor_reg + 1;
                end else if (!cfg_msix_enable) begin
                    if (c_dis_reg != {STS_COUNT_WIDTH{1'b1}}) c_dis_next = c_dis_reg + 1;
                end else begin
                    if (cfg_msix_mask) masked_seen_next = 1'b1;
                    mint_valid_next = 1'b1;
                    state_next = ST_SETUP;
                end
            end
        end
        ST_SETUP: begin
            int_vector_next = 1'b1;
            state_next = ST_REQ;
        end
        ST_REQ: begin
            int_vector_next = 1'b1;
            if (cfg_msix_fail) begin
                if (c_fail_reg != {STS_COUNT_WIDTH{1'b1}}) c_fail_next = c_fail_reg + 1;
                int_vector_next = 1'b0;
                if (retry_reg < FAIL_RETRY_LIMIT) begin
                    retry_next = retry_reg + 1;
                    state_next = ST_SETUP;
                end else begin
                    if (c_rty_reg != {STS_COUNT_WIDTH{1'b1}}) c_rty_next = c_rty_reg + 1;
                    mint_valid_next = 1'b0;
                    state_next = ST_IDLE;
                end
            end else if (cfg_msix_sent) begin
                if (c_sent_reg != {STS_COUNT_WIDTH{1'b1}}) c_sent_next = c_sent_reg + 1;
                int_vector_next = 1'b0;
                mint_valid_next = 1'b0;
                state_next = ST_IDLE;
            end
        end
        default: state_next = ST_IDLE;
    endcase
end

always_ff @(posedge clk) begin
    state_reg       <= state_next;
    vec_reg         <= vec_next;
    retry_reg       <= retry_next;
    int_vector_reg  <= int_vector_next;
    mint_valid_reg  <= mint_valid_next;
    irq_ready_reg   <= irq_ready_next;
    c_sent_reg      <= c_sent_next;
    c_fail_reg      <= c_fail_next;
    c_dis_reg       <= c_dis_next;
    c_oor_reg       <= c_oor_next;
    c_rty_reg       <= c_rty_next;
    masked_seen_reg <= masked_seen_next;

    if (rst) begin
        state_reg       <= ST_IDLE;
        vec_reg         <= 0;
        retry_reg       <= 0;
        int_vector_reg  <= 1'b0;
        mint_valid_reg  <= 1'b0;
        irq_ready_reg   <= 1'b0;
        c_sent_reg      <= 0;
        c_fail_reg      <= 0;
        c_dis_reg       <= 0;
        c_oor_reg       <= 0;
        c_rty_reg       <= 0;
        masked_seen_reg <= 1'b0;
    end
end

endmodule

`resetall
