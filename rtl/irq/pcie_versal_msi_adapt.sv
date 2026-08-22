// ---------------------------------------------------------------------------
// File        : pcie_versal_msi_adapt.sv
// Description : Adapts the CPM5 pcie3_cfg_msi sideband to the MSI interface a
//               PCIe DMA library expects. Every field keeps its meaning; the
//               five of unequal width widen, and a guard per field asserts it.
// Author      : Xiaohai Li <haixiaolee@gmail.com>
//
//
// Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
// SPDX-License-Identifier: BSD-2-Clause-Views
// ---------------------------------------------------------------------------

`resetall
`timescale 1ns / 1ps
`default_nettype none

module pcie_versal_msi_adapt #
(
    parameter US_ENABLE_W       = 4,
    parameter US_MMENABLE_W     = 12,
    parameter US_SELECT_W       = 2,
    parameter US_PSFN_W         = 2,
    parameter US_FUNC_NUM_W     = 8,

    parameter CPM5_ENABLE_W     = 1,
    parameter CPM5_MMENABLE_W   = 3,
    parameter CPM5_SELECT_W     = 4,
    parameter CPM5_PSFN_W       = 4,
    parameter CPM5_FUNC_NUM_W   = 16,

    parameter VECTOR_W          = 32,
    parameter ATTR_W            = 3,
    parameter TPH_TYPE_W        = 2,
    parameter TPH_ST_TAG_W      = 8
)
(
    input  wire [CPM5_ENABLE_W-1:0]    cpm_cfg_msi_enable,
    input  wire [CPM5_MMENABLE_W-1:0]  cpm_cfg_msi_mmenable,
    input  wire                        cpm_cfg_msi_mask_update,
    input  wire [VECTOR_W-1:0]         cpm_cfg_msi_data,
    input  wire                        cpm_cfg_msi_sent,
    input  wire                        cpm_cfg_msi_fail,

    output wire [VECTOR_W-1:0]         cpm_cfg_msi_int_vector,
    output wire [CPM5_SELECT_W-1:0]    cpm_cfg_msi_select,
    output wire [VECTOR_W-1:0]         cpm_cfg_msi_pending_status,
    output wire                        cpm_cfg_msi_pending_status_data_enable,
    output wire [CPM5_PSFN_W-1:0]      cpm_cfg_msi_pending_status_function_num,
    output wire [ATTR_W-1:0]           cpm_cfg_msi_attr,
    output wire                        cpm_cfg_msi_tph_present,
    output wire [TPH_TYPE_W-1:0]       cpm_cfg_msi_tph_type,
    output wire [TPH_ST_TAG_W-1:0]     cpm_cfg_msi_tph_st_tag,
    output wire [CPM5_FUNC_NUM_W-1:0]  cpm_cfg_msi_function_number,

    output wire [US_ENABLE_W-1:0]      us_cfg_interrupt_msi_enable,
    output wire [US_MMENABLE_W-1:0]    us_cfg_interrupt_msi_mmenable,
    output wire                        us_cfg_interrupt_msi_mask_update,
    output wire [VECTOR_W-1:0]         us_cfg_interrupt_msi_data,
    output wire                        us_cfg_interrupt_msi_sent,
    output wire                        us_cfg_interrupt_msi_fail,

    input  wire [VECTOR_W-1:0]         us_cfg_interrupt_msi_int,
    input  wire [US_SELECT_W-1:0]      us_cfg_interrupt_msi_select,
    input  wire [VECTOR_W-1:0]         us_cfg_interrupt_msi_pending_status,
    input  wire                        us_cfg_interrupt_msi_pending_status_data_enable,
    input  wire [US_PSFN_W-1:0]        us_cfg_interrupt_msi_pending_status_function_num,
    input  wire [ATTR_W-1:0]           us_cfg_interrupt_msi_attr,
    input  wire                        us_cfg_interrupt_msi_tph_present,
    input  wire [TPH_TYPE_W-1:0]       us_cfg_interrupt_msi_tph_type,
    input  wire [TPH_ST_TAG_W-1:0]     us_cfg_interrupt_msi_tph_st_tag,
    input  wire [US_FUNC_NUM_W-1:0]    us_cfg_interrupt_msi_function_number
);

initial begin
    if (US_ENABLE_W < CPM5_ENABLE_W) begin
        $error("Error: US enable width (%0d) < CPM5 (%0d) - would truncate msi_enable (instance %m)", US_ENABLE_W, CPM5_ENABLE_W);
        $finish;
    end
    if (US_MMENABLE_W < CPM5_MMENABLE_W) begin
        $error("Error: US mmenable width (%0d) < CPM5 (%0d) - would truncate msi_mmenable (instance %m)", US_MMENABLE_W, CPM5_MMENABLE_W);
        $finish;
    end
    if (CPM5_SELECT_W < US_SELECT_W) begin
        $error("Error: CPM5 select width (%0d) < US (%0d) - would truncate msi_select (instance %m)", CPM5_SELECT_W, US_SELECT_W);
        $finish;
    end
    if (CPM5_PSFN_W < US_PSFN_W) begin
        $error("Error: CPM5 pending_status_function_number width (%0d) < US (%0d) (instance %m)", CPM5_PSFN_W, US_PSFN_W);
        $finish;
    end
    if (CPM5_FUNC_NUM_W < US_FUNC_NUM_W) begin
        $error("Error: CPM5 function_number width (%0d) < US (%0d) (instance %m)", CPM5_FUNC_NUM_W, US_FUNC_NUM_W);
        $finish;
    end
    if (VECTOR_W != 32) begin
        $error("Error: MSI vector width must be 32 - MSI's architectural maximum and the consumer's interrupt vector register width (instance %m)", VECTOR_W);
        $finish;
    end
    if (ATTR_W != 3 || TPH_TYPE_W != 2 || TPH_ST_TAG_W != 8) begin
        $error("Error: attr/tph widths are fixed by the PCIe spec on both faces (instance %m)");
        $finish;
    end
end

assign us_cfg_interrupt_msi_enable   = {{(US_ENABLE_W-CPM5_ENABLE_W){1'b0}}, cpm_cfg_msi_enable};

assign us_cfg_interrupt_msi_mmenable = {{(US_MMENABLE_W-CPM5_MMENABLE_W){1'b0}}, cpm_cfg_msi_mmenable};

assign us_cfg_interrupt_msi_mask_update = cpm_cfg_msi_mask_update;
assign us_cfg_interrupt_msi_data        = cpm_cfg_msi_data;

assign us_cfg_interrupt_msi_sent        = cpm_cfg_msi_sent;
assign us_cfg_interrupt_msi_fail        = cpm_cfg_msi_fail;

assign cpm_cfg_msi_int_vector = us_cfg_interrupt_msi_int;

assign cpm_cfg_msi_select     = {{(CPM5_SELECT_W-US_SELECT_W){1'b0}}, us_cfg_interrupt_msi_select};

assign cpm_cfg_msi_pending_status                  = us_cfg_interrupt_msi_pending_status;
assign cpm_cfg_msi_pending_status_data_enable      = us_cfg_interrupt_msi_pending_status_data_enable;
assign cpm_cfg_msi_pending_status_function_num  =
    {{(CPM5_PSFN_W-US_PSFN_W){1'b0}}, us_cfg_interrupt_msi_pending_status_function_num};

assign cpm_cfg_msi_attr        = us_cfg_interrupt_msi_attr;
assign cpm_cfg_msi_tph_present = us_cfg_interrupt_msi_tph_present;
assign cpm_cfg_msi_tph_type    = us_cfg_interrupt_msi_tph_type;
assign cpm_cfg_msi_tph_st_tag  = us_cfg_interrupt_msi_tph_st_tag;

assign cpm_cfg_msi_function_number =
    {{(CPM5_FUNC_NUM_W-US_FUNC_NUM_W){1'b0}}, us_cfg_interrupt_msi_function_number};

endmodule

`resetall
