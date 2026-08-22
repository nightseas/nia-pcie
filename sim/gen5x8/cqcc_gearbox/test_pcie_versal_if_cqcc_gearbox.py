#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# File        : test_pcie_versal_if_cqcc_gearbox.py
# Description : The tests of the completer gearbox: completer request bytes survive
#               the split and survive back pressure, ready is a register output and
#               the interface accepts at full rate, completion bytes survive the
#               merge and back pressure, and a start alignment that cannot be
#               carried is reported.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
# Language    : Python 3
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import logging
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, Timer

CQ_BEAT_DWORDS = 32
CQ_HALF_DWORDS = 16
CQ_SOP_PTR_DW = 8

CQ_BYTE_EN_LO = 0
CQ_FIRST_BE_LO = 128
CQ_LAST_BE_LO = 144
CQ_IS_SOP_LO = 160
CQ_SOP_PTR_LO = 164
CQ_IS_EOP_LO = 172
CQ_EOP_PTR_LO = 176
CQ_DISCONTINUE_LO = 196

CLK_PERIOD_NS = 4


def thermometer(count):
    return (1 << count) - 1


class CqBeat:

    def __init__(self, tlps):
        self.tlps = list(tlps)
        self.dwords = [0] * CQ_BEAT_DWORDS
        self.strb = [0] * CQ_BEAT_DWORDS

        for index, (first_dw, last_dw) in enumerate(self.tlps):
            assert first_dw % CQ_SOP_PTR_DW == 0, (
                "a CQ start at dword %d is not on the %d dword pointer granularity"
                % (first_dw, CQ_SOP_PTR_DW))
            for dw in range(first_dw, last_dw + 1):
                self.dwords[dw] = random.getrandbits(32)
                self.strb[dw] = 1

    @property
    def tdata(self):
        value = 0
        for dw in range(CQ_BEAT_DWORDS):
            value |= self.dwords[dw] << (32 * dw)
        return value

    @property
    def tuser(self):
        value = 0
        for dw in range(CQ_BEAT_DWORDS):
            if self.strb[dw]:
                value |= 0xf << (CQ_BYTE_EN_LO + 4 * dw)

        value |= thermometer(len(self.tlps)) << CQ_IS_SOP_LO
        value |= thermometer(len(self.tlps)) << CQ_IS_EOP_LO

        for index, (first_dw, last_dw) in enumerate(self.tlps):
            value |= (first_dw // CQ_SOP_PTR_DW) << (CQ_SOP_PTR_LO + 2 * index)
            value |= last_dw << (CQ_EOP_PTR_LO + 5 * index)
            value |= 0xf << (CQ_FIRST_BE_LO + 4 * index)
            value |= 0xf << (CQ_LAST_BE_LO + 4 * index)

        return value

    def expected_halves(self):
        halves = []
        for half in (0, 1):
            base = half * CQ_HALF_DWORDS
            keep = 0
            dwords = []
            for offset in range(CQ_HALF_DWORDS):
                if self.strb[base + offset]:
                    keep |= 1 << offset
                    dwords.append(self.dwords[base + offset])
            if keep:
                halves.append((keep, dwords))
        return halves


def beat_set():
    return [
        CqBeat([(0, 3)]),
        CqBeat([(0, 31)]),
        CqBeat([(0, 3), (8, 11)]),
        CqBeat([(0, 3), (16, 19)]),
        CqBeat([(0, 19)]),
        CqBeat([(0, 7), (8, 31)]),
        CqBeat([(0, 15), (16, 23)]),
        CqBeat([(0, 0)]),
    ]


class TB:

    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.received = []

        cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

        dut.s_axis_cq_tdata.value = 0
        dut.s_axis_cq_tkeep.value = 0
        dut.s_axis_cq_tvalid.value = 0
        dut.s_axis_cq_tlast.value = 0
        dut.s_axis_cq_tuser.value = 0
        dut.m_axis_cq_tready.value = 0

        dut.s_axis_cc_tdata.value = 0
        dut.s_axis_cc_tkeep.value = 0
        dut.s_axis_cc_tvalid.value = 0
        dut.s_axis_cc_tlast.value = 0
        dut.s_axis_cc_tuser.value = 0
        dut.m_axis_cc_tready.value = 1

    async def reset(self):
        self.dut.rst.value = 1
        for _ in range(8):
            await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        for _ in range(4):
            await RisingEdge(self.dut.clk)

    async def send(self, beat):
        self.dut.s_axis_cq_tdata.value = beat.tdata
        self.dut.s_axis_cq_tuser.value = beat.tuser
        self.dut.s_axis_cq_tvalid.value = 1
        while True:
            await ReadOnly()
            accepted = self.dut.s_axis_cq_tready.value.integer == 1
            await RisingEdge(self.dut.clk)
            if accepted:
                return

    async def idle(self, cycles):
        self.dut.s_axis_cq_tvalid.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk)

    async def monitor(self):
        while True:
            await ReadOnly()
            if (self.dut.m_axis_cq_tvalid.value.integer == 1
                    and self.dut.m_axis_cq_tready.value.integer == 1):
                keep = self.dut.m_axis_cq_tkeep.value.integer
                data = self.dut.m_axis_cq_tdata.value.integer
                dwords = [(data >> (32 * dw)) & 0xffffffff
                          for dw in range(CQ_HALF_DWORDS) if keep & (1 << dw)]
                self.received.append((keep, dwords))
            assert self.dut.status_error_cq_slot_overflow.value.integer == 0, (
                "the gearbox reports a CQ slot overflow: more than two TLP starts or ends "
                "landed in one 512-bit half")
            assert self.dut.status_error_cq_leading_gap.value.integer == 0, (
                "the gearbox reports a CQ leading gap: the low half carries strobed dwords "
                "and dword 0 is not one of them")
            await RisingEdge(self.dut.clk)

    async def grant(self, probability):
        while True:
            self.dut.m_axis_cq_tready.value = 1 if random.random() < probability else 0
            await RisingEdge(self.dut.clk)


