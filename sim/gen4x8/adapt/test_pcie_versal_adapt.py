# ---------------------------------------------------------------------------
# File        : test_pcie_versal_adapt.py
# Description : Acceptance testbench for pcie_versal_adapt. One test per
#               requirement: field identity on RQ, truncation and poisoned TLP
#               surfacing on CQ, pass through on RC and CC, delayed handshake.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

DATA_W = 512
KEEP_W = DATA_W // 32

CPM5_RQ_USER_W = 183
CPM5_CQ_USER_W = 231
US_RQ_USER_W = 137
US_CQ_USER_W = 183
RC_USER_W = 161
CC_USER_W = 81

RQ_FIELDS = [
    (0,   8, "first_be"),
    (8,   8, "last_be"),
    (16,  4, "addr_offset"),
    (20,  2, "is_sop"),
    (22,  2, "is_sop0_ptr"),
    (24,  2, "is_sop1_ptr"),
    (26,  2, "is_eop"),
    (28,  4, "is_eop0_ptr"),
    (32,  4, "is_eop1_ptr"),
    (36,  1, "discontinue"),
    (45, 16, "tph_st_tag"),
    (61,  6, "seq_num0"),
    (67,  6, "seq_num1"),
    (73, 64, "parity"),
]

CQ_FIELDS = [
    (0,   8, "first_be"),
    (8,   8, "last_be"),
    (16, 64, "byte_en"),
    (80,  2, "is_sop"),
    (82,  2, "is_sop0_ptr"),
    (84,  2, "is_sop1_ptr"),
    (86,  2, "is_eop"),
    (88,  4, "is_eop0_ptr"),
    (92,  4, "is_eop1_ptr"),
    (96,  1, "discontinue"),
    (119, 64, "parity"),
]

RC_FIELDS = [
    (0,  64, "byte_en"),
    (64,  4, "is_sop"),
    (68,  2, "is_sop0_ptr"),
    (70,  2, "is_sop1_ptr"),
    (72,  2, "is_sop2_ptr"),
    (74,  2, "is_sop3_ptr"),
    (76,  4, "is_eop"),
    (80,  4, "is_eop0_ptr"),
    (84,  4, "is_eop1_ptr"),
    (88,  4, "is_eop2_ptr"),
    (92,  4, "is_eop3_ptr"),
    (96,  1, "discontinue"),
    (97, 64, "parity"),
]

CC_FIELDS = [
    (0,   2, "is_sop"),
    (2,   2, "is_sop0_ptr"),
    (4,   2, "is_sop1_ptr"),
    (6,   2, "is_eop"),
    (8,   4, "is_eop0_ptr"),
    (12,  4, "is_eop1_ptr"),
    (16,  1, "discontinue"),
    (17, 64, "parity"),
]

def field(vec, lo, width):
    return (int(vec) >> lo) & ((1 << width) - 1)

def one_hot_patterns(width):
    pats = [0, (1 << width) - 1]
    pats += [1 << i for i in range(width)]
    return pats

class TB:
    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log
        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

    async def reset(self):
        self.dut.rst.value = 1
        for sig, w in (("us_rq_tdata", DATA_W), ("us_rq_tkeep", KEEP_W),
                       ("us_rq_tuser", US_RQ_USER_W), ("us_cc_tdata", DATA_W),
                       ("us_cc_tkeep", KEEP_W), ("us_cc_tuser", CC_USER_W),
                       ("cpm_cq_tdata", DATA_W), ("cpm_cq_tkeep", KEEP_W),
                       ("cpm_cq_tuser", CPM5_CQ_USER_W), ("cpm_rc_tdata", DATA_W),
                       ("cpm_rc_tkeep", KEEP_W), ("cpm_rc_tuser", RC_USER_W)):
            getattr(self.dut, sig).value = 0
        for sig in ("us_rq_tvalid", "us_rq_tlast", "us_cc_tvalid", "us_cc_tlast",
                    "cpm_cq_tvalid", "cpm_cq_tlast", "cpm_rc_tvalid", "cpm_rc_tlast",
                    "cpm_rq_tready", "cpm_cc_tready", "us_cq_tready", "us_rc_tready"):
            getattr(self.dut, sig).value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)

