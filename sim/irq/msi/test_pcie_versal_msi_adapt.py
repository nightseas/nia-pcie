# ---------------------------------------------------------------------------
# File        : test_pcie_versal_msi_adapt.py
# Description : Acceptance testbench for pcie_versal_msi_adapt. One test per
#               requirement: the bench drives every source field, a widened field
#               preserves its value and pads with zero, a pass through field is an
#               identity, no field couples to another, a random soak holds every
#               field independent, and the module is combinational.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import os
import random

import cocotb
from cocotb.triggers import Timer

US_ENABLE_W = int(os.environ.get("PARAM_US_ENABLE_W", "4"))
US_MMENABLE_W = int(os.environ.get("PARAM_US_MMENABLE_W", "12"))
US_SELECT_W = int(os.environ.get("PARAM_US_SELECT_W", "2"))
US_PSFN_W = int(os.environ.get("PARAM_US_PSFN_W", "2"))
US_FUNC_NUM_W = int(os.environ.get("PARAM_US_FUNC_NUM_W", "8"))

CPM5_ENABLE_W = int(os.environ.get("PARAM_CPM5_ENABLE_W", "1"))
CPM5_MMENABLE_W = int(os.environ.get("PARAM_CPM5_MMENABLE_W", "3"))
CPM5_SELECT_W = int(os.environ.get("PARAM_CPM5_SELECT_W", "4"))
CPM5_PSFN_W = int(os.environ.get("PARAM_CPM5_PSFN_W", "4"))
CPM5_FUNC_NUM_W = int(os.environ.get("PARAM_CPM5_FUNC_NUM_W", "16"))

VECTOR_W = int(os.environ.get("PARAM_VECTOR_W", "32"))
ATTR_W = int(os.environ.get("PARAM_ATTR_W", "3"))
TPH_TYPE_W = int(os.environ.get("PARAM_TPH_TYPE_W", "2"))
TPH_ST_TAG_W = int(os.environ.get("PARAM_TPH_ST_TAG_W", "8"))

SEED = int(os.environ.get("NIA_SEED", "1"))

SETTLE_NS = 2

WIDEN_UP = [
    ("msi_enable", "cpm_cfg_msi_enable", "us_cfg_interrupt_msi_enable",
     CPM5_ENABLE_W, US_ENABLE_W),
    ("msi_mmenable", "cpm_cfg_msi_mmenable", "us_cfg_interrupt_msi_mmenable",
     CPM5_MMENABLE_W, US_MMENABLE_W),
]

WIDEN_DOWN = [
    ("msi_select", "us_cfg_interrupt_msi_select", "cpm_cfg_msi_select",
     US_SELECT_W, CPM5_SELECT_W),
    ("msi_pending_status_function_num", "us_cfg_interrupt_msi_pending_status_function_num",
     "cpm_cfg_msi_pending_status_function_num", US_PSFN_W, CPM5_PSFN_W),
    ("msi_function_number", "us_cfg_interrupt_msi_function_number",
     "cpm_cfg_msi_function_number", US_FUNC_NUM_W, CPM5_FUNC_NUM_W),
]

PASS_UP = [
    ("msi_mask_update", "cpm_cfg_msi_mask_update", "us_cfg_interrupt_msi_mask_update", 1),
    ("msi_data", "cpm_cfg_msi_data", "us_cfg_interrupt_msi_data", VECTOR_W),
    ("msi_sent", "cpm_cfg_msi_sent", "us_cfg_interrupt_msi_sent", 1),
    ("msi_fail", "cpm_cfg_msi_fail", "us_cfg_interrupt_msi_fail", 1),
]

