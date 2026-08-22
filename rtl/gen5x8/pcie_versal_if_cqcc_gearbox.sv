// ---------------------------------------------------------------------------
// File        : pcie_versal_if_cqcc_gearbox.sv
// Description : The completer request and completion gearbox. Splits the 1024-bit AXIS
//               completer request stream down to the 512-bit AXIS user width and
//               merges completions back up, reporting a start alignment it cannot carry.
// Author      : Xiaohai Li <haixiaolee@gmail.com>
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------
`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_if_cqcc_gearbox #
(

    parameter AXIS_PCIE_DATA_WIDTH = 1024,
    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32),

    parameter AXIS_PCIE_CQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH == 1024 ? 465 : 231,

    parameter AXIS_PCIE_CC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH == 1024 ? 165 : 81,

    parameter USER_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH == 1024 ? 512 : AXIS_PCIE_DATA_WIDTH,
    parameter USER_KEEP_WIDTH = (USER_DATA_WIDTH/32),

    parameter USER_CQ_USER_WIDTH = 231,
    parameter USER_CC_USER_WIDTH = 81,

    parameter CQ_STRADDLE = 1,

    parameter CC_STRADDLE = 1,

    parameter CQ_SOP_PTR_DW = 8,
    parameter CC_SOP_PTR_DW = 8
)
(
    input  wire                                clk,
    input  wire                                rst,

    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]     s_axis_cq_tdata,
    input  wire [AXIS_PCIE_KEEP_WIDTH-1:0]     s_axis_cq_tkeep,
    input  wire                                s_axis_cq_tvalid,
    output wire                                s_axis_cq_tready,
    input  wire                                s_axis_cq_tlast,
    input  wire [AXIS_PCIE_CQ_USER_WIDTH-1:0]  s_axis_cq_tuser,

    output wire [USER_DATA_WIDTH-1:0]          m_axis_cq_tdata,
    output wire [USER_KEEP_WIDTH-1:0]          m_axis_cq_tkeep,
    output wire                                m_axis_cq_tvalid,
    input  wire                                m_axis_cq_tready,
    output wire                                m_axis_cq_tlast,
    output wire [USER_CQ_USER_WIDTH-1:0]       m_axis_cq_tuser,

    input  wire [USER_DATA_WIDTH-1:0]          s_axis_cc_tdata,
    input  wire [USER_KEEP_WIDTH-1:0]          s_axis_cc_tkeep,
    input  wire                                s_axis_cc_tvalid,
    output wire                                s_axis_cc_tready,
    input  wire                                s_axis_cc_tlast,
    input  wire [USER_CC_USER_WIDTH-1:0]       s_axis_cc_tuser,

    output wire [AXIS_PCIE_DATA_WIDTH-1:0]     m_axis_cc_tdata,
    output wire [AXIS_PCIE_KEEP_WIDTH-1:0]     m_axis_cc_tkeep,
    output wire                                m_axis_cc_tvalid,
    input  wire                                m_axis_cc_tready,
    output wire                                m_axis_cc_tlast,
    output wire [AXIS_PCIE_CC_USER_WIDTH-1:0]  m_axis_cc_tuser,

    output wire                                status_error_cq_slot_overflow,

    output wire                                status_error_cq_leading_gap,

    output wire                                status_error_cc_sop_align
);

initial begin
    case (AXIS_PCIE_DATA_WIDTH)
        512: begin
            if (AXIS_PCIE_CQ_USER_WIDTH != 231) begin
                $error("Error: CPM5 CQ tuser width must be 231 at 512 bits (instance %m)");
                $finish;
            end
            if (AXIS_PCIE_CC_USER_WIDTH != 81) begin
                $error("Error: CPM5 CC tuser width must be 81 at 512 bits (instance %m)");
                $finish;
            end
        end
        1024: begin
            if (AXIS_PCIE_CQ_USER_WIDTH != 465) begin
                $error("Error: CPM5 CQ tuser width must be 465 at 1024 bits (instance %m)");
                $finish;
            end
            if (AXIS_PCIE_CC_USER_WIDTH != 165) begin
                $error("Error: CPM5 CC tuser width must be 165 at 1024 bits (instance %m)");
                $finish;
            end
        end
        default: begin
            $error("Error: AXIS_PCIE_DATA_WIDTH must be 512 or 1024 (instance %m)");
            $finish;
        end
    endcase

    if (USER_CQ_USER_WIDTH != 231) begin
        $error("Error: user-side CQ tuser width must be 231, the CPM5-at-512 form (instance %m)");
        $finish;
    end
    if (USER_CC_USER_WIDTH != 81) begin
        $error("Error: user-side CC tuser width must be 81 (instance %m)");
        $finish;
    end
    if (AXIS_PCIE_KEEP_WIDTH * 32 != AXIS_PCIE_DATA_WIDTH) begin
        $error("Error: CPM5 interface requires dword granularity (instance %m)");
        $finish;
    end
    if (USER_KEEP_WIDTH * 32 != USER_DATA_WIDTH) begin
        $error("Error: user interface requires dword granularity (instance %m)");
        $finish;
    end
    if (CQ_SOP_PTR_DW != 4 && CQ_SOP_PTR_DW != 8) begin
        $error("Error: CQ_SOP_PTR_DW must be 4 or 8 dwords (instance %m)");
        $finish;
    end

    if (CC_SOP_PTR_DW != 8) begin
        $error("Error: CC_SOP_PTR_DW must be 8 dwords - a 4-dword weight cannot address the high half of a 1024-bit beat (instance %m)");
        $finish;
    end
end

if (AXIS_PCIE_DATA_WIDTH == 1024) begin : gen_gearbox_1024

    logic [AXIS_PCIE_DATA_WIDTH-1:0]     cq_reg_tdata = 0;
    logic [AXIS_PCIE_KEEP_WIDTH-1:0]     cq_reg_tkeep = 0;
    logic                               cq_reg_tvalid = 1'b0, cq_reg_tvalid_next;
    logic                               cq_reg_tlast = 1'b0;
    logic [AXIS_PCIE_CQ_USER_WIDTH-1:0]  cq_reg_tuser = 0;

    logic [AXIS_PCIE_DATA_WIDTH-1:0]     cq_skid_tdata = 0;
    logic [AXIS_PCIE_KEEP_WIDTH-1:0]     cq_skid_tkeep = 0;
    logic                               cq_skid_tvalid = 1'b0, cq_skid_tvalid_next;
    logic                               cq_skid_tlast = 1'b0;
    logic [AXIS_PCIE_CQ_USER_WIDTH-1:0]  cq_skid_tuser = 0;

    logic                               cq_in_ready_reg = 1'b0;

    logic                               cq_store_in_to_reg;
    logic                               cq_store_in_to_skid;
    logic                               cq_store_skid_to_reg;

    wire                                cq_reg_ready;

    always @* begin
        cq_reg_tvalid_next = cq_reg_tvalid;
        cq_skid_tvalid_next = cq_skid_tvalid;
        cq_store_in_to_reg = 1'b0;
        cq_store_in_to_skid = 1'b0;
        cq_store_skid_to_reg = 1'b0;

        if (cq_in_ready_reg) begin
            if (cq_reg_ready || !cq_reg_tvalid) begin
                cq_reg_tvalid_next = s_axis_cq_tvalid;
                cq_store_in_to_reg = 1'b1;
            end else begin
                cq_skid_tvalid_next = s_axis_cq_tvalid;
                cq_store_in_to_skid = 1'b1;
            end
        end else if (cq_reg_ready) begin
            cq_reg_tvalid_next = cq_skid_tvalid;
            cq_skid_tvalid_next = 1'b0;
            cq_store_skid_to_reg = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        cq_reg_tvalid <= cq_reg_tvalid_next;
        cq_skid_tvalid <= cq_skid_tvalid_next;
        cq_in_ready_reg <= !cq_skid_tvalid_next;

        if (cq_store_in_to_reg) begin
            cq_reg_tdata <= s_axis_cq_tdata;
            cq_reg_tkeep <= s_axis_cq_tkeep;
            cq_reg_tlast <= s_axis_cq_tlast;
            cq_reg_tuser <= s_axis_cq_tuser;
        end else if (cq_store_skid_to_reg) begin
            cq_reg_tdata <= cq_skid_tdata;
            cq_reg_tkeep <= cq_skid_tkeep;
            cq_reg_tlast <= cq_skid_tlast;
            cq_reg_tuser <= cq_skid_tuser;
        end

        if (cq_store_in_to_skid) begin
            cq_skid_tdata <= s_axis_cq_tdata;
            cq_skid_tkeep <= s_axis_cq_tkeep;
            cq_skid_tlast <= s_axis_cq_tlast;
            cq_skid_tuser <= s_axis_cq_tuser;
        end

        if (rst) begin
            cq_reg_tvalid <= 1'b0;
            cq_skid_tvalid <= 1'b0;
            cq_in_ready_reg <= 1'b0;
        end
    end

    assign s_axis_cq_tready = cq_in_ready_reg;

    wire [127:0] cq_byte_en_in        = cq_reg_tuser[127:0];
    wire [15:0]  cq_first_be_in       = cq_reg_tuser[143:128];
    wire [15:0]  cq_last_be_in        = cq_reg_tuser[159:144];
    wire [3:0]   cq_is_sop_in         = cq_reg_tuser[163:160];
    wire [7:0]   cq_sop_ptr_in        = cq_reg_tuser[171:164];
    wire [3:0]   cq_is_eop_in         = cq_reg_tuser[175:172];
    wire [19:0]  cq_eop_ptr_in        = cq_reg_tuser[195:176];
    wire         cq_discontinue_in    = cq_reg_tuser[196];
    wire [3:0]   cq_tph_present_in    = cq_reg_tuser[200:197];
    wire [7:0]   cq_tph_type_in       = cq_reg_tuser[208:201];
    wire [31:0]  cq_tph_st_tag_in     = cq_reg_tuser[240:209];
    wire [127:0] cq_parity_in         = cq_reg_tuser[368:241];
    wire [3:0]   cq_pasid_valid_in    = cq_reg_tuser[372:369];
    wire [79:0]  cq_pasid_in          = cq_reg_tuser[452:373];
    wire [3:0]   cq_pasid_exe_in      = cq_reg_tuser[456:453];
    wire [3:0]   cq_pasid_pmode_in    = cq_reg_tuser[460:457];
    wire [3:0]   cq_poisoned_in       = cq_reg_tuser[464:461];

    logic [31:0] cq_sop_at;
    logic [31:0] cq_eop_at;
    logic [31:0] cq_strb;

    logic       cq_open_next;

    logic [1:0]  cq_lo_is_sop,   cq_hi_is_sop;
    logic [3:0]  cq_lo_sop_ptr,  cq_hi_sop_ptr;
    logic [1:0]  cq_lo_is_eop,   cq_hi_is_eop;
    logic [7:0]  cq_lo_eop_ptr,  cq_hi_eop_ptr;
    logic [7:0]  cq_lo_first_be, cq_hi_first_be;
    logic [7:0]  cq_lo_last_be,  cq_hi_last_be;
    logic [1:0]  cq_lo_tph_present, cq_hi_tph_present;
    logic [3:0]  cq_lo_tph_type,  cq_hi_tph_type;
    logic [15:0] cq_lo_tph_st_tag, cq_hi_tph_st_tag;
    logic [1:0]  cq_lo_pasid_valid, cq_hi_pasid_valid;
    logic [39:0] cq_lo_pasid,     cq_hi_pasid;
    logic [1:0]  cq_lo_pasid_exe, cq_hi_pasid_exe;
    logic [1:0]  cq_lo_pasid_pmode, cq_hi_pasid_pmode;
    logic [1:0]  cq_lo_poisoned,  cq_hi_poisoned;

    logic       cq_err_slot;
    logic       cq_err_gap;

    logic [31:0] ag1_ref;
    logic [31:0] ag1_rec;

    logic       cq_phase_reg = 1'b0;
    logic       cq_open_reg  = 1'b0;

    logic [5:0]  cq_i;
    integer     cq_lo_ns, cq_hi_ns, cq_lo_ne, cq_hi_ne;
    logic [5:0]  cq_dw;
    logic       cq_last_dw_seen;
    logic [3:0]  cq_last_dw_lo, cq_last_dw_hi;
    logic       cq_open_walk;

    always @* begin
        cq_sop_at = 32'd0;
        cq_eop_at = 32'd0;

        cq_lo_is_sop = 2'd0;  cq_hi_is_sop = 2'd0;
        cq_lo_sop_ptr = 4'd0; cq_hi_sop_ptr = 4'd0;
        cq_lo_is_eop = 2'd0;  cq_hi_is_eop = 2'd0;
        cq_lo_eop_ptr = 8'd0; cq_hi_eop_ptr = 8'd0;
        cq_lo_first_be = 8'd0; cq_hi_first_be = 8'd0;
        cq_lo_last_be = 8'd0;  cq_hi_last_be = 8'd0;
        cq_lo_tph_present = 2'd0; cq_hi_tph_present = 2'd0;
        cq_lo_tph_type = 4'd0;    cq_hi_tph_type = 4'd0;
        cq_lo_tph_st_tag = 16'd0; cq_hi_tph_st_tag = 16'd0;
        cq_lo_pasid_valid = 2'd0; cq_hi_pasid_valid = 2'd0;
        cq_lo_pasid = 40'd0;      cq_hi_pasid = 40'd0;
        cq_lo_pasid_exe = 2'd0;   cq_hi_pasid_exe = 2'd0;
        cq_lo_pasid_pmode = 2'd0; cq_hi_pasid_pmode = 2'd0;
        cq_lo_poisoned = 2'd0;    cq_hi_poisoned = 2'd0;

        cq_lo_ns = 0; cq_hi_ns = 0;
        cq_lo_ne = 0; cq_hi_ne = 0;
        cq_err_slot = 1'b0;
        cq_err_gap  = 1'b0;
        cq_dw = 6'd0;
        cq_open_walk = cq_open_reg;
        cq_last_dw_lo = 4'd0;
        cq_last_dw_hi = 4'd0;
        cq_last_dw_seen = 1'b0;
        cq_strb = 32'd0;
        cq_open_next = cq_open_reg;

        if (CQ_STRADDLE) begin

            for (cq_i = 0; cq_i < 4; cq_i = cq_i + 1) begin
                if (cq_is_sop_in[cq_i[1:0]]) begin
                    cq_dw = cq_sop_ptr_in[cq_i*2 +: 2] * CQ_SOP_PTR_DW;
                    cq_sop_at[cq_dw[4:0]] = 1'b1;
                    if (cq_dw < 6'd16) begin
                        if (cq_lo_ns < 2) begin
                            cq_lo_is_sop[cq_lo_ns] = 1'b1;

                            cq_lo_sop_ptr    [cq_lo_ns*2  +: 2]  = cq_dw[3:2];
                            cq_lo_first_be   [cq_lo_ns*4  +: 4]  = cq_first_be_in   [cq_i*4  +: 4];
                            cq_lo_last_be    [cq_lo_ns*4  +: 4]  = cq_last_be_in    [cq_i*4  +: 4];
                            cq_lo_tph_present[cq_lo_ns]          = cq_tph_present_in[cq_i[1:0]];
                            cq_lo_tph_type   [cq_lo_ns*2  +: 2]  = cq_tph_type_in   [cq_i*2  +: 2];
                            cq_lo_tph_st_tag [cq_lo_ns*8  +: 8]  = cq_tph_st_tag_in [cq_i*8  +: 8];
                            cq_lo_pasid_valid[cq_lo_ns]          = cq_pasid_valid_in[cq_i[1:0]];
                            cq_lo_pasid      [cq_lo_ns*20 +: 20] = cq_pasid_in      [cq_i*20 +: 20];
                            cq_lo_pasid_exe  [cq_lo_ns]          = cq_pasid_exe_in  [cq_i[1:0]];
                            cq_lo_pasid_pmode[cq_lo_ns]          = cq_pasid_pmode_in[cq_i[1:0]];
                            cq_lo_poisoned   [cq_lo_ns]          = cq_poisoned_in   [cq_i[1:0]];
                            cq_lo_ns = cq_lo_ns + 1;
                        end else begin
                            cq_err_slot = 1'b1;
                        end
                    end else begin
                        if (cq_hi_ns < 2) begin
                            cq_hi_is_sop[cq_hi_ns] = 1'b1;
                            cq_hi_sop_ptr    [cq_hi_ns*2  +: 2]  = cq_dw[3:2];
                            cq_hi_first_be   [cq_hi_ns*4  +: 4]  = cq_first_be_in   [cq_i*4  +: 4];
                            cq_hi_last_be    [cq_hi_ns*4  +: 4]  = cq_last_be_in    [cq_i*4  +: 4];
                            cq_hi_tph_present[cq_hi_ns]          = cq_tph_present_in[cq_i[1:0]];
                            cq_hi_tph_type   [cq_hi_ns*2  +: 2]  = cq_tph_type_in   [cq_i*2  +: 2];
                            cq_hi_tph_st_tag [cq_hi_ns*8  +: 8]  = cq_tph_st_tag_in [cq_i*8  +: 8];
                            cq_hi_pasid_valid[cq_hi_ns]          = cq_pasid_valid_in[cq_i[1:0]];
                            cq_hi_pasid      [cq_hi_ns*20 +: 20] = cq_pasid_in      [cq_i*20 +: 20];
                            cq_hi_pasid_exe  [cq_hi_ns]          = cq_pasid_exe_in  [cq_i[1:0]];
                            cq_hi_pasid_pmode[cq_hi_ns]          = cq_pasid_pmode_in[cq_i[1:0]];
                            cq_hi_poisoned   [cq_hi_ns]          = cq_poisoned_in   [cq_i[1:0]];
                            cq_hi_ns = cq_hi_ns + 1;
                        end else begin
                            cq_err_slot = 1'b1;
                        end
                    end
                end
            end

            for (cq_i = 0; cq_i < 4; cq_i = cq_i + 1) begin
                if (cq_is_eop_in[cq_i[1:0]]) begin
                    cq_dw = {1'b0, cq_eop_ptr_in[cq_i*5 +: 5]};
                    cq_eop_at[cq_dw[4:0]] = 1'b1;
                    if (cq_dw < 6'd16) begin
                        if (cq_lo_ne < 2) begin
                            cq_lo_is_eop[cq_lo_ne] = 1'b1;
                            cq_lo_eop_ptr[cq_lo_ne*4 +: 4] = cq_dw[3:0];
                            cq_lo_ne = cq_lo_ne + 1;
                        end else begin
                            cq_err_slot = 1'b1;
                        end
                    end else begin
                        if (cq_hi_ne < 2) begin
                            cq_hi_is_eop[cq_hi_ne] = 1'b1;
                            cq_hi_eop_ptr[cq_hi_ne*4 +: 4] = cq_dw[3:0];
                            cq_hi_ne = cq_hi_ne + 1;
                        end else begin
                            cq_err_slot = 1'b1;
                        end
                    end
                end
            end

            cq_open_walk = cq_open_reg;
            for (cq_i = 0; cq_i < 32; cq_i = cq_i + 1) begin
                if (cq_sop_at[cq_i[4:0]]) begin
                    cq_open_walk = 1'b1;
                end
                cq_strb[cq_i[4:0]] = cq_open_walk;
                if (cq_eop_at[cq_i[4:0]]) begin
                    cq_open_walk = 1'b0;
                end
            end
            cq_open_next = cq_open_walk;

            if (cq_strb[15:0] != 16'd0 && !cq_strb[0]) begin
                cq_err_gap = 1'b1;
            end
            if (cq_strb[31:16] != 16'd0 && !cq_strb[16]) begin
                cq_err_gap = 1'b1;
            end

            // synthesis translate_off
            ag1_ref = cq_eop_at;
            ag1_rec = 32'd0;
            for (cq_i = 0; cq_i < 2; cq_i = cq_i + 1) begin
                if (cq_lo_is_eop[cq_i[0]]) begin
                    ag1_rec[cq_lo_eop_ptr[cq_i*4 +: 4]] = 1'b1;
                end
                if (cq_hi_is_eop[cq_i[0]]) begin
                    ag1_rec[{1'b1, cq_hi_eop_ptr[cq_i*4 +: 4]}] = 1'b1;
                end
            end

            if (!cq_err_slot && ag1_rec !== ag1_ref) begin
                $error("T36G_GEARBOX_ASSERT A-G1 FAIL cq eop set not preserved across the 1024->2x512 split: ref=%b rec=%b lo_is_eop=%b lo_ptr=%h hi_is_eop=%b hi_ptr=%h (instance %m) -- R-0 EOP ALIASING",
                    ag1_ref, ag1_rec, cq_lo_is_eop, cq_lo_eop_ptr,
                    cq_hi_is_eop, cq_hi_eop_ptr);
            end
            // synthesis translate_on

        end else begin

            cq_strb = cq_reg_tkeep;
            cq_open_next = !cq_reg_tlast;

            cq_lo_first_be[3:0] = cq_first_be_in[3:0];
            cq_lo_last_be [3:0] = cq_last_be_in [3:0];
            cq_hi_first_be[3:0] = cq_first_be_in[3:0];
            cq_hi_last_be [3:0] = cq_last_be_in [3:0];
            cq_lo_tph_present[0]     = cq_tph_present_in[0];
            cq_lo_tph_type   [1:0]   = cq_tph_type_in[1:0];
            cq_lo_tph_st_tag [7:0]   = cq_tph_st_tag_in[7:0];
            cq_lo_pasid_valid[0]     = cq_pasid_valid_in[0];
            cq_lo_pasid      [19:0]  = cq_pasid_in[19:0];
            cq_lo_pasid_exe  [0]     = cq_pasid_exe_in[0];
            cq_lo_pasid_pmode[0]     = cq_pasid_pmode_in[0];
            cq_lo_poisoned   [0]     = cq_poisoned_in[0];
            cq_hi_tph_present[0]     = cq_tph_present_in[0];
            cq_hi_tph_type   [1:0]   = cq_tph_type_in[1:0];
            cq_hi_tph_st_tag [7:0]   = cq_tph_st_tag_in[7:0];
            cq_hi_pasid_valid[0]     = cq_pasid_valid_in[0];
            cq_hi_pasid      [19:0]  = cq_pasid_in[19:0];
            cq_hi_pasid_exe  [0]     = cq_pasid_exe_in[0];
            cq_hi_pasid_pmode[0]     = cq_pasid_pmode_in[0];
            cq_hi_poisoned   [0]     = cq_poisoned_in[0];

            cq_last_dw_lo = 4'd0;
            cq_last_dw_hi = 4'd0;
            cq_last_dw_seen = 1'b0;
            for (cq_i = 0; cq_i < 16; cq_i = cq_i + 1) begin
                if (cq_strb[cq_i[4:0]]) begin
                    cq_last_dw_lo = cq_i[3:0];
                end
                if (cq_strb[16+cq_i[3:0]]) begin
                    cq_last_dw_hi = cq_i[3:0];
                    cq_last_dw_seen = 1'b1;
                end
            end
            cq_lo_is_sop[0] = !cq_open_reg;
            cq_lo_sop_ptr[1:0] = 2'd0;
            cq_hi_is_sop[0] = 1'b0;
            if (cq_last_dw_seen) begin
                cq_hi_is_eop[0]      = cq_reg_tlast;
                cq_hi_eop_ptr[3:0]   = cq_last_dw_hi;
            end else begin
                cq_lo_is_eop[0]      = cq_reg_tlast;
                cq_lo_eop_ptr[3:0]   = cq_last_dw_lo;
            end
        end
    end

    wire cq_lo_occ = |cq_strb[15:0];
    wire cq_hi_occ = |cq_strb[31:16];
    wire cq_any    = cq_lo_occ | cq_hi_occ;

    wire cq_sel_hi = cq_phase_reg | ~cq_lo_occ;

    wire cq_last_half = ~(~cq_phase_reg & cq_lo_occ & cq_hi_occ);

    wire cq_beat_closes = CQ_STRADDLE ? ((|cq_eop_at) & ~cq_open_next)
                                      : cq_reg_tlast;

    assign m_axis_cq_tvalid = cq_reg_tvalid & cq_any;

    assign cq_reg_ready = cq_any ? (m_axis_cq_tready & cq_last_half) : 1'b1;

    assign m_axis_cq_tdata = cq_sel_hi ? cq_reg_tdata[1023:512]
                                      : cq_reg_tdata[511:0];
    assign m_axis_cq_tkeep = cq_sel_hi ? cq_strb[31:16] : cq_strb[15:0];
    assign m_axis_cq_tlast = cq_last_half & cq_beat_closes;

    wire cq_lo_discontinue = cq_discontinue_in & ~cq_hi_occ;
    wire cq_hi_discontinue = cq_discontinue_in;

    wire [230:0] cq_tuser_lo = {
        cq_lo_poisoned,
        cq_lo_pasid_pmode,
        cq_lo_pasid_exe,
        cq_lo_pasid,
        cq_lo_pasid_valid,
        cq_parity_in[63:0],
        cq_lo_tph_st_tag,
        cq_lo_tph_type,
        cq_lo_tph_present,
        cq_lo_discontinue,
        cq_lo_eop_ptr,
        cq_lo_is_eop,
        cq_lo_sop_ptr,
        cq_lo_is_sop,
        cq_byte_en_in[63:0],
        cq_lo_last_be,
        cq_lo_first_be
    };

    wire [230:0] cq_tuser_hi = {
        cq_hi_poisoned,
        cq_hi_pasid_pmode,
        cq_hi_pasid_exe,
        cq_hi_pasid,
        cq_hi_pasid_valid,
        cq_parity_in[127:64],
        cq_hi_tph_st_tag,
        cq_hi_tph_type,
        cq_hi_tph_present,
        cq_hi_discontinue,
        cq_hi_eop_ptr,
        cq_hi_is_eop,
        cq_hi_sop_ptr,
        cq_hi_is_sop,
        cq_byte_en_in[127:64],
        cq_hi_last_be,
        cq_hi_first_be
    };

    assign m_axis_cq_tuser = cq_sel_hi ? cq_tuser_hi : cq_tuser_lo;

    always_ff @(posedge clk) begin
        if (rst) begin
            cq_phase_reg <= 1'b0;
            cq_open_reg  <= 1'b0;
        end else begin
            if (cq_reg_tvalid && cq_any && m_axis_cq_tready) begin
                if (cq_last_half) begin
                    cq_phase_reg <= 1'b0;
                    cq_open_reg  <= cq_open_next;
                end else begin
                    cq_phase_reg <= 1'b1;
                end
            end else if (cq_reg_tvalid && !cq_any) begin

                cq_open_reg <= cq_open_next;
            end
        end
    end

    assign status_error_cq_slot_overflow = cq_reg_tvalid & cq_err_slot;
    assign status_error_cq_leading_gap   = cq_reg_tvalid & cq_err_gap;

    wire [1:0]  cc_is_sop_in    = s_axis_cc_tuser[1:0];
    wire [3:0]  cc_sop_ptr_in   = s_axis_cc_tuser[5:2];
    wire [1:0]  cc_is_eop_in    = s_axis_cc_tuser[7:6];
    wire [7:0]  cc_eop_ptr_in   = s_axis_cc_tuser[15:8];
    wire        cc_disc_in      = s_axis_cc_tuser[16];
    wire [63:0] cc_parity_in    = s_axis_cc_tuser[80:17];

    logic [1:0]  cc_map_sop;
    logic [3:0]  cc_map_sop_ptr;
    logic [1:0]  cc_map_eop;
    logic [9:0]  cc_map_eop_ptr;
    logic       cc_map_align_err;
    logic       cc_map_open_after;

    logic [15:0] cc_sop_at, cc_eop_at;
    logic       cc_open_walk;
    logic [4:0]  cc_dw;
    logic [4:0]  cc_last_dw;
    logic [4:0]  cc_i;

    logic         cc_hold_valid_reg = 1'b0;
    logic [511:0]  cc_hold_data_reg  = 512'd0;
    logic [15:0]   cc_hold_keep_reg  = 16'd0;
    logic [63:0]   cc_hold_parity_reg = 64'd0;
    logic         cc_hold_disc_reg  = 1'b0;
    logic [1:0]    cc_hold_sop_reg   = 2'd0;
    logic [3:0]    cc_hold_sop_ptr_reg = 4'd0;
    logic [1:0]    cc_hold_eop_reg   = 2'd0;
    logic [9:0]    cc_hold_eop_ptr_reg = 10'd0;
    logic         cc_open_reg       = 1'b0;

    wire cc_open_in = cc_hold_valid_reg ? 1'b1 : cc_open_reg;

    always @* begin
        logic [1:0] cc_j;
        cc_map_sop       = 2'd0;
        cc_map_sop_ptr   = 4'd0;
        cc_map_eop       = 2'd0;
        cc_map_eop_ptr   = 10'd0;
        cc_map_align_err = 1'b0;
        cc_sop_at        = 16'd0;
        cc_eop_at        = 16'd0;
        cc_dw            = 5'd0;
        cc_last_dw       = 5'd0;
        cc_open_walk     = cc_open_in;
        cc_map_open_after = cc_open_in;

        if (CC_STRADDLE) begin
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_is_sop_in[cc_j[0]]) begin

                    cc_dw = {1'b0, cc_sop_ptr_in[cc_j*2 +: 2], 2'd0};
                    cc_sop_at[cc_dw[3:0]] = 1'b1;
                    cc_map_sop[cc_j[0]] = 1'b1;
                    if (CC_SOP_PTR_DW == 8) begin

                        if (cc_dw[2:0] != 3'd0) begin
                            cc_map_align_err = 1'b1;
                        end
                        cc_map_sop_ptr[cc_j*2 +: 2] = {1'b0, cc_dw[3]};
                    end else begin
                        cc_map_sop_ptr[cc_j*2 +: 2] = cc_dw[3:2];
                    end
                end
            end
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_is_eop_in[cc_j[0]]) begin
                    cc_dw = {1'b0, cc_eop_ptr_in[cc_j*4 +: 4]};
                    cc_eop_at[cc_dw[3:0]] = 1'b1;
                    cc_map_eop[cc_j[0]] = 1'b1;
                    cc_map_eop_ptr[cc_j*5 +: 5] = cc_dw;
                end
            end
            cc_open_walk = cc_open_in;
            for (cc_i = 0; cc_i < 16; cc_i = cc_i + 1) begin
                if (cc_sop_at[cc_i[3:0]]) begin
                    cc_open_walk = 1'b1;
                end
                if (cc_eop_at[cc_i[3:0]]) begin
                    cc_open_walk = 1'b0;
                end
            end
            cc_map_open_after = cc_open_walk;
        end else begin

            for (cc_i = 0; cc_i < 16; cc_i = cc_i + 1) begin
                if (s_axis_cc_tkeep[cc_i[3:0]]) begin
                    cc_last_dw = cc_i;
                end
            end
            cc_map_sop[0]        = !cc_open_in;
            cc_map_eop[0]        = s_axis_cc_tlast;
            cc_map_eop_ptr[4:0]  = cc_last_dw;
            cc_map_open_after    = !s_axis_cc_tlast;
        end
    end

    wire cc_single_ok = ~cc_map_open_after;

    logic [3:0]  cc_out_sop;
    logic [7:0]  cc_out_sop_ptr;
    logic [3:0]  cc_out_eop;
    logic [19:0] cc_out_eop_ptr;
    integer     cc_n;
    logic [1:0]  cc_ptr8_biased;

    always @* begin
        logic [1:0] cc_j;
        cc_out_sop     = 4'd0;
        cc_out_sop_ptr = 8'd0;
        cc_out_eop     = 4'd0;
        cc_out_eop_ptr = 20'd0;
        cc_ptr8_biased = 2'd0;
        cc_n = 0;

        if (cc_hold_valid_reg) begin

            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_hold_sop_reg[cc_j[0]]) begin
                    cc_out_sop[cc_n] = 1'b1;
                    cc_out_sop_ptr[cc_n*2 +: 2] = cc_hold_sop_ptr_reg[cc_j*2 +: 2];
                    cc_n = cc_n + 1;
                end
            end
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_map_sop[cc_j[0]]) begin

                    cc_ptr8_biased = cc_map_sop_ptr[cc_j*2 +: 2] + 2'd2;
                    cc_out_sop[cc_n] = 1'b1;
                    cc_out_sop_ptr[cc_n*2 +: 2] = cc_ptr8_biased;
                    cc_n = cc_n + 1;
                end
            end
            cc_n = 0;
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_hold_eop_reg[cc_j[0]]) begin
                    cc_out_eop[cc_n] = 1'b1;
                    cc_out_eop_ptr[cc_n*5 +: 5] = cc_hold_eop_ptr_reg[cc_j*5 +: 5];
                    cc_n = cc_n + 1;
                end
            end
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_map_eop[cc_j[0]]) begin
                    cc_out_eop[cc_n] = 1'b1;
                    cc_out_eop_ptr[cc_n*5 +: 5] = cc_map_eop_ptr[cc_j*5 +: 5] + 5'd16;
                    cc_n = cc_n + 1;
                end
            end
        end else begin

            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_map_sop[cc_j[0]]) begin
                    cc_out_sop[cc_n] = 1'b1;
                    cc_out_sop_ptr[cc_n*2 +: 2] = cc_map_sop_ptr[cc_j*2 +: 2];
                    cc_n = cc_n + 1;
                end
            end
            cc_n = 0;
            for (cc_j = 0; cc_j < 2; cc_j = cc_j + 1) begin
                if (cc_map_eop[cc_j[0]]) begin
                    cc_out_eop[cc_n] = 1'b1;
                    cc_out_eop_ptr[cc_n*5 +: 5] = cc_map_eop_ptr[cc_j*5 +: 5];
                    cc_n = cc_n + 1;
                end
            end
        end
    end

    assign m_axis_cc_tdata = cc_hold_valid_reg ? {s_axis_cc_tdata, cc_hold_data_reg}
                                              : {512'd0, s_axis_cc_tdata};
    assign m_axis_cc_tkeep = cc_hold_valid_reg ? {s_axis_cc_tkeep, cc_hold_keep_reg}
                                              : {16'd0, s_axis_cc_tkeep};
    assign m_axis_cc_tlast = s_axis_cc_tlast;
    assign m_axis_cc_tuser = {
        (cc_hold_valid_reg ? {cc_parity_in, cc_hold_parity_reg}
                           : {64'd0, cc_parity_in}),
        (cc_hold_valid_reg ? (cc_disc_in | cc_hold_disc_reg)
                           : cc_disc_in),
        cc_out_eop_ptr,
        cc_out_eop,
        cc_out_sop_ptr,
        cc_out_sop
    };

    assign m_axis_cc_tvalid = s_axis_cc_tvalid & (cc_hold_valid_reg | cc_single_ok);
    assign s_axis_cc_tready = (cc_hold_valid_reg | cc_single_ok) ? m_axis_cc_tready
                                                                : 1'b1;

    always_ff @(posedge clk) begin
        if (rst) begin
            cc_hold_valid_reg <= 1'b0;
            cc_open_reg       <= 1'b0;
        end else begin
            if (cc_hold_valid_reg) begin
                if (s_axis_cc_tvalid && m_axis_cc_tready) begin
                    cc_hold_valid_reg <= 1'b0;
                    cc_open_reg       <= cc_map_open_after;
                end
            end else if (s_axis_cc_tvalid) begin
                if (cc_single_ok) begin
                    if (m_axis_cc_tready) begin
                        cc_open_reg <= cc_map_open_after;
                    end
                end else begin
                    cc_hold_valid_reg   <= 1'b1;
                    cc_hold_data_reg    <= s_axis_cc_tdata;
                    cc_hold_keep_reg    <= s_axis_cc_tkeep;
                    cc_hold_parity_reg  <= cc_parity_in;
                    cc_hold_disc_reg    <= cc_disc_in;
                    cc_hold_sop_reg     <= cc_map_sop;
                    cc_hold_sop_ptr_reg <= cc_map_sop_ptr;
                    cc_hold_eop_reg     <= cc_map_eop;
                    cc_hold_eop_ptr_reg <= cc_map_eop_ptr;
                end
            end
        end
    end

    assign status_error_cc_sop_align = s_axis_cc_tvalid & cc_map_align_err;

    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst) begin
            if (status_error_cq_slot_overflow) begin
                $display("ERROR %t: pcie_versal_if_cqcc_gearbox %m: CQ straddle metadata overflow - more than 2 TLP starts/ends in one 512-bit half (is_sop=%b is_eop=%b sop_ptr=%b eop_ptr=%b). Check CQ_SOP_PTR_DW.",
                    $time, cq_is_sop_in, cq_is_eop_in, cq_sop_ptr_in, cq_eop_ptr_in);
            end
            if (status_error_cq_leading_gap) begin
                $display("ERROR %t: pcie_versal_if_cqcc_gearbox %m: CQ leading gap in a 512-bit half, not expressible (strb=%b open=%b).",
                    $time, cq_strb, cq_open_reg);
            end
            if (status_error_cc_sop_align) begin
                $display("ERROR %t: pcie_versal_if_cqcc_gearbox %m: CC TLP start is not on a %0d-dword boundary, not expressible at 1024 bits (is_sop=%b sop_ptr=%b).",
                    $time, CC_SOP_PTR_DW, cc_is_sop_in, cc_sop_ptr_in);
            end
        end
    end
    // synthesis translate_on

end else begin : gen_bypass_512

    assign m_axis_cq_tdata  = s_axis_cq_tdata;
    assign m_axis_cq_tkeep  = s_axis_cq_tkeep;
    assign m_axis_cq_tvalid = s_axis_cq_tvalid;
    assign s_axis_cq_tready = m_axis_cq_tready;
    assign m_axis_cq_tlast  = s_axis_cq_tlast;
    assign m_axis_cq_tuser  = s_axis_cq_tuser;

    assign m_axis_cc_tdata  = s_axis_cc_tdata;
    assign m_axis_cc_tkeep  = s_axis_cc_tkeep;
    assign m_axis_cc_tvalid = s_axis_cc_tvalid;
    assign s_axis_cc_tready = m_axis_cc_tready;
    assign m_axis_cc_tlast  = s_axis_cc_tlast;
    assign m_axis_cc_tuser  = s_axis_cc_tuser;

    assign status_error_cq_slot_overflow = 1'b0;
    assign status_error_cq_leading_gap   = 1'b0;
    assign status_error_cc_sop_align     = 1'b0;

end

endmodule

`resetall
