# ---------------------------------------------------------------------------
# File        : fpga.xdc
# Description : Pin constraints of the Gen5 x8, 1024-bit AXIS, example: the link up, the
#               poisoned TLP seen and the gearbox error status outputs, with their
#               package pins and IO standard.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Xilinx design constraints
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set_property PACKAGE_PIN N34 [get_ports {gpio_lnk_up_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_lnk_up_o}]

set_property PACKAGE_PIN P34 [get_ports {gpio_poison_seen_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_poison_seen_o}]

set_property PACKAGE_PIN P32 [get_ports {gpio_gearbox_err_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_gearbox_err_o}]

set_property PACKAGE_PIN R32 [get_ports {gpio_uncor_err_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {gpio_uncor_err_o}]

set_false_path -to [get_ports {gpio_lnk_up_o gpio_poison_seen_o gpio_gearbox_err_o gpio_uncor_err_o}]
set_output_delay 0 [get_ports {gpio_lnk_up_o gpio_poison_seen_o gpio_gearbox_err_o gpio_uncor_err_o}]