def check_bytes(tb, beats):
    expect = []
    for beat in beats:
        expect.extend(beat.expected_halves())

    assert len(tb.received) == len(expect), (
        "the gearbox delivered %d half beats and the %d input beats carry %d occupied "
        "halves" % (len(tb.received), len(beats), len(expect)))

    for index, ((got_keep, got_dwords), (want_keep, want_dwords)) in enumerate(
            zip(tb.received, expect)):
        assert got_keep == want_keep, (
            "half beat %d carries tkeep 0x%04x and its input half is 0x%04x"
            % (index, got_keep, want_keep))
        assert got_dwords == want_dwords, (
            "half beat %d carries %d dwords that are not the dwords the CPM5 face "
            "presented" % (index, len(got_dwords)))


CC_BEAT_DWORDS = 16
CC_IS_SOP_LO = 0
CC_SOP_PTR_LO = 2
CC_IS_EOP_LO = 6
CC_EOP_PTR_LO = 8
CC_DISCONTINUE_LO = 16
CC_SOP_PTR_UNIT_DWORDS = 4


class CcBeat:

    def __init__(self, dwords, sop_dw=None, eop_dw=None, last=False):
        assert len(dwords) <= CC_BEAT_DWORDS
        self.dwords = list(dwords)
        self.sop_dw = sop_dw
        self.eop_dw = eop_dw
        self.last = last

    @property
    def tdata(self):
        value = 0
        for index, dw in enumerate(self.dwords):
            value |= (dw & 0xffffffff) << (32 * index)
        return value

    @property
    def tkeep(self):
        return (1 << len(self.dwords)) - 1

    @property
    def tuser(self):
        value = 0
        if self.sop_dw is not None:
            value |= 1 << CC_IS_SOP_LO
            assert self.sop_dw % CC_SOP_PTR_UNIT_DWORDS == 0, (
                "a CC start at dword %d is not on the %d dword pointer unit"
                % (self.sop_dw, CC_SOP_PTR_UNIT_DWORDS))
            value |= (self.sop_dw // CC_SOP_PTR_UNIT_DWORDS) << CC_SOP_PTR_LO
        if self.eop_dw is not None:
            value |= 1 << CC_IS_EOP_LO
            value |= self.eop_dw << CC_EOP_PTR_LO
        return value


def cc_tlp_beats(payload_dwords, seed):
    beats = []
    remaining = payload_dwords
    first = True
    value = seed
    while remaining > 0:
        take = min(CC_BEAT_DWORDS, remaining)
        dwords = []
        for _ in range(take):
            value = (value * 1103515245 + 12345) & 0xffffffff
            dwords.append(value)
        remaining -= take
        beats.append(CcBeat(dwords,
                            sop_dw=0 if first else None,
                            eop_dw=take - 1 if remaining == 0 else None,
                            last=remaining == 0))
        first = False
    return beats


class CcTb:

    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.cc")
        self.received = []

        cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

        dut.s_axis_cq_tdata.value = 0
        dut.s_axis_cq_tkeep.value = 0
        dut.s_axis_cq_tvalid.value = 0
        dut.s_axis_cq_tlast.value = 0
        dut.s_axis_cq_tuser.value = 0
        dut.m_axis_cq_tready.value = 1

        dut.s_axis_cc_tdata.value = 0
        dut.s_axis_cc_tkeep.value = 0
        dut.s_axis_cc_tvalid.value = 0
        dut.s_axis_cc_tlast.value = 0
        dut.s_axis_cc_tuser.value = 0
        dut.m_axis_cc_tready.value = 0

    async def reset(self):
        self.dut.rst.value = 1
        for _ in range(8):
            await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        for _ in range(4):
            await RisingEdge(self.dut.clk)

    async def send(self, beat):
        self.dut.s_axis_cc_tdata.value = beat.tdata
        self.dut.s_axis_cc_tkeep.value = beat.tkeep
        self.dut.s_axis_cc_tuser.value = beat.tuser
        self.dut.s_axis_cc_tlast.value = 1 if beat.last else 0
        self.dut.s_axis_cc_tvalid.value = 1
        while True:
            await ReadOnly()
            accepted = self.dut.s_axis_cc_tready.value.integer == 1
            await RisingEdge(self.dut.clk)
            if accepted:
                return

    async def idle(self, cycles):
        self.dut.s_axis_cc_tvalid.value = 0
        self.dut.s_axis_cc_tlast.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk)

    async def monitor(self):
        while True:
            await ReadOnly()
            if (self.dut.m_axis_cc_tvalid.value.integer == 1
                    and self.dut.m_axis_cc_tready.value.integer == 1):
                keep = self.dut.m_axis_cc_tkeep.value.integer
                data = self.dut.m_axis_cc_tdata.value.integer
                for dw in range(2 * CC_BEAT_DWORDS):
                    if keep & (1 << dw):
                        self.received.append((data >> (32 * dw)) & 0xffffffff)
            await RisingEdge(self.dut.clk)

    async def grant(self, probability):
        while True:
            self.dut.m_axis_cc_tready.value = 1 if random.random() < probability else 0
            await RisingEdge(self.dut.clk)


