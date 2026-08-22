// ---------------------------------------------------------------------------
// File        : fpga.v
// Description : Top level of the TU03 Gen5 x8, 1024-bit AXIS, endpoint example.
//               Instantiates the CPM5 block design and fpga_core, and carries
//               the device pins the example reports its status on.
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

module fpga (

    input  wire        gt_refclk1_clk_p,
    input  wire        gt_refclk1_clk_n,
    input  wire [7:0]  pcie_rx_p,
    input  wire [7:0]  pcie_rx_n,
    output wire [7:0]  pcie_tx_p,
    output wire [7:0]  pcie_tx_n,

    output wire        gpio_lnk_up_o,
    output wire        gpio_poison_seen_o,
    output wire        gpio_gearbox_err_o,
    output wire        gpio_uncor_err_o
);

parameter AXIS_PCIE_DATA_WIDTH    = 1024;
parameter AXIS_PCIE_KEEP_WIDTH    = (AXIS_PCIE_DATA_WIDTH/32);

parameter AXIS_PCIE_RQ_USER_WIDTH = 373;
parameter AXIS_PCIE_RC_USER_WIDTH = 337;
parameter AXIS_PCIE_CQ_USER_WIDTH = 465;
parameter AXIS_PCIE_CC_USER_WIDTH = 165;

parameter RC_STRADDLE = 1;
parameter RQ_STRADDLE = 1;
parameter CQ_STRADDLE = 1;
parameter CC_STRADDLE = 1;

parameter RQ_SEQ_NUM_WIDTH  = 6;
parameter RQ_SEQ_NUM_ENABLE = 1;

parameter PCIE_TAG_COUNT = 256;

parameter BAR0_APERTURE = 24;
parameter BAR2_APERTURE = 24;
parameter BAR4_APERTURE = 16;

parameter RQ_STRADDLE_ENC = 1;
parameter RC_SOP_COMPACT    = 1;
parameter RC_FIFO_SEG_COUNT = 4;

wire pcie_user_clk;
wire pcie_user_reset;
wire pcie_user_lnk_up;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rq_tkeep;
wire                               axis_rq_tlast;
wire                               axis_rq_tready;
wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] axis_rq_tuser;
wire                               axis_rq_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rc_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rc_tkeep;
wire                               axis_rc_tlast;
wire                               axis_rc_tready;
wire [AXIS_PCIE_RC_USER_WIDTH-1:0] axis_rc_tuser;
wire                               axis_rc_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cq_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cq_tkeep;
wire                               axis_cq_tlast;
wire                               axis_cq_tready;
wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] axis_cq_tuser;
wire                               axis_cq_tvalid;

wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cc_tdata;
wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cc_tkeep;
wire                               axis_cc_tlast;
wire                               axis_cc_tready;
wire [AXIS_PCIE_CC_USER_WIDTH-1:0] axis_cc_tuser;
wire                               axis_cc_tvalid;

wire [2:0]  cfg_max_payload;
wire [2:0]  cfg_max_read_req;
wire [3:0]  cfg_rcb_status;

wire [9:0]  cfg_mgmt_addr;
wire [7:0]  cfg_mgmt_function_number;
wire        cfg_mgmt_write;
wire [31:0] cfg_mgmt_write_data;
wire [3:0]  cfg_mgmt_byte_enable;
wire        cfg_mgmt_read;
wire [31:0] cfg_mgmt_read_data;
wire        cfg_mgmt_read_write_done;

wire [7:0]  cfg_fc_ph;
wire [11:0] cfg_fc_pd;
wire [7:0]  cfg_fc_nph;
wire [11:0] cfg_fc_npd;
wire [7:0]  cfg_fc_cplh;
wire [11:0] cfg_fc_cpld;
wire [2:0]  cfg_fc_sel;

wire [3:0]  cfg_interrupt_msix_enable;
wire [3:0]  cfg_interrupt_msix_mask;
wire [63:0] cfg_interrupt_msix_address;
wire [31:0] cfg_interrupt_msix_data;
wire        cfg_interrupt_msix_int;
wire [1:0]  cfg_interrupt_msix_vec_pending;
wire        cfg_interrupt_msix_vec_pending_status;
wire        cfg_interrupt_msix_sent;
wire        cfg_interrupt_msix_fail;
wire [7:0]  cfg_interrupt_msi_function_number;

wire        status_error_cor;
wire        status_error_uncor;

