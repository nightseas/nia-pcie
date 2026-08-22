// ---------------------------------------------------------------------------
// File        : pcie_versal_if_rc.sv
// Description : The requester completion path at 1024-bit AXI4-Stream. Takes
//               straddled completions and decodes the compact start of frame
//               encoding that width uses, presenting whole completions to the client.
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_if_rc #
(

    parameter AXIS_PCIE_DATA_WIDTH = 1024,

    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32),

    parameter AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH >= 1024 ? 337 :
                                        AXIS_PCIE_DATA_WIDTH >=  512 ? 161 : 75,

    parameter RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256,

    parameter RC_SOP_COMPACT = (AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE,

    parameter RC_FIFO_SEG_COUNT = ((AXIS_PCIE_DATA_WIDTH >= 1024) && RC_STRADDLE) ? 4 :
                                  ((RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) ? (AXIS_PCIE_DATA_WIDTH/128) : 1),

    parameter TLP_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH,

    parameter TLP_STRB_WIDTH = TLP_DATA_WIDTH/32,

    parameter TLP_HDR_WIDTH = 128,

    parameter TLP_SEG_COUNT = 1
)
(
    input  wire                                    clk,
    input  wire                                    rst,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]         s_axis_rc_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]         s_axis_rc_tkeep,
    input  wire                                    s_axis_rc_tvalid,
    output wire                                    s_axis_rc_tready,
    input  wire                                    s_axis_rc_tlast,
    input  wire [AXIS_PCIE_RC_USER_WIDTH-1:0]      s_axis_rc_tuser,

    output wire [TLP_DATA_WIDTH-1:0]               rx_cpl_tlp_data,
    output wire [TLP_STRB_WIDTH-1:0]               rx_cpl_tlp_strb,
    output wire [TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0]  rx_cpl_tlp_hdr,
    output wire [TLP_SEG_COUNT*4-1:0]              rx_cpl_tlp_error,
    output wire [TLP_SEG_COUNT-1:0]                rx_cpl_tlp_valid,
    output wire [TLP_SEG_COUNT-1:0]                rx_cpl_tlp_sop,
    output wire [TLP_SEG_COUNT-1:0]                rx_cpl_tlp_eop,
    input  wire                                    rx_cpl_tlp_ready
);

parameter INT_TLP_SEG_COUNT = (RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) ? (AXIS_PCIE_DATA_WIDTH/128) : 1;
parameter INT_TLP_SEG_DATA_WIDTH = TLP_DATA_WIDTH / INT_TLP_SEG_COUNT;
parameter INT_TLP_SEG_STRB_WIDTH = TLP_STRB_WIDTH / INT_TLP_SEG_COUNT;

localparam CP_FN  = INT_TLP_SEG_COUNT;
localparam CP_CN  = RC_FIFO_SEG_COUNT;
localparam CP_FPC = (CP_CN > 0) ? (CP_FN / CP_CN) : 1;
localparam CP_CYE = (CP_FPC > 1) ? (CP_FPC - 1) : 0;
localparam CP_CYN = (CP_CYE > 0) ? CP_CYE : 1;
localparam CP_NE  = CP_FN + CP_CYE;

localparam CP_SELW = $clog2(CP_NE + 1);
localparam CP_NEP  = 1 << CP_SELW;
localparam CP_FSW  = INT_TLP_SEG_DATA_WIDTH;
localparam CP_FSS  = INT_TLP_SEG_STRB_WIDTH;
localparam CP_CSW  = CP_FSW * CP_FPC;
localparam CP_CSS  = CP_FSS * CP_FPC;

localparam CP_MIN_SLOTS = CP_NE;
localparam CP_MIN_BEATS = (CP_MIN_SLOTS + CP_CN - 1) / CP_CN;
localparam CP_IDXW = ($clog2(CP_MIN_BEATS) > 0) ? $clog2(CP_MIN_BEATS) : 1;
localparam CP_NB   = 1 << CP_IDXW;
localparam CP_NSL  = CP_NB * CP_CN;
localparam CP_CYW  = ($clog2(CP_FPC) > 0) ? $clog2(CP_FPC) : 1;

localparam CP_CNLOG = $clog2(CP_CN);

localparam RC_USER_BYTE_EN_OFF  = 0;
localparam RC_USER_BYTE_EN_W    = AXIS_PCIE_DATA_WIDTH/8;
localparam RC_USER_SOP_OFF      = RC_USER_BYTE_EN_OFF + RC_USER_BYTE_EN_W;
localparam RC_USER_SOP_W        = INT_TLP_SEG_COUNT;
localparam RC_USER_SOP_PTR_OFF  = RC_USER_SOP_OFF + RC_USER_SOP_W;

localparam RC_USER_SOP_PTR_W    = $clog2(INT_TLP_SEG_COUNT) > 0 ? $clog2(INT_TLP_SEG_COUNT) : 1;
localparam RC_USER_EOP_OFF      = RC_USER_SOP_PTR_OFF + INT_TLP_SEG_COUNT*RC_USER_SOP_PTR_W;
localparam RC_USER_EOP_W        = INT_TLP_SEG_COUNT;
localparam RC_USER_EOP_PTR_OFF  = RC_USER_EOP_OFF + RC_USER_EOP_W;

localparam RC_USER_EOP_PTR_W    = $clog2(TLP_STRB_WIDTH) > 0 ? $clog2(TLP_STRB_WIDTH) : 1;
localparam RC_USER_DISC_OFF     = RC_USER_EOP_PTR_OFF + INT_TLP_SEG_COUNT*RC_USER_EOP_PTR_W;
localparam RC_USER_PARITY_OFF   = RC_USER_DISC_OFF + 1;
localparam RC_USER_PARITY_W     = AXIS_PCIE_DATA_WIDTH/8;
localparam RC_USER_WIDE_W       = RC_USER_PARITY_OFF + RC_USER_PARITY_W;

localparam RC_FMT_TLAST = 0;
localparam RC_FMT_NARROW_STRADDLE = 1;
localparam RC_FMT_WIDE  = 2;
localparam RC_USER_FMT  = !(RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) ? RC_FMT_TLAST :
                          (AXIS_PCIE_DATA_WIDTH >= 512)                 ? RC_FMT_WIDE  :
                                                                          RC_FMT_NARROW_STRADDLE;

