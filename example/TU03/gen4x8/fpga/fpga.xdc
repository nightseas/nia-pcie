# ---------------------------------------------------------------------------
# File        : fpga.xdc
# Description : Pin constraints for the TU03 endpoint example. It constrains the
#               status outputs only: the PCIe lanes and the reference clock
#               belong to the CPM5 block and are placed by it.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN N34 [get_ports {pcie_user_lnk_up_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {pcie_user_lnk_up_o}]

set_property PACKAGE_PIN P34 [get_ports {sts_cq_poisoned_seen_o}]
set_property IOSTANDARD LVCMOS15 [get_ports {sts_cq_poisoned_seen_o}]

set_property PACKAGE_PIN P32 [get_ports {sts_cq_poisoned_tlp_o[0]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sts_cq_poisoned_tlp_o[0]}]

set_property PACKAGE_PIN R32 [get_ports {sts_cq_poisoned_tlp_o[1]}]
set_property IOSTANDARD LVCMOS15 [get_ports {sts_cq_poisoned_tlp_o[1]}]