PASS_DOWN = [
    ("msi_int_vector", "us_cfg_interrupt_msi_int", "cpm_cfg_msi_int_vector", VECTOR_W),
    ("msi_pending_status", "us_cfg_interrupt_msi_pending_status",
     "cpm_cfg_msi_pending_status", VECTOR_W),
    ("msi_pending_status_data_enable", "us_cfg_interrupt_msi_pending_status_data_enable",
     "cpm_cfg_msi_pending_status_data_enable", 1),
    ("msi_attr", "us_cfg_interrupt_msi_attr", "cpm_cfg_msi_attr", ATTR_W),
    ("msi_tph_present", "us_cfg_interrupt_msi_tph_present", "cpm_cfg_msi_tph_present", 1),
    ("msi_tph_type", "us_cfg_interrupt_msi_tph_type", "cpm_cfg_msi_tph_type", TPH_TYPE_W),
    ("msi_tph_st_tag", "us_cfg_interrupt_msi_tph_st_tag", "cpm_cfg_msi_tph_st_tag", TPH_ST_TAG_W),
]

ALL_INPUTS = [
    ("cpm_cfg_msi_enable", CPM5_ENABLE_W),
    ("cpm_cfg_msi_mmenable", CPM5_MMENABLE_W),
    ("cpm_cfg_msi_mask_update", 1),
    ("cpm_cfg_msi_data", VECTOR_W),
    ("cpm_cfg_msi_sent", 1),
    ("cpm_cfg_msi_fail", 1),
    ("us_cfg_interrupt_msi_int", VECTOR_W),
    ("us_cfg_interrupt_msi_select", US_SELECT_W),
    ("us_cfg_interrupt_msi_pending_status", VECTOR_W),
    ("us_cfg_interrupt_msi_pending_status_data_enable", 1),
    ("us_cfg_interrupt_msi_pending_status_function_num", US_PSFN_W),
    ("us_cfg_interrupt_msi_attr", ATTR_W),
    ("us_cfg_interrupt_msi_tph_present", 1),
    ("us_cfg_interrupt_msi_tph_type", TPH_TYPE_W),
    ("us_cfg_interrupt_msi_tph_st_tag", TPH_ST_TAG_W),
    ("us_cfg_interrupt_msi_function_number", US_FUNC_NUM_W),
]