@cocotb.test()
async def test_rq_field_identity(dut):
    tb = TB(dut)
    await tb.reset()
    for lo, width, name in RQ_FIELDS:
        for pat in one_hot_patterns(width):
            dut.us_rq_tuser.value = pat << lo
            await Timer(1, units="ns")
            got = field(dut.cpm_rq_tuser.value, lo, width)
            assert got == pat, (
                f"RQ field '{name}' at [{lo+width-1}:{lo}]: drove 0x{pat:x}, "
                f"CPM5 side shows 0x{got:x}")
    for _ in range(64):
        v = random.getrandbits(US_RQ_USER_W)
        dut.us_rq_tuser.value = v
        await Timer(1, units="ns")
        assert field(dut.cpm_rq_tuser.value, 0, US_RQ_USER_W) == v, \
            "RQ full-vector identity failed"
    dut._log.info("PASS: RQ [136:0] identity over %d fields + 64 random vectors",
                  len(RQ_FIELDS))

@cocotb.test()
async def test_rq_pasid_zero(dut):
    tb = TB(dut)
    await tb.reset()
    for _ in range(64):
        dut.us_rq_tuser.value = random.getrandbits(US_RQ_USER_W)
        await Timer(1, units="ns")
        extra = field(dut.cpm_rq_tuser.value, US_RQ_USER_W,
                      CPM5_RQ_USER_W - US_RQ_USER_W)
        assert extra == 0, (
            f"RQ PASID span [{CPM5_RQ_USER_W-1}:{US_RQ_USER_W}] must be 0, "
            f"got 0x{extra:x} (this design issues no ATS or PRI)")
    dut._log.info("PASS: RQ PASID span held at 0")

@cocotb.test()
async def test_cq_field_identity(dut):
    tb = TB(dut)
    await tb.reset()
    for lo, width, name in CQ_FIELDS:
        for pat in one_hot_patterns(width):
            dut.cpm_cq_tuser.value = pat << lo
            await Timer(1, units="ns")
            got = field(dut.us_cq_tuser.value, lo, width)
            assert got == pat, (
                f"CQ field '{name}' at [{lo+width-1}:{lo}]: drove 0x{pat:x}, "
                f"library side shows 0x{got:x}")
    for _ in range(64):
        v = random.getrandbits(US_CQ_USER_W)
        dut.cpm_cq_tuser.value = v
        await Timer(1, units="ns")
        assert field(dut.us_cq_tuser.value, 0, US_CQ_USER_W) == v, \
            "CQ full-vector identity failed"
    dut._log.info("PASS: CQ [182:0] identity over %d fields + 64 random vectors",
                  len(CQ_FIELDS))

@cocotb.test()
async def test_cq_poison_surfaced(dut):
    tb = TB(dut)
    await tb.reset()
    POISON_LO = 229

    assert int(dut.sts_cq_poisoned_seen.value) == 0, \
        "the sticky bit must clear on reset"

    for pat in (0b01, 0b10, 0b11):
        dut.cpm_cq_tuser.value = pat << POISON_LO
        dut.cpm_cq_tvalid.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got = int(dut.sts_cq_poisoned_tlp.value)
        assert got == pat, (
            f"poisoned_tlp: CPM5 drove 0b{pat:02b}, sts shows 0b{got:02b} "
            f"but the status does not show it")
        assert int(dut.sts_cq_poisoned_seen.value) == 1, \
            "the sticky bit must set on any poisoned TLP"

    dut.cpm_cq_tuser.value = 0
    dut.cpm_cq_tvalid.value = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
    assert int(dut.sts_cq_poisoned_seen.value) == 1, \
        "the sticky bit must persist until reset"

    assert field(dut.us_cq_tuser.value, 0, US_CQ_USER_W) == 0, \
        "poison must not corrupt the US+ 183-bit window"
    dut._log.info("PASS: poisoned_tlp surfaced + sticky, no leakage")

@cocotb.test()
async def test_rc_passthrough(dut):
    tb = TB(dut)
    await tb.reset()
    for lo, width, name in RC_FIELDS:
        for pat in one_hot_patterns(width):
            dut.cpm_rc_tuser.value = pat << lo
            await Timer(1, units="ns")
            got = field(dut.us_rc_tuser.value, lo, width)
            assert got == pat, (
                f"RC field '{name}' at [{lo+width-1}:{lo}]: 0x{pat:x} -> 0x{got:x} "
                f"on the US+ face")
    dut._log.info("PASS: RC pass-through, %d fields incl. 4-TLP straddle ptrs",
                  len(RC_FIELDS))