@cocotb.test()
async def test_t10_completer_completion_bytes_survive_the_merge(dut):
    random.seed(0xcc10)
    tb = CcTb(dut)
    await tb.reset()

    dut.m_axis_cc_tready.value = 1
    cocotb.start_soon(tb.monitor())

    expect = []
    for payload in (1, 4, 15, 16, 17, 32, 33, 48):
        beats = cc_tlp_beats(payload, seed=payload * 7 + 1)
        for beat in beats:
            expect.extend(beat.dwords)
            await tb.send(beat)
        await tb.idle(2)
    await tb.idle(24)

    assert tb.received == expect, (
        "the gearbox delivered %d dwords on the 1024-bit completer completion face and the "
        "512-bit side presented %d" % (len(tb.received), len(expect)))
    assert dut.status_error_cc_sop_align.value.integer == 0, (
        "the gearbox reports a CC start alignment error on traffic whose starts are all at "
        "dword 0")


@cocotb.test()
async def test_t11_completer_completion_bytes_survive_back_pressure(dut):
    random.seed(0xcc11)
    tb = CcTb(dut)
    await tb.reset()

    cocotb.start_soon(tb.monitor())
    cocotb.start_soon(tb.grant(0.4))

    expect = []
    for round_index in range(4):
        for payload in (1, 7, 16, 24, 32):
            beats = cc_tlp_beats(payload, seed=round_index * 100 + payload)
            for beat in beats:
                expect.extend(beat.dwords)
                await tb.send(beat)
    tb.dut.s_axis_cc_tvalid.value = 0
    for _ in range(600):
        await RisingEdge(dut.clk)
        if len(tb.received) == len(expect):
            break

    assert tb.received == expect, (
        "under back pressure the gearbox delivered %d dwords and the 512-bit side presented "
        "%d" % (len(tb.received), len(expect)))
    assert dut.status_error_cc_sop_align.value.integer == 0, (
        "the gearbox reports a CC start alignment error under back pressure on traffic whose "
        "starts are all at dword 0")


@cocotb.test()
async def test_t12_completer_completion_start_alignment_is_reported(dut):
    random.seed(0xcc12)
    tb = CcTb(dut)
    await tb.reset()

    dut.m_axis_cc_tready.value = 1
    cocotb.start_soon(tb.monitor())

    beat = CcBeat([0x11111111] * 8, sop_dw=0, eop_dw=7, last=True)
    await tb.send(beat)
    await tb.idle(4)
    assert dut.status_error_cc_sop_align.value.integer == 0, (
        "a start at dword 0 is on the 8 dword granularity of CC_SOP_PTR_DW and must not be "
        "reported as misaligned")

    dut.s_axis_cc_tdata.value = beat.tdata
    dut.s_axis_cc_tkeep.value = beat.tkeep
    dut.s_axis_cc_tlast.value = 1
    dut.s_axis_cc_tuser.value = (1 << CC_IS_SOP_LO) | (1 << CC_SOP_PTR_LO) \
        | (1 << CC_IS_EOP_LO) | (7 << CC_EOP_PTR_LO)
    dut.s_axis_cc_tvalid.value = 1

    seen = 0
    for _ in range(8):
        await ReadOnly()
        if dut.status_error_cc_sop_align.value.integer == 1:
            seen = 1
        await RisingEdge(dut.clk)

    dut.s_axis_cc_tvalid.value = 0
    assert seen == 1, (
        "a CC start at dword 4 is not on the 8 dword granularity that CC_SOP_PTR_DW 8 "
        "declares, and status_error_cc_sop_align stayed low: the detector is vacuous")