def patterns(width):
    out = [0, (1 << width) - 1]
    for bit in range(width):
        out.append(1 << bit)
    if width > 2:
        out.append(int("01" * ((width + 1) // 2), 2) & ((1 << width) - 1))
        out.append(int("10" * ((width + 1) // 2), 2) & ((1 << width) - 1))
    return sorted(set(out))


async def quiesce(dut):
    for name, width in ALL_INPUTS:
        getattr(dut, name).value = 0
    await Timer(SETTLE_NS, units="ns")


async def drive(dut, name, value):
    getattr(dut, name).value = value
    await Timer(SETTLE_NS, units="ns")


def read(dut, name):
    return int(getattr(dut, name).value)


@cocotb.test()
async def test_bench_drives_every_source_field(dut):
    named = {s for _, s, _, _, _ in WIDEN_UP + WIDEN_DOWN}
    named |= {s for _, s, _, _ in PASS_UP + PASS_DOWN}
    listed = {n for n, _ in ALL_INPUTS}
    assert named == listed, \
        "the bench input table is incomplete: not driven %r, driven but unchecked %r" % \
        (sorted(named - listed), sorted(listed - named))
    for name, _ in ALL_INPUTS:
        assert hasattr(dut, name), "%s is not a port of the module" % name
    dut._log.info("bench drives and checks all %d input fields", len(ALL_INPUTS))


@cocotb.test()
async def test_widened_fields_preserve_value(dut):
    await quiesce(dut)
    for label, src, dst, src_w, dst_w in WIDEN_UP + WIDEN_DOWN:
        for value in patterns(src_w):
            await drive(dut, src, value)
            got = read(dut, dst)
            assert got == value, \
                "%s: drove %s = 0x%x at %d bits, read %s = 0x%x at %d bits" % \
                (label, src, value, src_w, dst, got, dst_w)
        await drive(dut, src, 0)
    dut._log.info("value preserved across %d widened fields", len(WIDEN_UP + WIDEN_DOWN))


@cocotb.test()
async def test_widened_fields_pad_is_zero(dut):
    await quiesce(dut)
    bad = []
    for label, src, dst, src_w, dst_w in WIDEN_UP + WIDEN_DOWN:
        if dst_w <= src_w:
            continue
        for value in patterns(src_w):
            await drive(dut, src, value)
            pad = read(dut, dst) >> src_w
            if pad != 0:
                bad.append("%s: %s[%d:%d] = 0x%x with %s = 0x%x" %
                           (label, dst, dst_w - 1, src_w, pad, src, value))
        await drive(dut, src, 0)
    assert not bad, "pad bits above the source width must be zero: %s" % bad[:6]
    dut._log.info("pad above the source width stayed zero on every pattern")


@cocotb.test()
async def test_passthrough_fields_are_identity(dut):
    await quiesce(dut)
    for label, src, dst, width in PASS_UP + PASS_DOWN:
        for value in patterns(width):
            await drive(dut, src, value)
            got = read(dut, dst)
            assert got == value, \
                "%s: drove %s = 0x%x, read %s = 0x%x" % (label, src, value, dst, got)
        await drive(dut, src, 0)
    dut._log.info("identity held across %d pass through fields", len(PASS_UP + PASS_DOWN))


@cocotb.test()
async def test_no_cross_field_coupling(dut):
    random.seed(SEED)
    await quiesce(dut)
    watched = [(d, w) for _, _, d, _, w in WIDEN_UP + WIDEN_DOWN] + \
              [(d, w) for _, _, d, w in PASS_UP + PASS_DOWN]
    for name, width in ALL_INPUTS:
        await quiesce(dut)
        baseline = {d: read(dut, d) for d, _ in watched}
        await drive(dut, name, (1 << width) - 1)
        moved = [d for d, _ in watched if read(dut, d) != baseline[d]]
        assert len(moved) == 1, \
            "%s should drive exactly one output, moved %r" % (name, moved)
    dut._log.info("each of %d inputs drives exactly one output", len(ALL_INPUTS))


@cocotb.test()
async def test_random_soak_every_field_independent(dut):
    random.seed(SEED + 1)
    await quiesce(dut)
    for _ in range(200):
        sent = {}
        for name, width in ALL_INPUTS:
            value = random.getrandbits(width)
            sent[name] = value
            getattr(dut, name).value = value
        await Timer(SETTLE_NS, units="ns")
        for label, src, dst, src_w, dst_w in WIDEN_UP + WIDEN_DOWN:
            assert read(dut, dst) == sent[src], \
                "%s widened mismatch: %s = 0x%x, %s = 0x%x" % \
                (label, src, sent[src], dst, read(dut, dst))
        for label, src, dst, width in PASS_UP + PASS_DOWN:
            assert read(dut, dst) == sent[src], \
                "%s identity mismatch: %s = 0x%x, %s = 0x%x" % \
                (label, src, sent[src], dst, read(dut, dst))
    dut._log.info("soak: 200 random vectors, seed %d, every field independent", SEED + 1)


@cocotb.test()
async def test_module_is_combinational(dut):
    await quiesce(dut)
    before = read(dut, "us_cfg_interrupt_msi_data")
    dut.cpm_cfg_msi_data.value = 0xA5A5A5A5
    await Timer(SETTLE_NS, units="ns")
    after = read(dut, "us_cfg_interrupt_msi_data")
    assert before == 0 and after == 0xA5A5A5A5, \
        "data did not follow within one settle: before 0x%x after 0x%x" % (before, after)
    dut.cpm_cfg_msi_data.value = 0
    await Timer(SETTLE_NS, units="ns")
    assert read(dut, "us_cfg_interrupt_msi_data") == 0, \
        "output held a stale value, so the path is not combinational"
    dut._log.info("output follows input with no clock, both directions")