wire        status_error_cq_slot_overflow;
wire        status_error_cq_leading_gap;
wire        status_error_cc_sop_align;
wire [1:0]  sts_cq_poisoned_tlp;
wire        sts_cq_poisoned_seen;

wire [RQ_SEQ_NUM_WIDTH-1:0] pcie_rq_seq_num0;
wire                        pcie_rq_seq_num_vld0;
wire [RQ_SEQ_NUM_WIDTH-1:0] pcie_rq_seq_num1;
wire                        pcie_rq_seq_num_vld1;
wire [RQ_SEQ_NUM_WIDTH-1:0] pcie_rq_seq_num2;
wire                        pcie_rq_seq_num_vld2;
wire [RQ_SEQ_NUM_WIDTH-1:0] pcie_rq_seq_num3;
wire                        pcie_rq_seq_num_vld3;

wire [251:0] cfg_interrupt_msix_vf_enable_tie = 252'd0;
wire [251:0] cfg_interrupt_msix_vf_mask_tie   = 252'd0;

wire [1:0]  cpm_cfg_max_payload;
wire [2:0]  cpm_cfg_max_read_req;
wire        cpm_cfg_rcb_status;
wire        cpm_cfg_msix_enable;
wire        cpm_cfg_msix_mask;

assign cfg_max_payload  = {1'b0, cpm_cfg_max_payload};
assign cfg_max_read_req = cpm_cfg_max_read_req;
assign cfg_rcb_status   = {3'b000, cpm_cfg_rcb_status};

assign cfg_interrupt_msix_enable = {3'b000, cpm_cfg_msix_enable};
assign cfg_interrupt_msix_mask   = {3'b000, cpm_cfg_msix_mask};

reg sticky_gearbox_err_reg = 1'b0;
reg sticky_poison_reg      = 1'b0;
reg sticky_uncor_reg       = 1'b0;

always @(posedge pcie_user_clk) begin
    if (pcie_user_reset) begin
        sticky_gearbox_err_reg <= 1'b0;
        sticky_poison_reg      <= 1'b0;
        sticky_uncor_reg       <= 1'b0;
    end else begin
        if (status_error_cq_slot_overflow || status_error_cq_leading_gap ||
                status_error_cc_sop_align) begin
            sticky_gearbox_err_reg <= 1'b1;
        end
        if (sts_cq_poisoned_seen || sts_cq_poisoned_tlp[0] || sts_cq_poisoned_tlp[1]) begin
            sticky_poison_reg <= 1'b1;
        end
        if (status_error_uncor) begin
            sticky_uncor_reg <= 1'b1;
        end
    end
end

assign gpio_lnk_up_o      = pcie_user_lnk_up;
assign gpio_gearbox_err_o = sticky_gearbox_err_reg;
assign gpio_poison_seen_o = sticky_poison_reg;
assign gpio_uncor_err_o   = sticky_uncor_reg;

cips_cpm5_pcie_g5x8_wrapper
cips_cpm5_pcie_g5x8_inst (
    .gt_refclk1_clk_p                   (gt_refclk1_clk_p),
    .gt_refclk1_clk_n                   (gt_refclk1_clk_n),
    .PCIE1_GT_grx_p                     (pcie_rx_p),
    .PCIE1_GT_grx_n                     (pcie_rx_n),
    .PCIE1_GT_gtx_p                     (pcie_tx_p),
    .PCIE1_GT_gtx_n                     (pcie_tx_n),

    .pcie1_user_clk                     (pcie_user_clk),
    .pcie1_user_reset                   (pcie_user_reset),
    .pcie1_user_lnk_up                  (pcie_user_lnk_up),

    .pcie1_s_axis_rq_tdata              (axis_rq_tdata),
    .pcie1_s_axis_rq_tkeep              (axis_rq_tkeep),
    .pcie1_s_axis_rq_tlast              (axis_rq_tlast),
    .pcie1_s_axis_rq_tready             (axis_rq_tready),
    .pcie1_s_axis_rq_tuser              (axis_rq_tuser),
    .pcie1_s_axis_rq_tvalid             (axis_rq_tvalid),

    .pcie1_m_axis_rc_tdata              (axis_rc_tdata),
    .pcie1_m_axis_rc_tkeep              (axis_rc_tkeep),
    .pcie1_m_axis_rc_tlast              (axis_rc_tlast),
    .pcie1_m_axis_rc_tready             (axis_rc_tready),
    .pcie1_m_axis_rc_tuser              (axis_rc_tuser),
    .pcie1_m_axis_rc_tvalid             (axis_rc_tvalid),

    .pcie1_m_axis_cq_tdata              (axis_cq_tdata),
    .pcie1_m_axis_cq_tkeep              (axis_cq_tkeep),
    .pcie1_m_axis_cq_tlast              (axis_cq_tlast),
    .pcie1_m_axis_cq_tready             (axis_cq_tready),
    .pcie1_m_axis_cq_tuser              (axis_cq_tuser),
    .pcie1_m_axis_cq_tvalid             (axis_cq_tvalid),

    .pcie1_s_axis_cc_tdata              (axis_cc_tdata),
    .pcie1_s_axis_cc_tkeep              (axis_cc_tkeep),
    .pcie1_s_axis_cc_tlast              (axis_cc_tlast),
    .pcie1_s_axis_cc_tready             (axis_cc_tready),
    .pcie1_s_axis_cc_tuser              (axis_cc_tuser),
    .pcie1_s_axis_cc_tvalid             (axis_cc_tvalid),

    .pcie1_cfg_mgmt_addr                (cfg_mgmt_addr),
    .pcie1_cfg_mgmt_byte_en             (cfg_mgmt_byte_enable),
    .pcie1_cfg_mgmt_function_number     ({8'd0, cfg_mgmt_function_number}),
    .pcie1_cfg_mgmt_read_data           (cfg_mgmt_read_data),
    .pcie1_cfg_mgmt_read_en             (cfg_mgmt_read),
    .pcie1_cfg_mgmt_read_write_done     (cfg_mgmt_read_write_done),
    .pcie1_cfg_mgmt_write_data          (cfg_mgmt_write_data),
    .pcie1_cfg_mgmt_write_en            (cfg_mgmt_write),
    .pcie1_cfg_mgmt_debug_access        (1'b0),

    .pcie1_cfg_control_err_cor_in       (status_error_cor),
    .pcie1_cfg_control_err_uncor_in     (status_error_uncor),
    .pcie1_cfg_control_flr_done         (1'b0),
    .pcie1_cfg_control_flr_done_function_number (16'd0),
    .pcie1_cfg_control_flr_in_process   (),
    .pcie1_cfg_control_hot_reset_in     (1'b0),
    .pcie1_cfg_control_hot_reset_out    (),
    .pcie1_cfg_control_per_function_number (16'd0),
    .pcie1_cfg_control_per_function_req (1'b0),
    .pcie1_cfg_control_power_state_change_ack (1'b1),
    .pcie1_cfg_control_power_state_change_interrupt (),

    .pcie1_cfg_fc_ph                    (cfg_fc_ph),
    .pcie1_cfg_fc_pd                    (cfg_fc_pd),
    .pcie1_cfg_fc_nph                   (cfg_fc_nph),
    .pcie1_cfg_fc_npd                   (cfg_fc_npd),
    .pcie1_cfg_fc_cplh                  (cfg_fc_cplh),
    .pcie1_cfg_fc_cpld                  (cfg_fc_cpld),
    .pcie1_cfg_fc_ph_scale              (),
    .pcie1_cfg_fc_pd_scale              (),
    .pcie1_cfg_fc_nph_scale             (),
    .pcie1_cfg_fc_npd_scale             (),
    .pcie1_cfg_fc_cplh_scale            (),
    .pcie1_cfg_fc_cpld_scale            (),
    .pcie1_cfg_fc_sel                   (cfg_fc_sel),
    .pcie1_cfg_fc_vc_sel                (1'b0),

    .pcie1_cfg_status_cq_np_req         (2'b11),
    .pcie1_cfg_status_cq_np_req_count   (),
    .pcie1_cfg_status_max_payload       (cpm_cfg_max_payload),
    .pcie1_cfg_status_max_read_req      (cpm_cfg_max_read_req),
    .pcie1_cfg_status_rcb_status        (cpm_cfg_rcb_status),

    .pcie1_cfg_status_rq_seq_num0       (pcie_rq_seq_num0),
    .pcie1_cfg_status_rq_seq_num1       (pcie_rq_seq_num1),
    .pcie1_cfg_status_rq_seq_num2       (pcie_rq_seq_num2),
    .pcie1_cfg_status_rq_seq_num3       (pcie_rq_seq_num3),
    .pcie1_cfg_status_rq_seq_num_vld0   (pcie_rq_seq_num_vld0),
    .pcie1_cfg_status_rq_seq_num_vld1   (pcie_rq_seq_num_vld1),
    .pcie1_cfg_status_rq_seq_num_vld2   (pcie_rq_seq_num_vld2),
    .pcie1_cfg_status_rq_seq_num_vld3   (pcie_rq_seq_num_vld3),

    .pcie1_cfg_status_rq_tag0           (),
    .pcie1_cfg_status_rq_tag1           (),
    .pcie1_cfg_status_rq_tag2           (),
    .pcie1_cfg_status_rq_tag3           (),
    .pcie1_cfg_status_rq_tag_av         (),
    .pcie1_cfg_status_rq_tag_vld0       (),
    .pcie1_cfg_status_rq_tag_vld1       (),
    .pcie1_cfg_status_rq_tag_vld2       (),
    .pcie1_cfg_status_rq_tag_vld3       (),
    .pcie1_cfg_status_10b_tag_requester_enable (),
    .pcie1_cfg_status_atomic_requester_enable  (),
    .pcie1_cfg_status_ext_tag_enable    (),
    .pcie1_cfg_status_bus_number        (),
    .pcie1_cfg_status_current_speed     (),
    .pcie1_cfg_status_negotiated_width  (),
    .pcie1_cfg_status_err_cor_out       (),
    .pcie1_cfg_status_err_fatal_out     (),
    .pcie1_cfg_status_err_nonfatal_out  (),
    .pcie1_cfg_status_function_power_state (),
    .pcie1_cfg_status_function_status   (),
    .pcie1_cfg_status_link_power_state  (),
    .pcie1_cfg_status_local_error_out   (),
    .pcie1_cfg_status_local_error_valid (),
    .pcie1_cfg_status_ltssm_state       (),
    .pcie1_cfg_status_per_function_out  (),
    .pcie1_cfg_status_per_function_vld  (),
    .pcie1_cfg_status_phy_link_down     (),
    .pcie1_cfg_status_phy_link_status   (),
    .pcie1_cfg_status_pl_status_change  (),
    .pcie1_cfg_status_rx_pm_state       (),
    .pcie1_cfg_status_tx_pm_state       (),
    .pcie1_cfg_status_tph_requester_enable (),
    .pcie1_cfg_status_tph_st_mode       (),
    .pcie1_cfg_status_wrreq_bme_vld     (),
    .pcie1_cfg_status_wrreq_flr_vld     (),
    .pcie1_cfg_status_wrreq_function_number (),
    .pcie1_cfg_status_wrreq_msi_vld     (),
    .pcie1_cfg_status_wrreq_msix_vld    (),
    .pcie1_cfg_status_wrreq_out_value   (),
    .pcie1_cfg_status_wrreq_vfe_vld     (),

    .pcie1_transmit_fc_nph_av           (),
    .pcie1_transmit_fc_npd_av           (),

    .pcie1_cfg_ext_function_number      (),
    .pcie1_cfg_ext_read_data            (32'd0),
    .pcie1_cfg_ext_read_data_valid      (1'b0),
    .pcie1_cfg_ext_read_received        (),
    .pcie1_cfg_ext_register_number      (),
    .pcie1_cfg_ext_write_byte_enable    (),
    .pcie1_cfg_ext_write_data           (),
    .pcie1_cfg_ext_write_received       (),

    .pcie1_cfg_interrupt_intx_vector    (4'd0),
    .pcie1_cfg_interrupt_pending        (16'd0),
    .pcie1_cfg_interrupt_sent           (),

    .pcie1_cfg_msix_int_vector          (cfg_interrupt_msix_int),
    .pcie1_cfg_msix_mint_vector         (32'd0),
    .pcie1_cfg_msix_function_number     ({8'd0, cfg_interrupt_msi_function_number}),
    .pcie1_cfg_msix_enable              (cpm_cfg_msix_enable),
    .pcie1_cfg_msix_mask                (cpm_cfg_msix_mask),
    .pcie1_cfg_msix_sent                (cfg_interrupt_msix_sent),
    .pcie1_cfg_msix_fail                (cfg_interrupt_msix_fail),
    .pcie1_cfg_msix_vec_pending         (cfg_interrupt_msix_vec_pending),
    .pcie1_cfg_msix_vec_pending_status  (cfg_interrupt_msix_vec_pending_status),
    .pcie1_cfg_msix_attr                (3'd0),
    .pcie1_cfg_msix_tph_present         (1'b0),
    .pcie1_cfg_msix_tph_st_tag          (8'd0),
    .pcie1_cfg_msix_tph_type            (2'd0)
);

fpga_core #(
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
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),
    .RQ_SEQ_NUM_ENABLE(RQ_SEQ_NUM_ENABLE),
    .RQ_STRADDLE_ENC(RQ_STRADDLE_ENC),
    .RC_SOP_COMPACT(RC_SOP_COMPACT),
    .RC_FIFO_SEG_COUNT(RC_FIFO_SEG_COUNT),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),
    .BAR0_APERTURE(BAR0_APERTURE),
    .BAR2_APERTURE(BAR2_APERTURE),
    .BAR4_APERTURE(BAR4_APERTURE)
)
core_inst (
    .clk(pcie_user_clk),
    .rst(pcie_user_reset),

    .m_axis_rq_tdata(axis_rq_tdata),
    .m_axis_rq_tkeep(axis_rq_tkeep),
    .m_axis_rq_tlast(axis_rq_tlast),
    .m_axis_rq_tready(axis_rq_tready),
    .m_axis_rq_tuser(axis_rq_tuser),
    .m_axis_rq_tvalid(axis_rq_tvalid),

    .s_axis_rc_tdata(axis_rc_tdata),
    .s_axis_rc_tkeep(axis_rc_tkeep),
    .s_axis_rc_tlast(axis_rc_tlast),
    .s_axis_rc_tready(axis_rc_tready),
    .s_axis_rc_tuser(axis_rc_tuser),
    .s_axis_rc_tvalid(axis_rc_tvalid),

    .s_axis_cq_tdata(axis_cq_tdata),
    .s_axis_cq_tkeep(axis_cq_tkeep),
    .s_axis_cq_tlast(axis_cq_tlast),
    .s_axis_cq_tready(axis_cq_tready),
    .s_axis_cq_tuser(axis_cq_tuser),
    .s_axis_cq_tvalid(axis_cq_tvalid),

    .m_axis_cc_tdata(axis_cc_tdata),
    .m_axis_cc_tkeep(axis_cc_tkeep),
    .m_axis_cc_tlast(axis_cc_tlast),
    .m_axis_cc_tready(axis_cc_tready),
    .m_axis_cc_tuser(axis_cc_tuser),
    .m_axis_cc_tvalid(axis_cc_tvalid),

    .s_axis_rq_seq_num_0(pcie_rq_seq_num0),
    .s_axis_rq_seq_num_valid_0(pcie_rq_seq_num_vld0),
    .s_axis_rq_seq_num_1(pcie_rq_seq_num1),
    .s_axis_rq_seq_num_valid_1(pcie_rq_seq_num_vld1),
    .s_axis_rq_seq_num_2(pcie_rq_seq_num2),
    .s_axis_rq_seq_num_valid_2(pcie_rq_seq_num_vld2),
    .s_axis_rq_seq_num_3(pcie_rq_seq_num3),
    .s_axis_rq_seq_num_valid_3(pcie_rq_seq_num_vld3),

    .cfg_max_payload(cfg_max_payload),
    .cfg_max_read_req(cfg_max_read_req),
    .cfg_rcb_status(cfg_rcb_status),

    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_function_number(cfg_mgmt_function_number),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),

    .cfg_fc_ph(cfg_fc_ph),
    .cfg_fc_pd(cfg_fc_pd),
    .cfg_fc_nph(cfg_fc_nph),
    .cfg_fc_npd(cfg_fc_npd),
    .cfg_fc_cplh(cfg_fc_cplh),
    .cfg_fc_cpld(cfg_fc_cpld),
    .cfg_fc_sel(cfg_fc_sel),

    .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
    .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
    .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable_tie),
    .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask_tie),
    .cfg_interrupt_msix_address(cfg_interrupt_msix_address),
    .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
    .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
    .cfg_interrupt_msix_vec_pending(cfg_interrupt_msix_vec_pending),
    .cfg_interrupt_msix_vec_pending_status(cfg_interrupt_msix_vec_pending_status),
    .cfg_interrupt_msix_sent(cfg_interrupt_msix_sent),
    .cfg_interrupt_msix_fail(cfg_interrupt_msix_fail),
    .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),

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
