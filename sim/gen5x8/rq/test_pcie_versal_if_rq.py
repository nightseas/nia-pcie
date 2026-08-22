# ---------------------------------------------------------------------------
# File        : test_pcie_versal_if_rq.py
# Description : The tests of the requester request path: descriptors and byte
#               enables, payload sizes and the end pointer, interleaved ports in
#               order and under back pressure, every sequence number returned once,
#               small writes exercising the start placement, and a pinned
#               elaboration.
# Language    : Python 3
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import itertools
import logging
import os
import random
import sys
from collections import Counter

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from cocotbext.axi import AxiStreamBus
from cocotbext.pcie.core.tlp import Tlp, TlpType

def repo_root_above(start):
    d = start
    while not os.path.isfile(os.path.join(d, ".nia-repo-root")):
        up = os.path.dirname(d)
        if up == d:
            raise RuntimeError(
                "no .nia-repo-root at or above %s: this folder has been copied out of the "
                "nia-pcie tree, so set NIA_ROOT to the checkout" % start)
        d = up
    return d


TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
NIA_ROOT = os.environ.get("NIA_ROOT") or repo_root_above(TESTS_DIR)
MODEL_DIR = os.path.join(NIA_ROOT, "sim", "model")
RTL_DIR = os.path.join(NIA_ROOT, "rtl", "gen5x8")
VP_TB_DIR = os.path.join(NIA_ROOT, "verilog-pcie", "tb")

for _dir in (TESTS_DIR, MODEL_DIR, VP_TB_DIR):
    if _dir not in sys.path:
        sys.path.insert(0, _dir)

from cpm5_pcie_device import (Cpm5Rq1024Sink, RQ1024_BEAT_DWORDS, rq1024_check_tlp,
                              rq1024_tlp)
from pcie_if import PcieIfFrame, PcieIfSource, PcieIfTxBus

RQ_SRC = os.environ.get("RQ_SRC", os.path.join(RTL_DIR, "pcie_versal_if_rq.v"))
RQ_STRADDLE_ENC = int(os.environ.get("PARAM_RQ_STRADDLE_ENC", "1"))
RQ_USER_W = int(os.environ.get("PARAM_AXIS_PCIE_RQ_USER_WIDTH", "373"))
DATA_W = int(os.environ.get("PARAM_AXIS_PCIE_DATA_WIDTH", "1024"))
RQ_SEQ_NUM_W = int(os.environ.get("PARAM_RQ_SEQ_NUM_WIDTH", "6"))
TX_SEQ_NUM_COUNT = int(os.environ.get("PARAM_TX_SEQ_NUM_COUNT", "4"))
TX_SEQ_NUM_W = int(os.environ.get("PARAM_TX_SEQ_NUM_WIDTH", "5"))

SEQ_LIMIT = 1 << TX_SEQ_NUM_W
SEQ_MASK = SEQ_LIMIT - 1
MAX_PAYLOAD_SIZE_ENC = 3
MAX_PAYLOAD_SIZE_BYTES = 128 << MAX_PAYLOAD_SIZE_ENC

ELABORATION_GUARDS = (
    ("AXIS_PCIE_DATA_WIDTH", 1024),
    ("AXIS_PCIE_RQ_USER_WIDTH", 373),
    ("RQ_SEQ_NUM_WIDTH", 6),
    ("TX_SEQ_NUM_COUNT", 4),
)


def incrementing_payload(length):
    return bytearray(itertools.islice(itertools.cycle(range(256)), length))


def single_cycle_grants():
    rand = random.Random(0xc0ffee)
    while True:
        for _ in range(rand.randint(1, 6)):
            yield 1
        yield 0


def random_idle():
    rand = random.Random(0x5eed)
    while True:
        yield rand.random() < 0.4


def read_request(addr, length, tag, seq):
    tlp = Tlp()
    tlp.fmt_type = TlpType.MEM_READ
    tlp.set_addr_be(addr, length)
    tlp.tag = tag
    frame = PcieIfFrame.from_tlp(tlp, force_64bit_addr=True)
    frame.seq = seq
    return tlp, frame


def write_request(addr, data, seq):
    tlp = Tlp()
    tlp.fmt_type = TlpType.MEM_WRITE
    tlp.set_addr_be_data(addr, data)
    frame = PcieIfFrame.from_tlp(tlp, force_64bit_addr=True)
    frame.seq = seq
    return tlp, frame