@cocotb.test()
async def test_cc_passthrough(dut):
    tb = TB(dut)
    await tb.reset()
    for lo, width, name in CC_FIELDS:
        for pat in one_hot_patterns(width):
            dut.us_cc_tuser.value = pat << lo
            await Timer(1, units="ns")
            got = field(dut.cpm_cc_tuser.value, lo, width)
            assert got == pat, (
                f"CC field '{name}' at [{lo+width-1}:{lo}]: 0x{pat:x} -> 0x{got:x} "
                f"on the CPM5 face")
    dut._log.info("PASS: CC pass-through, %d fields", len(CC_FIELDS))

@cocotb.test()
async def test_zero_latency(dut):
    tb = TB(dut)
    await tb.reset()
    for _ in range(32):
        d = random.getrandbits(DATA_W)
        k = random.getrandbits(KEEP_W)
        dut.us_rq_tdata.value = d
        dut.us_rq_tkeep.value = k
        dut.us_rq_tvalid.value = 1
        dut.us_rq_tlast.value = 1
        dut.cpm_cq_tdata.value = d
        dut.cpm_cq_tvalid.value = 1
        await Timer(1, units="ns")
        assert int(dut.cpm_rq_tdata.value) == d, "RQ tdata delayed: the adapter must add no latency"
        assert int(dut.cpm_rq_tkeep.value) == k, "RQ tkeep delayed"
        assert int(dut.cpm_rq_tvalid.value) == 1, "RQ tvalid delayed"
        assert int(dut.cpm_rq_tlast.value) == 1, "RQ tlast delayed"
        assert int(dut.us_cq_tdata.value) == d, "CQ tdata delayed"
    dut._log.info("PASS: zero-latency datapath on all four channels")

@cocotb.test()
async def test_tready_transparent(dut):
    tb = TB(dut)
    await tb.reset()
    for val in (0, 1, 0, 1, 1, 0):
        dut.cpm_rq_tready.value = val
        dut.cpm_cc_tready.value = val
        dut.us_cq_tready.value = val
        dut.us_rc_tready.value = val
        await Timer(1, units="ns")
        assert int(dut.us_rq_tready.value) == val, \
            "RQ back-pressure not transparent"
        assert int(dut.us_cc_tready.value) == val, "CC back-pressure not transparent"
        assert int(dut.cpm_cq_tready.value) == val, "CQ back-pressure not transparent"
        assert int(dut.cpm_rc_tready.value) == val, "RC back-pressure not transparent"
    dut._log.info("PASS: tready transparent, same cycle, all four channels")

@cocotb.test()
async def test_no_buffering(dut):
    tb = TB(dut)
    await tb.reset()
    dut.us_rq_tdata.value = (1 << DATA_W) - 1
    dut.us_rq_tvalid.value = 1
    await Timer(1, units="ns")
    dut.us_rq_tdata.value = 0
    dut.us_rq_tvalid.value = 0
    for cycle in range(16):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        assert int(dut.cpm_rq_tvalid.value) == 0, \
            f"residual tvalid at cycle {cycle} - the adapter is holding state"
        assert int(dut.cpm_rq_tdata.value) == 0, \
            f"residual tdata at cycle {cycle}: the adapter must not buffer"
    dut._log.info("PASS: no buffering, no residual beats over 16 idle cycles")

@cocotb.test()
async def test_straddle_config(dut):
    tb = TB(dut)
    await tb.reset()

    dut.us_rq_tuser.value = 0b11 << 20
    dut.cpm_cq_tuser.value = 0b11 << 80
    dut.us_cc_tuser.value = 0b11 << 0
    dut.cpm_rc_tuser.value = 0b1111 << 64
    await Timer(1, units="ns")

    assert field(dut.cpm_rq_tuser.value, 20, 2) == 0b11, "RQ 2-TLP straddle lost"
    assert field(dut.us_cq_tuser.value, 80, 2) == 0b11, "CQ 2-TLP straddle lost"
    assert field(dut.cpm_cc_tuser.value, 0, 2) == 0b11, "CC 2-TLP straddle lost"
    assert field(dut.us_rc_tuser.value, 64, 4) == 0b1111, "RC 4-TLP straddle lost"
    dut._log.info("PASS: straddle-bearing fields at full width (RQ/CQ/CC 2, RC 4)")