function integer rc_expect_seg_count;
    input integer w;
    begin
        case (w)
            1024:    rc_expect_seg_count = 8;
            512:     rc_expect_seg_count = 4;
            256:     rc_expect_seg_count = 2;
            default: rc_expect_seg_count = 1;
        endcase
    end
endfunction

function integer rc_expect_user_width;
    input integer w;
    begin
        case (w)
            1024:    rc_expect_user_width = 337;
            512:     rc_expect_user_width = 161;
            default: rc_expect_user_width = 75;
        endcase
    end
endfunction

initial begin

    if (AXIS_PCIE_DATA_WIDTH != 64 && AXIS_PCIE_DATA_WIDTH != 128 && AXIS_PCIE_DATA_WIDTH != 256 &&
            AXIS_PCIE_DATA_WIDTH != 512 && AXIS_PCIE_DATA_WIDTH != 1024) begin
        $error("Error: PCIe interface width must be 64, 128, 256, 512, or 1024 (instance %m)");
        $finish;
    end

    if (AXIS_PCIE_KEEP_WIDTH * 32 != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: PCIe interface requires dword (32-bit) granularity (instance %m)");
        $finish;
    end

    if (AXIS_PCIE_RC_USER_WIDTH != rc_expect_user_width(AXIS_PCIE_DATA_WIDTH)) begin
        $error("Error: PCIe RC tuser width must be %0d for a %0d-bit interface (instance %m)",
            rc_expect_user_width(AXIS_PCIE_DATA_WIDTH), AXIS_PCIE_DATA_WIDTH);
        $finish;
    end

    if (RC_STRADDLE && AXIS_PCIE_DATA_WIDTH >= 256) begin
        if (INT_TLP_SEG_COUNT != rc_expect_seg_count(AXIS_PCIE_DATA_WIDTH)) begin
            $error("Error: INT_TLP_SEG_COUNT is %0d but must be %0d at %0d bits (instance %m)",
                INT_TLP_SEG_COUNT, rc_expect_seg_count(AXIS_PCIE_DATA_WIDTH), AXIS_PCIE_DATA_WIDTH);
            $finish;
        end
    end else begin
        if (INT_TLP_SEG_COUNT != 1) begin
            $error("Error: INT_TLP_SEG_COUNT must be 1 without straddling (instance %m)");
            $finish;
        end
    end

    if (RC_USER_FMT == RC_FMT_WIDE) begin
        if (RC_USER_WIDE_W != AXIS_PCIE_RC_USER_WIDTH) begin
            $error("Error: derived RC tuser layout totals %0d bits, expected %0d (instance %m)",
                RC_USER_WIDE_W, AXIS_PCIE_RC_USER_WIDTH);
            $finish;
        end
    end

    if (TLP_DATA_WIDTH != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: Interface widths must match (instance %m)");
        $finish;
    end

    if (TLP_HDR_WIDTH != 128) begin
        $error("Error: TLP segment header width must be 128 (instance %m)");
        $finish;
    end

    if (TLP_SEG_COUNT != 1) begin
        $error("Error: TLP_SEG_COUNT must be 1 (contract V12) (instance %m)");
        $finish;
    end

    if (RC_SOP_COMPACT != 0 && RC_SOP_COMPACT != 1) begin
        $error("Error: RC_SOP_COMPACT must be 0 or 1, is %0d (instance %m)", RC_SOP_COMPACT);
        $finish;
    end

    if (RC_SOP_COMPACT == 0) begin

        if (RC_FIFO_SEG_COUNT != INT_TLP_SEG_COUNT) begin
            $error("Error: RC_SOP_COMPACT=0 requires RC_FIFO_SEG_COUNT == INT_TLP_SEG_COUNT (%0d), is %0d (instance %m)",
                INT_TLP_SEG_COUNT, RC_FIFO_SEG_COUNT);
            $finish;
        end
    end else begin

        if (RC_FIFO_SEG_COUNT != 8 && RC_FIFO_SEG_COUNT != 4) begin
            $error("Error: RC_FIFO_SEG_COUNT must be 8 or 4 when compacting, is %0d. 2 is REFUSED: measured broken (T36C_RC_SEG2_REFUSED; s9_run4 rc_1024_seg2 = 10/19 while every other arm is clean; CP_FPC=4 path untraced) -- see contract 3.7 (instance %m)",
                RC_FIFO_SEG_COUNT);
            $finish;
        end
        if (!RC_STRADDLE || INT_TLP_SEG_COUNT < 2) begin
            $error("Error: RC_SOP_COMPACT=1 requires RC_STRADDLE and INT_TLP_SEG_COUNT >= 2 (is %0d) (instance %m)",
                INT_TLP_SEG_COUNT);
            $finish;
        end
        if (RC_FIFO_SEG_COUNT > INT_TLP_SEG_COUNT) begin
            $error("Error: RC_FIFO_SEG_COUNT (%0d) must not exceed INT_TLP_SEG_COUNT (%0d) (instance %m)",
                RC_FIFO_SEG_COUNT, INT_TLP_SEG_COUNT);
            $finish;
        end

        if (CP_FPC * RC_FIFO_SEG_COUNT != INT_TLP_SEG_COUNT) begin
            $error("Error: RC_FIFO_SEG_COUNT (%0d) must divide INT_TLP_SEG_COUNT (%0d) (instance %m)",
                RC_FIFO_SEG_COUNT, INT_TLP_SEG_COUNT);
            $finish;
        end

        if (CP_CSW * RC_FIFO_SEG_COUNT != TLP_DATA_WIDTH) begin
            $error("Error: coarse segment geometry inconsistent: %0d x %0d != %0d (instance %m)",
                CP_CSW, RC_FIFO_SEG_COUNT, TLP_DATA_WIDTH);
            $finish;
        end

        if (CP_NSL < CP_NE) begin
            $error("Error: slot capacity CP_NSL=%0d is below the proven bound CP_NE=%0d -- the scan would drop completions (instance %m)",
                CP_NSL, CP_NE);
            $finish;
        end

        if (CP_NB < CP_MIN_BEATS) begin
            $error("Error: emit-beat capacity CP_NB=%0d is below CP_MIN_BEATS=%0d (instance %m)",
                CP_NB, CP_MIN_BEATS);
            $finish;
        end
    end

    $display("T36B_RC_WITNESS inst=%m axis_w=%0d rc_user_w=%0d straddle=%0d int_seg=%0d int_seg_data_w=%0d compact=%0d fifo_in_seg=%0d fifo_in_seg_data_w=%0d fpc=%0d entries=%0d slots=%0d emit_beats=%0d added_latency_cyc=%0d",
        AXIS_PCIE_DATA_WIDTH, AXIS_PCIE_RC_USER_WIDTH, RC_STRADDLE,
        INT_TLP_SEG_COUNT, INT_TLP_SEG_DATA_WIDTH,
        RC_SOP_COMPACT, RC_FIFO_SEG_COUNT, (TLP_DATA_WIDTH/RC_FIFO_SEG_COUNT),
        CP_FPC, CP_NE, CP_NSL, CP_NB, (RC_SOP_COMPACT ? 2 : 0));
end

localparam [2:0]
    TLP_FMT_3DW = 3'b000,
    TLP_FMT_4DW = 3'b001,
    TLP_FMT_3DW_DATA = 3'b010,
    TLP_FMT_4DW_DATA = 3'b011,
    TLP_FMT_PREFIX = 3'b100;

localparam [2:0]
    CPL_STATUS_SC  = 3'b000,
    CPL_STATUS_UR  = 3'b001,
    CPL_STATUS_CRS = 3'b010,
    CPL_STATUS_CA  = 3'b100;

localparam [3:0]
    RC_ERROR_NORMAL_TERMINATION = 4'b0000,
    RC_ERROR_POISONED = 4'b0001,
    RC_ERROR_BAD_STATUS = 4'b0010,
    RC_ERROR_INVALID_LENGTH = 4'b0011,
    RC_ERROR_MISMATCH = 4'b0100,
    RC_ERROR_INVALID_ADDRESS = 4'b0101,
    RC_ERROR_INVALID_TAG = 4'b0110,
    RC_ERROR_TIMEOUT = 4'b1001,
    RC_ERROR_FLR = 4'b1000;

localparam [3:0]
    PCIE_ERROR_NONE = 4'd0,
    PCIE_ERROR_POISONED = 4'd1,
    PCIE_ERROR_BAD_STATUS = 4'd2,
    PCIE_ERROR_MISMATCH = 4'd3,
    PCIE_ERROR_INVALID_LEN = 4'd4,
    PCIE_ERROR_INVALID_ADDR = 4'd5,
    PCIE_ERROR_INVALID_TAG = 4'd6,
    PCIE_ERROR_FLR = 4'd8,
    PCIE_ERROR_TIMEOUT = 4'd15;

logic [TLP_DATA_WIDTH-1:0] rx_cpl_tlp_data_reg = 0, rx_cpl_tlp_data_next;
logic [TLP_STRB_WIDTH-1:0] rx_cpl_tlp_strb_reg = 0, rx_cpl_tlp_strb_next;
logic [INT_TLP_SEG_COUNT*TLP_HDR_WIDTH-1:0] rx_cpl_tlp_hdr_reg = 0, rx_cpl_tlp_hdr_next;
logic [INT_TLP_SEG_COUNT*4-1:0] rx_cpl_tlp_error_reg = 0, rx_cpl_tlp_error_next;
logic [INT_TLP_SEG_COUNT-1:0] rx_cpl_tlp_valid_reg = 0, rx_cpl_tlp_valid_next;
logic [INT_TLP_SEG_COUNT-1:0] rx_cpl_tlp_sop_reg = 0, rx_cpl_tlp_sop_next;
logic [INT_TLP_SEG_COUNT-1:0] rx_cpl_tlp_eop_reg = 0, rx_cpl_tlp_eop_next;
logic tlp_frame_reg = 0, tlp_frame_next;

wire fifo_tlp_ready;

logic tlp_input_frame_reg = 1'b0, tlp_input_frame_next;

logic [TLP_DATA_WIDTH-1:0] rc_data;
logic [TLP_STRB_WIDTH-1:0] rc_strb;
logic [INT_TLP_SEG_COUNT-1:0] rc_valid;
logic [TLP_STRB_WIDTH-1:0] rc_strb_sop;
logic [TLP_STRB_WIDTH-1:0] rc_strb_eop;
logic [INT_TLP_SEG_COUNT-1:0] rc_sop;
logic [INT_TLP_SEG_COUNT-1:0] rc_eop;
logic rc_frame_reg = 1'b0, rc_frame_next;

logic [TLP_DATA_WIDTH-1:0] rc_data_int_reg = 0, rc_data_int_next;
logic [TLP_STRB_WIDTH-1:0] rc_strb_int_reg = 0, rc_strb_int_next;
logic [INT_TLP_SEG_COUNT-1:0] rc_valid_int_reg = 0, rc_valid_int_next;
logic [TLP_STRB_WIDTH-1:0] rc_strb_eop_int_reg = 0, rc_strb_eop_int_next;
logic [INT_TLP_SEG_COUNT-1:0] rc_sop_int_reg = 0, rc_sop_int_next;
logic [INT_TLP_SEG_COUNT-1:0] rc_eop_int_reg = 0, rc_eop_int_next;

wire [TLP_DATA_WIDTH*2-1:0] rc_data_full = {rc_data, rc_data_int_reg};
wire [TLP_STRB_WIDTH*2-1:0] rc_strb_full = {rc_strb, rc_strb_int_reg};
wire [INT_TLP_SEG_COUNT*2-1:0] rc_valid_full = {rc_valid, rc_valid_int_reg};
wire [TLP_STRB_WIDTH*2-1:0] rc_strb_eop_full = {rc_strb_eop, rc_strb_eop_int_reg};
wire [INT_TLP_SEG_COUNT*2-1:0] rc_sop_full = {rc_sop, rc_sop_int_reg};
wire [INT_TLP_SEG_COUNT*2-1:0] rc_eop_full = {rc_eop, rc_eop_int_reg};

logic [INT_TLP_SEG_COUNT*128-1:0] tlp_hdr;
logic [INT_TLP_SEG_COUNT*4-1:0] tlp_error;

wire                                     stage_a_ready;
wire [TLP_DATA_WIDTH-1:0]                fifo_in_data;
wire [TLP_STRB_WIDTH-1:0]                fifo_in_strb;
wire [RC_FIFO_SEG_COUNT*TLP_HDR_WIDTH-1:0] fifo_in_hdr;
wire [RC_FIFO_SEG_COUNT*4-1:0]           fifo_in_error;
wire [RC_FIFO_SEG_COUNT-1:0]             fifo_in_valid;
wire [RC_FIFO_SEG_COUNT-1:0]             fifo_in_sop;
wire [RC_FIFO_SEG_COUNT-1:0]             fifo_in_eop;

assign s_axis_rc_tready = stage_a_ready;

pcie_tlp_fifo #(
    .DEPTH((1024/4)*2),
    .TLP_DATA_WIDTH(TLP_DATA_WIDTH),
    .TLP_STRB_WIDTH(TLP_STRB_WIDTH),
    .TLP_HDR_WIDTH(TLP_HDR_WIDTH),
    .SEQ_NUM_WIDTH(1),
    .IN_TLP_SEG_COUNT(RC_FIFO_SEG_COUNT),
    .OUT_TLP_SEG_COUNT(TLP_SEG_COUNT)
)
pcie_tlp_fifo_inst (
    .clk(clk),
    .rst(rst),

    .in_tlp_data(fifo_in_data),
    .in_tlp_strb(fifo_in_strb),
    .in_tlp_hdr(fifo_in_hdr),
    .in_tlp_seq(0),
    .in_tlp_bar_id(0),
    .in_tlp_func_num(0),
    .in_tlp_error(fifo_in_error),
    .in_tlp_valid(fifo_in_valid),
    .in_tlp_sop(fifo_in_sop),
    .in_tlp_eop(fifo_in_eop),
    .in_tlp_ready(fifo_tlp_ready),

    .out_tlp_data(rx_cpl_tlp_data),
    .out_tlp_strb(rx_cpl_tlp_strb),
    .out_tlp_hdr(rx_cpl_tlp_hdr),
    .out_tlp_seq(),
    .out_tlp_bar_id(),
    .out_tlp_func_num(),
    .out_tlp_error(rx_cpl_tlp_error),
    .out_tlp_valid(rx_cpl_tlp_valid),
    .out_tlp_sop(rx_cpl_tlp_sop),
    .out_tlp_eop(rx_cpl_tlp_eop),
    .out_tlp_ready(rx_cpl_tlp_ready),

    .half_full(),
    .watermark()
);

if (RC_SOP_COMPACT) begin : g_rc_compact

    logic [CP_NEP*CP_FSW-1:0]        e_data;
    logic [CP_NEP*TLP_HDR_WIDTH-1:0] e_hdr;
    logic [CP_NEP*4-1:0]             e_err;
    logic [CP_NEP*CP_FSS-1:0]        e_strb;
    logic [CP_NEP-1:0]               e_valid;
    logic [CP_NEP-1:0]               e_sop;
    logic [CP_NEP-1:0]               e_eop;
    logic [CP_NEP-1:0]               e_fs;
    logic [CP_SELW-1:0]              e_lastv;
    logic [CP_CYN*CP_SELW-1:0]       e_cysel;

    logic [CP_CYN*CP_FSW-1:0]        cy_data_reg = 0;
    logic [CP_CYN*TLP_HDR_WIDTH-1:0] cy_hdr_reg = 0;
    logic [CP_CYN*4-1:0]             cy_err_reg = 0;
    logic [CP_CYN*CP_FSS-1:0]        cy_strb_reg = 0;
    logic [CP_CYN-1:0]               cy_sop_reg = 0;
    logic [CP_CYW-1:0]               cy_cnt_reg = 0;

    integer ei;
    logic   e_seen;

    logic [31:0] cy_cnt_x;
    logic [31:0] e_lastv_x;
    logic [31:0] e_cysrc_x;
    logic [CP_SELW-1:0]              cysel_c;
    logic [CP_CYN*CP_FSW-1:0]        cy_data_nxt;
    logic [CP_CYN*TLP_HDR_WIDTH-1:0] cy_hdr_nxt;
    logic [CP_CYN*4-1:0]             cy_err_nxt;
    logic [CP_CYN*CP_FSS-1:0]        cy_strb_nxt;
    logic [CP_CYN-1:0]               cy_sop_nxt;

    always @* begin
        e_data  = 0;
        e_hdr   = 0;
        e_err   = 0;
        e_strb  = 0;
        e_valid = 0;
        e_sop   = 0;
        e_eop   = 0;
        cy_cnt_x = {{(32-CP_CYW){1'b0}}, cy_cnt_reg};
        for (ei = 0; ei < CP_NE; ei = ei + 1) begin
            if (ei < CP_CYE) begin

                e_data [ei*CP_FSW        +: CP_FSW]        = cy_data_reg[(ei % CP_CYN)*CP_FSW        +: CP_FSW];
                e_hdr  [ei*TLP_HDR_WIDTH +: TLP_HDR_WIDTH] = cy_hdr_reg [(ei % CP_CYN)*TLP_HDR_WIDTH +: TLP_HDR_WIDTH];
                e_err  [ei*4             +: 4]             = cy_err_reg [(ei % CP_CYN)*4             +: 4];
                e_strb [ei*CP_FSS        +: CP_FSS]        = cy_strb_reg[(ei % CP_CYN)*CP_FSS        +: CP_FSS];

                e_valid[ei] = (cy_cnt_x >= (CP_CYE - ei));
                e_sop  [ei] = cy_sop_reg[ei % CP_CYN] && (cy_cnt_x >= (CP_CYE - ei));

                e_eop  [ei] = 1'b0;
            end else begin
                e_data [ei*CP_FSW        +: CP_FSW]        = rx_cpl_tlp_data_reg [(ei-CP_CYE)*CP_FSW        +: CP_FSW];
                e_hdr  [ei*TLP_HDR_WIDTH +: TLP_HDR_WIDTH] = rx_cpl_tlp_hdr_reg  [(ei-CP_CYE)*TLP_HDR_WIDTH +: TLP_HDR_WIDTH];
                e_err  [ei*4             +: 4]             = rx_cpl_tlp_error_reg[(ei-CP_CYE)*4             +: 4];
                e_strb [ei*CP_FSS        +: CP_FSS]        = rx_cpl_tlp_strb_reg [(ei-CP_CYE)*CP_FSS        +: CP_FSS];
                e_valid[ei] = rx_cpl_tlp_valid_reg[ei-CP_CYE];
                e_sop  [ei] = rx_cpl_tlp_sop_reg  [ei-CP_CYE];
                e_eop  [ei] = rx_cpl_tlp_eop_reg  [ei-CP_CYE];
            end
        end

        e_seen = 1'b0;
        for (ei = 0; ei < CP_NE; ei = ei + 1) begin
            e_fs[ei] = e_valid[ei] && (e_sop[ei] || !e_seen);
            if (e_valid[ei]) begin
                e_seen = 1'b1;
            end
        end

        e_lastv = 0;
        for (ei = 0; ei < CP_NE; ei = ei + 1) begin
            if (e_valid[ei]) begin
                e_lastv = ei[CP_SELW-1:0];
            end
        end
        e_cysel = 0;
        e_lastv_x = {{(32-CP_SELW){1'b0}}, e_lastv};
        for (ei = 0; ei < CP_CYE; ei = ei + 1) begin

            if (e_lastv_x >= (CP_CYE-1-ei)) begin
                e_cysrc_x = e_lastv_x - (CP_CYE-1-ei);
                e_cysel[(ei % CP_CYN)*CP_SELW +: CP_SELW] = e_cysrc_x[CP_SELW-1:0];
            end
        end

        cy_data_nxt = 0;
        cy_hdr_nxt  = 0;
        cy_err_nxt  = 0;
        cy_strb_nxt = 0;
        cy_sop_nxt  = 0;
        for (ei = 0; ei < CP_CYE; ei = ei + 1) begin
            cysel_c = e_cysel[(ei % CP_CYN)*CP_SELW +: CP_SELW];
            cy_data_nxt[(ei % CP_CYN)*CP_FSW        +: CP_FSW]        = e_data[cysel_c*CP_FSW        +: CP_FSW];
            cy_hdr_nxt [(ei % CP_CYN)*TLP_HDR_WIDTH +: TLP_HDR_WIDTH] = e_hdr [cysel_c*TLP_HDR_WIDTH +: TLP_HDR_WIDTH];
            cy_err_nxt [(ei % CP_CYN)*4             +: 4]             = e_err [cysel_c*4             +: 4];
            cy_strb_nxt[(ei % CP_CYN)*CP_FSS        +: CP_FSS]        = e_strb[cysel_c*CP_FSS        +: CP_FSS];
            cy_sop_nxt [(ei % CP_CYN)]                                = e_sop [cysel_c];
        end
    end

    logic [CP_NSL-1:0]                sl_valid;
    logic [CP_NSL-1:0]                sl_sop;
    logic [CP_NSL-1:0]                sl_eop;
    logic [CP_NSL*CP_CSS-1:0]         sl_strb;
    logic [CP_NSL*CP_FPC*CP_SELW-1:0] sl_sel;
    logic [CP_IDXW+1-1:0]             sl_nbeats;
    logic [CP_CYW-1:0]                sl_ncarry;
    integer sc_i, sc_p, sc_t, sc_nb;

    always @* begin
        sl_valid = 0;
        sl_sop   = 0;
        sl_eop   = 0;
        sl_strb  = 0;
        sl_sel   = 0;
        sc_p = 0;
        sc_t = 0;
        for (sc_i = 0; sc_i < CP_NE; sc_i = sc_i + 1) begin
            if (e_valid[sc_i]) begin

                if (e_fs[sc_i] && sc_p != 0) begin
                    sc_t = sc_t + 1;
                    sc_p = 0;
                end
                if (sc_t < CP_NSL) begin
                    sl_valid[sc_t] = 1'b1;
                    sl_sel[(sc_t*CP_FPC + sc_p)*CP_SELW +: CP_SELW] = sc_i[CP_SELW-1:0];
                    sl_strb[sc_t*CP_CSS + sc_p*CP_FSS +: CP_FSS] = e_strb[sc_i*CP_FSS +: CP_FSS];
                    if (sc_p == 0) begin

                        sl_sop[sc_t] = e_sop[sc_i];
                    end
                    if (e_eop[sc_i]) begin
                        sl_eop[sc_t] = 1'b1;
                    end
                end
                if (e_eop[sc_i]) begin
                    sc_t = sc_t + 1;
                    sc_p = 0;
                end else begin
                    sc_p = sc_p + 1;
                    if (sc_p == CP_FPC) begin
                        sc_t = sc_t + 1;
                        sc_p = 0;
                    end
                end
            end

        end

        if (sc_p != 0 && sc_t < CP_NSL) begin
            sl_valid[sc_t] = 1'b0;
            sl_sop[sc_t]   = 1'b0;
            sl_eop[sc_t]   = 1'b0;
            sl_strb[sc_t*CP_CSS +: CP_CSS] = 0;
        end
        sl_ncarry = sc_p[CP_CYW-1:0];

        sc_nb     = (sc_t + CP_CN - 1) >> CP_CNLOG;
        sl_nbeats = sc_nb[CP_IDXW+1-1:0];
    end

    logic                           b1_valid_reg = 1'b0;
    logic [CP_NEP*CP_FSW-1:0]         b1_e_data_reg = 0;
    logic [CP_NEP*TLP_HDR_WIDTH-1:0]  b1_e_hdr_reg = 0;
    logic [CP_NEP*4-1:0]              b1_e_err_reg = 0;
    logic [CP_NSL*CP_FPC*CP_SELW-1:0] b1_sel_reg = 0;
    logic [CP_NSL*CP_CSS-1:0]         b1_strb_reg = 0;
    logic [CP_NSL-1:0]                b1_svalid_reg = 0;
    logic [CP_NSL-1:0]                b1_ssop_reg = 0;
    logic [CP_NSL-1:0]                b1_seop_reg = 0;
    logic [CP_IDXW+1-1:0]             b1_nbeats_reg = 0;

    logic [CP_NB*TLP_DATA_WIDTH-1:0]  cp_data_reg = 0;
    logic [CP_NB*TLP_STRB_WIDTH-1:0]  cp_strb_reg = 0;
    logic [CP_NSL*TLP_HDR_WIDTH-1:0]  cp_hdr_reg = 0;
    logic [CP_NSL*4-1:0]              cp_err_reg = 0;
    logic [CP_NSL-1:0]                cp_valid_reg = 0;
    logic [CP_NSL-1:0]                cp_sop_reg = 0;
    logic [CP_NSL-1:0]                cp_eop_reg = 0;
    logic [CP_IDXW+1-1:0]             cp_cnt_reg = 0;
    logic [CP_IDXW-1:0]               cp_idx_reg = 0;

    logic [CP_NSL*CP_CSW-1:0]         b2_data;
    logic [CP_NSL*TLP_HDR_WIDTH-1:0]  b2_hdr;
    logic [CP_NSL*4-1:0]              b2_err;
    integer mt, mq;
    logic [CP_SELW-1:0] msel;

    always @* begin
        b2_data = 0;
        b2_hdr  = 0;
        b2_err  = 0;
        for (mt = 0; mt < CP_NSL; mt = mt + 1) begin
            for (mq = 0; mq < CP_FPC; mq = mq + 1) begin
                msel = b1_sel_reg[(mt*CP_FPC + mq)*CP_SELW +: CP_SELW];
                b2_data[mt*CP_CSW + mq*CP_FSW +: CP_FSW] = b1_e_data_reg[msel*CP_FSW +: CP_FSW];
            end
            msel = b1_sel_reg[(mt*CP_FPC)*CP_SELW +: CP_SELW];
            b2_hdr[mt*TLP_HDR_WIDTH +: TLP_HDR_WIDTH] = b1_e_hdr_reg[msel*TLP_HDR_WIDTH +: TLP_HDR_WIDTH];
            b2_err[mt*4 +: 4] = b1_e_err_reg[msel*4 +: 4];
        end
    end

    wire b2_free = (cp_cnt_reg == 0) || ((cp_cnt_reg == {{(CP_IDXW){1'b0}}, 1'b1}) && fifo_tlp_ready);
    wire b2_load = b1_valid_reg && b2_free;
    wire b1_free = !b1_valid_reg || b2_load;

    assign stage_a_ready = b1_free;

    assign fifo_in_data  = cp_data_reg[cp_idx_reg*TLP_DATA_WIDTH +: TLP_DATA_WIDTH];
    assign fifo_in_strb  = cp_strb_reg[cp_idx_reg*TLP_STRB_WIDTH +: TLP_STRB_WIDTH];
    assign fifo_in_hdr   = cp_hdr_reg[cp_idx_reg*CP_CN*TLP_HDR_WIDTH +: CP_CN*TLP_HDR_WIDTH];
    assign fifo_in_error = cp_err_reg[cp_idx_reg*CP_CN*4 +: CP_CN*4];
    assign fifo_in_valid = (cp_cnt_reg != 0) ? cp_valid_reg[cp_idx_reg*CP_CN +: CP_CN] : {CP_CN{1'b0}};
    assign fifo_in_sop   = cp_sop_reg[cp_idx_reg*CP_CN +: CP_CN];
    assign fifo_in_eop   = cp_eop_reg[cp_idx_reg*CP_CN +: CP_CN];

    always_ff @(posedge clk) begin

        if (b1_free && (rx_cpl_tlp_valid_reg != 0)) begin
            b1_e_data_reg <= e_data;
            b1_e_hdr_reg  <= e_hdr;
            b1_e_err_reg  <= e_err;
            b1_sel_reg    <= sl_sel;
            b1_strb_reg   <= sl_strb;
            b1_svalid_reg <= sl_valid;
            b1_ssop_reg   <= sl_sop;
            b1_seop_reg   <= sl_eop;
            b1_nbeats_reg <= sl_nbeats;
            b1_valid_reg  <= 1'b1;

            cy_cnt_reg  <= sl_ncarry;
            cy_data_reg <= cy_data_nxt;
            cy_hdr_reg  <= cy_hdr_nxt;
            cy_err_reg  <= cy_err_nxt;
            cy_strb_reg <= cy_strb_nxt;
            cy_sop_reg  <= cy_sop_nxt;
        end else if (b2_load) begin
            b1_valid_reg <= 1'b0;
        end

        if (b2_load) begin
            cp_data_reg  <= b2_data;
            cp_strb_reg  <= b1_strb_reg;
            cp_hdr_reg   <= b2_hdr;
            cp_err_reg   <= b2_err;
            cp_valid_reg <= b1_svalid_reg;
            cp_sop_reg   <= b1_ssop_reg;
            cp_eop_reg   <= b1_seop_reg;
            cp_cnt_reg   <= b1_nbeats_reg;
            cp_idx_reg   <= 0;
        end else if ((cp_cnt_reg != 0) && fifo_tlp_ready) begin
            cp_cnt_reg <= cp_cnt_reg - 1;
            cp_idx_reg <= cp_idx_reg + 1;
        end

        if (rst) begin
            b1_valid_reg <= 1'b0;
            b1_nbeats_reg <= 0;
            b1_svalid_reg <= 0;
            cp_valid_reg <= 0;
            cp_cnt_reg   <= 0;
            cp_idx_reg   <= 0;
            cy_cnt_reg   <= 0;
        end
    end

end else begin : g_rc_no_compact

    assign stage_a_ready = fifo_tlp_ready;
    assign fifo_in_data  = rx_cpl_tlp_data_reg;
    assign fifo_in_strb  = rx_cpl_tlp_strb_reg;
    assign fifo_in_hdr   = rx_cpl_tlp_hdr_reg;
    assign fifo_in_error = rx_cpl_tlp_error_reg;
    assign fifo_in_valid = rx_cpl_tlp_valid_reg;
    assign fifo_in_sop   = rx_cpl_tlp_sop_reg;
    assign fifo_in_eop   = rx_cpl_tlp_eop_reg;

end

integer seg, lane;
logic valid;

always @* begin
    rx_cpl_tlp_data_next = rx_cpl_tlp_data_reg;
    rx_cpl_tlp_strb_next = rx_cpl_tlp_strb_reg;
    rx_cpl_tlp_hdr_next = rx_cpl_tlp_hdr_reg;
    rx_cpl_tlp_error_next = rx_cpl_tlp_error_reg;

    rx_cpl_tlp_valid_next = stage_a_ready ? 0 : rx_cpl_tlp_valid_reg;
    rx_cpl_tlp_sop_next = rx_cpl_tlp_sop_reg;
    rx_cpl_tlp_eop_next = rx_cpl_tlp_eop_reg;
    tlp_frame_next = tlp_frame_reg;

    rc_frame_next = rc_frame_reg;

    rc_data_int_next = rc_data_int_reg;
    rc_strb_int_next = rc_strb_int_reg;
    rc_valid_int_next = rc_valid_int_reg;
    rc_strb_eop_int_next = rc_strb_eop_int_reg;
    rc_sop_int_next = rc_sop_int_reg;
    rc_eop_int_next = rc_eop_int_reg;

    if (RC_USER_FMT != RC_FMT_TLAST) begin
        rc_data = s_axis_rc_tdata;
        rc_strb = 0;
        rc_valid = 0;
        rc_strb_sop = 0;
        rc_strb_eop = 0;
        rc_sop = 0;
        rc_eop = 0;

        if (RC_USER_FMT == RC_FMT_WIDE) begin

            for (seg = 0; seg < INT_TLP_SEG_COUNT; seg = seg + 1) begin
                if (s_axis_rc_tuser[RC_USER_SOP_OFF+seg]) begin
                    rc_strb_sop[s_axis_rc_tuser[RC_USER_SOP_PTR_OFF+seg*RC_USER_SOP_PTR_W +: RC_USER_SOP_PTR_W]*INT_TLP_SEG_STRB_WIDTH] = 1'b1;
                end
                if (s_axis_rc_tuser[RC_USER_EOP_OFF+seg]) begin
                    rc_strb_eop[s_axis_rc_tuser[RC_USER_EOP_PTR_OFF+seg*RC_USER_EOP_PTR_W +: RC_USER_EOP_PTR_W]] = 1'b1;
                end
            end

        end else begin

            if (INT_TLP_SEG_COUNT == 1) begin
                if (s_axis_rc_tuser[32]) begin
                    rc_strb_sop[0] = 1'b1;
                end
            end else begin
                if (s_axis_rc_tuser[32]) begin
                    if (rc_frame_reg) begin
                        rc_strb_sop[4] = 1'b1;
                    end else begin
                        rc_strb_sop[0] = 1'b1;
                    end
                end
                if (s_axis_rc_tuser[33]) begin
                    rc_strb_sop[4] = 1'b1;
                end
            end
            for (seg = 0; seg < INT_TLP_SEG_COUNT; seg = seg + 1) begin
                if (s_axis_rc_tuser[34+seg*4]) begin
                    rc_strb_eop[s_axis_rc_tuser[35+seg*4 +: 3]] = 1'b1;
                end
            end
        end

        valid = 1;
        for (lane = 0; lane < TLP_STRB_WIDTH; lane = lane + 1) begin
            if (rc_strb_sop[lane]) begin
                valid = 1;
                rc_sop[lane/INT_TLP_SEG_STRB_WIDTH] = 1'b1;
            end
            if (valid) begin
                rc_strb[lane] = 1'b1;
                rc_valid[lane/INT_TLP_SEG_STRB_WIDTH] = s_axis_rc_tvalid;
            end
            if (rc_strb_eop[lane]) begin
                valid = 0;
                rc_eop[lane/INT_TLP_SEG_STRB_WIDTH] = 1'b1;
            end
        end
        if (s_axis_rc_tready && s_axis_rc_tvalid) begin
            rc_frame_next = valid;
        end
    end else begin

        rc_data = s_axis_rc_tdata;
        rc_strb = s_axis_rc_tvalid ? s_axis_rc_tkeep : 0;
        rc_valid = s_axis_rc_tvalid;
        rc_sop = !rc_frame_reg;
        rc_eop = s_axis_rc_tlast;
        rc_strb_sop = rc_sop;
        rc_strb_eop = 0;
        for (lane = 0; lane < TLP_STRB_WIDTH; lane = lane + 1) begin
            if (rc_strb[lane]) begin
                rc_strb_eop = (rc_eop) << lane;
            end
        end
        if (s_axis_rc_tready && s_axis_rc_tvalid) begin
            rc_frame_next = !s_axis_rc_tlast;
        end
    end

    for (seg = 0; seg < INT_TLP_SEG_COUNT; seg = seg + 1) begin

        if (rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+32 +: 11] != 0) begin
            tlp_hdr[128*seg+125 +: 3] = TLP_FMT_3DW_DATA;
        end else begin
            tlp_hdr[128*seg+125 +: 3] = TLP_FMT_3DW;
        end
        tlp_hdr[128*seg+120 +: 5] = {4'b0101, rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+29]};
        tlp_hdr[128*seg+119] = 1'b0;
        tlp_hdr[128*seg+116 +: 3] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+89 +: 3];
        tlp_hdr[128*seg+115] = 1'b0;
        tlp_hdr[128*seg+114] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+94];
        tlp_hdr[128*seg+113] = 1'b0;
        tlp_hdr[128*seg+112] = 1'b0;
        tlp_hdr[128*seg+111] = 1'b0;
        tlp_hdr[128*seg+110] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+46];
        tlp_hdr[128*seg+108 +: 2] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+92 +: 2];
        tlp_hdr[128*seg+106 +: 2] = 2'b00;
        tlp_hdr[128*seg+96 +: 10] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+32 +: 11];

        tlp_hdr[128*seg+80 +: 16] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+72 +: 16];
        tlp_hdr[128*seg+77 +: 3] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+43 +: 3];
        tlp_hdr[128*seg+76] = 1'b0;
        tlp_hdr[128*seg+64 +: 12] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+16 +: 13];

        tlp_hdr[128*seg+48 +: 16] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+48 +: 16];
        tlp_hdr[128*seg+40 +: 8] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+64 +: 8];
        tlp_hdr[128*seg+39] = 1'b0;
        tlp_hdr[128*seg+32 +: 7] = rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+0 +: 7];

        tlp_hdr[128*seg+0 +: 32] = 32'd0;

        case (rc_data_full[INT_TLP_SEG_DATA_WIDTH*seg+12 +: 4])
            RC_ERROR_NORMAL_TERMINATION: tlp_error[4*seg +: 4] = PCIE_ERROR_NONE;
            RC_ERROR_POISONED:           tlp_error[4*seg +: 4] = PCIE_ERROR_POISONED;
            RC_ERROR_BAD_STATUS:         tlp_error[4*seg +: 4] = PCIE_ERROR_BAD_STATUS;
            RC_ERROR_INVALID_LENGTH:     tlp_error[4*seg +: 4] = PCIE_ERROR_INVALID_LEN;
            RC_ERROR_MISMATCH:           tlp_error[4*seg +: 4] = PCIE_ERROR_MISMATCH;
            RC_ERROR_INVALID_ADDRESS:    tlp_error[4*seg +: 4] = PCIE_ERROR_INVALID_ADDR;
            RC_ERROR_INVALID_TAG:        tlp_error[4*seg +: 4] = PCIE_ERROR_INVALID_TAG;
            RC_ERROR_FLR:                tlp_error[4*seg +: 4] = PCIE_ERROR_FLR;
            RC_ERROR_TIMEOUT:            tlp_error[4*seg +: 4] = PCIE_ERROR_TIMEOUT;
            default:                     tlp_error[4*seg +: 4] = PCIE_ERROR_NONE;
        endcase
    end

    if (stage_a_ready) begin
        rx_cpl_tlp_strb_next = 0;
        rx_cpl_tlp_valid_next = 0;
        rx_cpl_tlp_sop_next = 0;
        rx_cpl_tlp_eop_next = 0;
        if (TLP_DATA_WIDTH == 64) begin

            if (rc_valid_full[0]) begin
                rx_cpl_tlp_data_next = rc_data_full >> 32;
                rx_cpl_tlp_strb_next = rc_strb_full >> 1;
                if (rc_sop_full[0]) begin
                    tlp_frame_next = 1'b0;
                    rx_cpl_tlp_hdr_next = tlp_hdr;
                    rx_cpl_tlp_error_next = tlp_error;
                    if (rc_eop_full[0]) begin
                        rc_valid_int_next[0] = 1'b0;
                    end else if (rc_valid_full[1]) begin
                        rc_valid_int_next[0] = 1'b0;
                    end
                end else begin
                    rx_cpl_tlp_sop_next = !tlp_frame_reg;
                    rx_cpl_tlp_eop_next = 1'b0;
                    if (rc_eop_full[0]) begin
                        rx_cpl_tlp_strb_next = rc_strb_full[1];
                        rx_cpl_tlp_valid_next = 1'b1;
                        rc_valid_int_next[0] = 1'b0;
                        rx_cpl_tlp_eop_next = 1'b1;
                    end else if (rc_valid_full[1]) begin
                        rx_cpl_tlp_valid_next = 1'b1;
                        rc_valid_int_next[0] = 1'b0;
                        tlp_frame_next = 1'b1;
                    end
                end
            end
        end else begin

            for (seg = 0; seg < INT_TLP_SEG_COUNT; seg = seg + 1) begin
                if (rc_valid_full[seg]) begin
                    rx_cpl_tlp_data_next[INT_TLP_SEG_DATA_WIDTH*seg +: INT_TLP_SEG_DATA_WIDTH] = rc_data_full >> (96 + INT_TLP_SEG_DATA_WIDTH*seg);
                    if (rc_sop_full[seg]) begin
                        rx_cpl_tlp_hdr_next[TLP_HDR_WIDTH*seg +: TLP_HDR_WIDTH] = tlp_hdr[128*seg +: 128];
                        rx_cpl_tlp_error_next[4*seg +: 4] = tlp_error[4*seg +: 4];
                    end
                    rx_cpl_tlp_sop_next[seg] = rc_sop_full[seg];
                    if (rc_eop_full[seg]) begin
                        rx_cpl_tlp_strb_next[INT_TLP_SEG_STRB_WIDTH*seg +: INT_TLP_SEG_STRB_WIDTH] = rc_strb_full[INT_TLP_SEG_STRB_WIDTH*seg +: INT_TLP_SEG_STRB_WIDTH] >> 3;
                        if (rc_sop_full[seg] || rc_strb_eop_full[INT_TLP_SEG_STRB_WIDTH*seg +: INT_TLP_SEG_STRB_WIDTH] >> 3) begin
                            rx_cpl_tlp_eop_next[seg] = 1'b1;
                            rx_cpl_tlp_valid_next[seg] = 1'b1;
                        end
                        rc_valid_int_next[seg] = 1'b0;
                    end else begin
                        rx_cpl_tlp_strb_next[INT_TLP_SEG_STRB_WIDTH*seg +: INT_TLP_SEG_STRB_WIDTH] = rc_strb_full >> (3 + INT_TLP_SEG_STRB_WIDTH*seg);
                        if (rc_valid_full[seg+1]) begin
                            rx_cpl_tlp_eop_next[seg] = (rc_strb_eop_full[INT_TLP_SEG_STRB_WIDTH*(seg+1) +: INT_TLP_SEG_STRB_WIDTH] & 3'h7) != 0;
                            rx_cpl_tlp_valid_next[seg] = 1'b1;
                            rc_valid_int_next[seg] = 1'b0;
                        end
                    end
                end
            end
        end
    end

    if (s_axis_rc_tready && s_axis_rc_tvalid) begin
        rc_data_int_next = rc_data;
        rc_strb_int_next = rc_strb;
        rc_valid_int_next = rc_valid;
        rc_strb_eop_int_next = rc_strb_eop;
        rc_sop_int_next = rc_sop;
        rc_eop_int_next = rc_eop;
    end
end

always_ff @(posedge clk) begin
    rx_cpl_tlp_data_reg <= rx_cpl_tlp_data_next;
    rx_cpl_tlp_strb_reg <= rx_cpl_tlp_strb_next;
    rx_cpl_tlp_hdr_reg <= rx_cpl_tlp_hdr_next;
    rx_cpl_tlp_error_reg <= rx_cpl_tlp_error_next;
    rx_cpl_tlp_valid_reg <= rx_cpl_tlp_valid_next;
    rx_cpl_tlp_sop_reg <= rx_cpl_tlp_sop_next;
    rx_cpl_tlp_eop_reg <= rx_cpl_tlp_eop_next;
    tlp_frame_reg <= tlp_frame_next;

    rc_frame_reg <= rc_frame_next;

    rc_data_int_reg <= rc_data_int_next;
    rc_strb_int_reg <= rc_strb_int_next;
    rc_valid_int_reg <= rc_valid_int_next;
    rc_strb_eop_int_reg <= rc_strb_eop_int_next;
    rc_sop_int_reg <= rc_sop_int_next;
    rc_eop_int_reg <= rc_eop_int_next;

    if (rst) begin
        rx_cpl_tlp_valid_reg <= 0;

        rc_frame_reg <= 1'b0;
        rc_valid_int_reg <= 0;
    end
end

endmodule

`resetall