def check_one_start_per_beat(sink):
    assert sink.max_sop_per_beat() <= 1, (
        "a beat carries %d TLP starts: the one start slot geometry admits one"
        % sink.max_sop_per_beat())
    assert sink.max_eop_per_beat() <= 1, (
        "a beat carries %d TLP ends: the one start slot geometry admits one"
        % sink.max_eop_per_beat())


def check_frame_framing(straddle_enc, frame):
    beats = frame.beats
    assert beats, "the reassembled TLP carries no beat"

    if straddle_enc:
        assert [beat["is_sop"] for beat in beats] == [1] + [0] * (len(beats) - 1), (
            "is_sop over the beats of one TLP is %r, the one start slot geometry is "
            "one start in the first beat and none after it"
            % [beat["is_sop"] for beat in beats])
        assert [beat["is_eop"] for beat in beats] == [0] * (len(beats) - 1) + [1], (
            "is_eop over the beats of one TLP is %r, the one start slot geometry is "
            "one end in the last beat and none before it"
            % [beat["is_eop"] for beat in beats])
        assert beats[0]["sop0_ptr"] == 0, (
            "is_sop0_ptr is %d and 3-R1 requires byte lane 0" % beats[0]["sop0_ptr"])
        assert beats[-1]["eop0_ptr"] == len(beats[-1]["dwords"]) - 1, (
            "is_eop0_ptr is %d and the last beat carries %d dwords"
            % (beats[-1]["eop0_ptr"], len(beats[-1]["dwords"])))
    else:
        assert [beat["tlast"] for beat in beats] == [0] * (len(beats) - 1) + [1], (
            "tlast over the beats of one TLP is %r and must mark the last beat only"
            % [beat["tlast"] for beat in beats])
        assert beats[-1]["tkeep"] == (1 << len(beats[-1]["dwords"])) - 1, (
            "tkeep 0x%08x on the last beat does not match its %d dwords"
            % (beats[-1]["tkeep"], len(beats[-1]["dwords"])))

    for beat in beats[:-1]:
        assert len(beat["dwords"]) == RQ1024_BEAT_DWORDS, (
            "a beat before the last carries %d of %d dwords: a TLP occupies whole beats "
            "from its start" % (len(beat["dwords"]), RQ1024_BEAT_DWORDS))


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)
        self.straddle_enc = RQ_STRADDLE_ENC

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.rd_req_source = PcieIfSource(
            PcieIfTxBus.from_prefix(dut, "tx_rd_req_tlp"), dut.clk, dut.rst)
        self.wr_req_source = PcieIfSource(
            PcieIfTxBus.from_prefix(dut, "tx_wr_req_tlp"), dut.clk, dut.rst)
        self.sink = Cpm5Rq1024Sink(
            AxiStreamBus.from_prefix(dut, "m_axis_rq"), dut.clk, dut.rst,
            straddle_enc=self.straddle_enc)

        for name in ("s_axis_rq_seq_num_0", "s_axis_rq_seq_num_valid_0",
                     "s_axis_rq_seq_num_1", "s_axis_rq_seq_num_valid_1",
                     "s_axis_rq_seq_num_2", "s_axis_rq_seq_num_valid_2",
                     "s_axis_rq_seq_num_3", "s_axis_rq_seq_num_valid_3"):
            if hasattr(dut, name):
                getattr(dut, name).setimmediatevalue(0)

        dut.tx_fc_ph_av.setimmediatevalue(0x80)
        dut.tx_fc_pd_av.setimmediatevalue(0x800)
        dut.tx_fc_nph_av.setimmediatevalue(0x80)
        dut.tx_fc_npd_av.setimmediatevalue(0x800)
        dut.max_payload_size.setimmediatevalue(MAX_PAYLOAD_SIZE_ENC)

    def set_idle_generator(self, generator=None):
        if generator:
            self.rd_req_source.set_pause_generator(generator())
            self.wr_req_source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

    async def cycle_reset(self):
        self.dut.rst.setimmediatevalue(0)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def return_seq_num(self, value):
        self.dut.s_axis_rq_seq_num_0.value = value
        self.dut.s_axis_rq_seq_num_valid_0.value = 1
        await Timer(1, units="ns")
        result = {
            "wr_valid": int(self.dut.m_axis_wr_req_tx_seq_num_valid.value) & 1,
            "wr_value": int(self.dut.m_axis_wr_req_tx_seq_num.value) & SEQ_MASK,
            "rd_valid": int(self.dut.m_axis_rd_req_tx_seq_num_valid.value) & 1,
            "rd_value": int(self.dut.m_axis_rd_req_tx_seq_num.value) & SEQ_MASK,
        }
        await RisingEdge(self.dut.clk)
        self.dut.s_axis_rq_seq_num_valid_0.value = 0
        await RisingEdge(self.dut.clk)
        return result