@cocotb.test()
async def test_t8a_completer_request_bytes_survive_the_split(dut):
    random.seed(0xc0ffee)
    tb = TB(dut)
    await tb.reset()

    dut.m_axis_cq_tready.value = 1
    cocotb.start_soon(tb.monitor())

    beats = beat_set()
    for beat in beats:
        await tb.send(beat)
    await tb.idle(16)

    check_bytes(tb, beats)


@cocotb.test()
async def test_t8b_completer_request_bytes_survive_back_pressure(dut):
    random.seed(0x5eed)
    tb = TB(dut)
    await tb.reset()

    cocotb.start_soon(tb.monitor())
    cocotb.start_soon(tb.grant(0.35))

    beats = []
    for _ in range(6):
        beats.extend(beat_set())
    for beat in beats:
        await tb.send(beat)

    dut.s_axis_cq_tvalid.value = 0
    for _ in range(400):
        await RisingEdge(dut.clk)
        if len(tb.received) == sum(len(b.expected_halves()) for b in beats):
            break

    check_bytes(tb, beats)


@cocotb.test()
async def test_t8c_completer_request_ready_is_a_register_output(dut):
    random.seed(0x1eaf)
    tb = TB(dut)
    await tb.reset()

    cocotb.start_soon(tb.monitor())

    dut.m_axis_cq_tready.value = 0

    beat = CqBeat([(0, 3)])
    dut.s_axis_cq_tdata.value = beat.tdata
    dut.s_axis_cq_tuser.value = beat.tuser
    dut.s_axis_cq_tvalid.value = 1

    accepted = 0
    for _ in range(8):
        await ReadOnly()
        if dut.s_axis_cq_tready.value.integer == 1:
            accepted += 1
        await RisingEdge(dut.clk)
        if accepted == 2:
            break

    assert accepted == 2, (
        "the gearbox took %d beats with the completer side not ready: a skid buffer holds "
        "one beat in its output register and one in its skid register" % accepted)

    await ReadOnly()
    assert dut.s_axis_cq_tready.value.integer == 0, (
        "s_axis_cq_tready is still asserted with both skid stages occupied")
    assert dut.m_axis_cq_tvalid.value.integer == 1, (
        "the gearbox presents no beat downstream, so the ready under test is not the one "
        "that a bypassed skid would drive from m_axis_cq_tready")

    await RisingEdge(dut.clk)

    checks = 0
    for _ in range(40):
        await Timer(1, units="ns")
        before = dut.s_axis_cq_tready.value.integer
        held = dut.m_axis_cq_tready.value.integer

        dut.m_axis_cq_tready.value = 1 - held
        await Timer(1, units="ns")
        after = dut.s_axis_cq_tready.value.integer
        dut.m_axis_cq_tready.value = held

        assert after == before, (
            "s_axis_cq_tready moved from %d to %d inside one cycle when "
            "m_axis_cq_tready changed from %d to %d: 3-R11 requires the ready the CPM5 "
            "block sees to be a register output, so no combinational path exists between "
            "two pins of the hard block" % (before, after, held, 1 - held))
        checks += 1
        await RisingEdge(dut.clk)

    assert checks == 40, (
        "only %d cycles were checked and the test is written to check 40" % checks)


@cocotb.test()
async def test_t8d_completer_request_accepts_at_full_rate(dut):
    random.seed(0xfa57)
    tb = TB(dut)
    await tb.reset()

    dut.m_axis_cq_tready.value = 1
    cocotb.start_soon(tb.monitor())

    beats = [CqBeat([(0, 31)]) for _ in range(32)]
    start = cocotb.utils.get_sim_time(units="ns")
    for beat in beats:
        await tb.send(beat)
    await tb.idle(8)
    elapsed = cocotb.utils.get_sim_time(units="ns") - start

    check_bytes(tb, beats)

    cycles = elapsed / CLK_PERIOD_NS
    assert cycles <= 2 * len(beats) + 12, (
        "%d full beats took %.0f cycles: a 1024-bit beat that fills both halves needs two "
        "512-bit beats, so the skid buffer must not cost throughput beyond that"
        % (len(beats), cycles))