@cocotb.test()
async def test_t1_read_request_descriptor_and_byte_enables(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    for index, length in enumerate((4, 128)):
        seq = (index + 1) % SEQ_LIMIT
        tlp, frame = read_request(0x1000 + index * 0x100, length, 0x20 + index, seq)
        await tb.rd_req_source.send(frame)

        rx_frame = await tb.sink.recv()
        rq1024_check_tlp(tlp, rx_frame)
        check_frame_framing(tb.straddle_enc, rx_frame)
        check_one_start_per_beat(tb.sink)

        assert len(rx_frame.data) == 4, (
            "a memory read request is 4 descriptor dwords, %d were reassembled"
            % len(rx_frame.data))
        assert len(rx_frame.beats) == 1, (
            "a 4 dword request fits one 1024-bit beat, %d beats were driven"
            % len(rx_frame.beats))
        assert rx_frame.first_be == tlp.first_be, (
            "first_be is 0x%x, the generic side asked for 0x%x"
            % (rx_frame.first_be, tlp.first_be))
        assert rx_frame.last_be == tlp.last_be, (
            "last_be is 0x%x, the generic side asked for 0x%x"
            % (rx_frame.last_be, tlp.last_be))
        assert rx_frame.seq_num & SEQ_MASK == seq, (
            "seq_num0 carries 0x%x, the generic side issued 0x%x"
            % (rx_frame.seq_num & SEQ_MASK, seq))

    assert tb.sink.empty()


@cocotb.test()
async def test_t2_write_request_payload_sizes_and_eop_ptr(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    for index, size in enumerate((4, 64, 128, 256, 512, 1024)):
        assert size <= MAX_PAYLOAD_SIZE_BYTES
        data = incrementing_payload(size)
        seq = index % SEQ_LIMIT
        tlp, frame = write_request(0x2000 + index * 0x1000, data, seq)
        await tb.wr_req_source.send(frame)

        rx_frame = await tb.sink.recv()
        rx_tlp = rq1024_check_tlp(tlp, rx_frame)
        check_frame_framing(tb.straddle_enc, rx_frame)
        check_one_start_per_beat(tb.sink)

        total_dwords = 4 + size // 4
        expect_beats = (total_dwords + RQ1024_BEAT_DWORDS - 1) // RQ1024_BEAT_DWORDS
        assert len(rx_frame.data) == total_dwords, (
            "a %d byte write is 4 descriptor dwords and %d payload dwords, %d were "
            "reassembled" % (size, size // 4, len(rx_frame.data)))
        assert len(rx_frame.beats) == expect_beats, (
            "a %d dword TLP is %d beats of %d dwords, %d beats were driven"
            % (total_dwords, expect_beats, RQ1024_BEAT_DWORDS, len(rx_frame.beats)))
        assert bytes(rx_tlp.get_data()) == bytes(data), (
            "the %d byte payload is not the payload the generic side issued" % size)

        last_dwords = total_dwords - RQ1024_BEAT_DWORDS * (expect_beats - 1)
        if tb.straddle_enc:
            assert rx_frame.beats[-1]["eop0_ptr"] == last_dwords - 1, (
                "is_eop0_ptr is %d, the final beat of a %d dword TLP ends at dword %d"
                % (rx_frame.beats[-1]["eop0_ptr"], total_dwords, last_dwords - 1))
        else:
            assert rx_frame.beats[-1]["tkeep"] == (1 << last_dwords) - 1, (
                "tkeep on the final beat is 0x%08x, a %d dword TLP keeps %d lanes"
                % (rx_frame.beats[-1]["tkeep"], total_dwords, last_dwords))

    assert tb.sink.empty()


@cocotb.test()
async def test_t3_interleaved_ports_saturated_keep_order(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    rand = random.Random(0xa11ce)
    sent_rd = []
    sent_wr = []

    for k in range(24):
        seq = k % SEQ_LIMIT
        rd_tlp, rd_frame = read_request(0x10000 + k * 0x40,
                                        4 * rand.randint(1, 32), k & 0xff, seq)
        sent_rd.append(rd_tlp)
        await tb.rd_req_source.send(rd_frame)

        wr_tlp, wr_frame = write_request(0x20000 + k * 0x400,
                                         incrementing_payload(4 * rand.randint(1, 128)),
                                         seq)
        sent_wr.append(wr_tlp)
        await tb.wr_req_source.send(wr_frame)

    rx_rd = []
    rx_wr = []

    for _ in range(len(sent_rd) + len(sent_wr)):
        rx_frame = await tb.sink.recv()
        check_frame_framing(tb.straddle_enc, rx_frame)
        rx_tlp = rq1024_tlp(rx_frame)
        if rx_tlp.fmt_type in (TlpType.MEM_WRITE, TlpType.MEM_WRITE_64):
            rx_wr.append(rx_frame)
        else:
            rx_rd.append(rx_frame)

    check_one_start_per_beat(tb.sink)

    assert len(rx_rd) == len(sent_rd), (
        "the read port issued %d requests and %d arrived" % (len(sent_rd), len(rx_rd)))
    assert len(rx_wr) == len(sent_wr), (
        "the write port issued %d requests and %d arrived" % (len(sent_wr), len(rx_wr)))

    for index, tlp in enumerate(sent_rd):
        rq1024_check_tlp(tlp, rx_rd[index])

    for index, tlp in enumerate(sent_wr):
        rq1024_check_tlp(tlp, rx_wr[index])

    assert tb.sink.empty()


@cocotb.test()
async def test_t4_interleaved_ports_under_backpressure_keep_every_byte(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    tb.set_idle_generator(random_idle)
    tb.set_backpressure_generator(single_cycle_grants)

    rand = random.Random(0xb0b)
    sent_rd = []
    sent_wr = []

    for k in range(16):
        seq = k % SEQ_LIMIT
        rd_tlp, rd_frame = read_request(0x30000 + k * 0x40,
                                        4 * rand.randint(1, 16), k & 0xff, seq)
        sent_rd.append(rd_tlp)
        await tb.rd_req_source.send(rd_frame)

        wr_tlp, wr_frame = write_request(0x40000 + k * 0x400,
                                        incrementing_payload(4 * rand.randint(1, 64)),
                                        seq)
        sent_wr.append(wr_tlp)
        await tb.wr_req_source.send(wr_frame)

    rx_rd = []
    rx_wr = []

    for _ in range(len(sent_rd) + len(sent_wr)):
        rx_frame = await tb.sink.recv()
        check_frame_framing(tb.straddle_enc, rx_frame)
        rx_tlp = rq1024_tlp(rx_frame)
        if rx_tlp.fmt_type in (TlpType.MEM_WRITE, TlpType.MEM_WRITE_64):
            rx_wr.append(rx_frame)
        else:
            rx_rd.append(rx_frame)

    check_one_start_per_beat(tb.sink)

    assert len(rx_rd) == len(sent_rd), (
        "the read port issued %d requests and %d arrived under back pressure"
        % (len(sent_rd), len(rx_rd)))
    assert len(rx_wr) == len(sent_wr), (
        "the write port issued %d requests and %d arrived under back pressure"
        % (len(sent_wr), len(rx_wr)))

    for index, tlp in enumerate(sent_rd):
        rq1024_check_tlp(tlp, rx_rd[index])

    for index, tlp in enumerate(sent_wr):
        rq1024_check_tlp(tlp, rx_wr[index])

    assert tb.sink.empty()


@cocotb.test()
async def test_t5_sequence_numbers_returned_exactly_once(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    issued = []

    for k in range(64):
        seq = k % SEQ_LIMIT
        tlp, frame = write_request(0x50000 + k * 0x100, incrementing_payload(64), seq)
        issued.append(seq)
        await tb.wr_req_source.send(frame)

    observed = []

    for k in range(64):
        rx_frame = await tb.sink.recv()
        observed.append(rx_frame.seq_num)

    assert [value & SEQ_MASK for value in observed] == issued, (
        "the write port issued %r and the RQ interface carried %r"
        % (issued, [value & SEQ_MASK for value in observed]))

    returned = Counter()

    for value in observed:
        result = await tb.return_seq_num(value)
        assert result["wr_valid"] == 1, (
            "sequence number 0x%x was issued by the write port and did not return on the "
            "write port" % value)
        assert result["rd_valid"] == 0, (
            "sequence number 0x%x was issued by the write port and returned on the read "
            "port as well" % value)
        returned[result["wr_value"]] += 1

    assert returned == Counter(issued), (
        "the write port issued %r and %r came back" % (sorted(issued), sorted(returned.elements())))

    assert tb.sink.empty()


@cocotb.test()
async def test_t6_payload_only_beat_carries_no_start_and_no_end(dut):
    tb = TB(dut)
    await tb.cycle_reset()

    data = incrementing_payload(512)
    tlp, frame = write_request(0x60000, data, 1)
    await tb.wr_req_source.send(frame)

    rx_frame = await tb.sink.recv()
    rq1024_check_tlp(tlp, rx_frame)
    check_frame_framing(tb.straddle_enc, rx_frame)
    check_one_start_per_beat(tb.sink)

    middle = rx_frame.beats[1:-1]
    assert middle, (
        "a 512 byte write is %d dwords and must occupy a beat that is neither a start "
        "nor an end" % len(rx_frame.data))

    for index, beat in enumerate(middle):
        assert beat["is_sop"] == 0, (
            "the payload only beat %d carries is_sop 0x%x" % (index + 1, beat["is_sop"]))
        assert beat["is_eop"] == 0, (
            "the payload only beat %d carries is_eop 0x%x" % (index + 1, beat["is_eop"]))
        assert len(beat["dwords"]) == RQ1024_BEAT_DWORDS, (
            "the payload only beat %d carries %d of %d dwords"
            % (index + 1, len(beat["dwords"]), RQ1024_BEAT_DWORDS))
        assert beat["tlast"] == 0, (
            "the payload only beat %d asserts tlast" % (index + 1))
        if tb.straddle_enc:
            assert beat["tkeep"] == 0, (
                "the payload only beat %d drives tkeep 0x%08x at RQ_STRADDLE_ENC 1"
                % (index + 1, beat["tkeep"]))
        else:
            assert beat["tkeep"] == (1 << RQ1024_BEAT_DWORDS) - 1, (
                "the payload only beat %d drives tkeep 0x%08x and every lane is valid"
                % (index + 1, beat["tkeep"]))

    assert tb.sink.empty()


@cocotb.test()
async def test_t7_elaboration_is_pinned_and_guarded(dut):
    assert len(dut.m_axis_rq_tdata) == DATA_W == 1024, (
        "the module elaborated at %d bits and this geometry is 1024 only"
        % len(dut.m_axis_rq_tdata))
    assert len(dut.m_axis_rq_tuser) == RQ_USER_W == 373, (
        "the module elaborated with a %d bit RQ tuser and the CPM5 1024-bit RQ face is 373"
        % len(dut.m_axis_rq_tuser))
    assert len(dut.m_axis_rq_tkeep) == RQ1024_BEAT_DWORDS
    assert len(dut.s_axis_rq_seq_num_0) == RQ_SEQ_NUM_W == 6, (
        "the module elaborated with a %d bit RQ sequence number and this geometry is 6"
        % len(dut.s_axis_rq_seq_num_0))
    assert TX_SEQ_NUM_COUNT == 4
    assert len(dut.m_axis_wr_req_tx_seq_num_valid) == 4, (
        "the module elaborated with %d TX sequence number slots and the CPM5 1024-bit RQ face "
        "returns four" % len(dut.m_axis_wr_req_tx_seq_num_valid))
    assert len(dut.m_axis_rd_req_tx_seq_num_valid) == 4
    assert len(dut.m_axis_wr_req_tx_seq_num) == 4 * TX_SEQ_NUM_W

    with open(RQ_SRC) as handle:
        source = handle.read()

    for name, value in ELABORATION_GUARDS:
        pattern = f"{name} != {value}"
        alternate = f"{name} !== {value}"
        assert pattern in source or alternate in source, (
            "%s carries no '%s' guard, so 3-R7 cannot refuse that configuration"
            % (os.path.basename(RQ_SRC), pattern))

    assert source.count("$error") >= len(ELABORATION_GUARDS), (
        "%s carries %d $error calls and 3-R7 needs one per guard"
        % (os.path.basename(RQ_SRC), source.count("$error")))
    assert "$finish" in source, (
        "%s carries no $finish, so a refusal would not stop the simulation"
        % os.path.basename(RQ_SRC))
