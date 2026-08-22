# ---------------------------------------------------------------------------
# File        : cpm5_pcie_device.py
# Description : CPM5 PCIE mode device model for cocotb. Presents the CPM5
#               tuser widths on the four request and completion interfaces, so
#               a testbench drives a design the way the block does.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import contextlib
import logging

import cocotb
from cocotb.queue import Queue
from cocotb.triggers import RisingEdge

from cocotbext.pcie.core.tlp import Tlp
from cocotbext.pcie.xilinx.us.interface import RqSink, CqSource
from cocotbext.pcie.xilinx.us.interface import UsPcieFrame
from cocotbext.pcie.xilinx.us.tlp import Tlp_us
from cocotbext.pcie.xilinx.us import UltraScalePlusPcieDevice
from cocotbext.pcie.xilinx.us import usp_model

CPM5_RQ_USER_W = 183
CPM5_CQ_USER_W = 231
RC_USER_W = 161
CC_USER_W = 81

CQ_POISON_OFFSET = 229

class Cpm5RqSink(RqSink):

    def _init(self):
        assert self.width == 512, \
            "this model is 512-bit only (1024 is forbidden - PLAN A4)"
        assert len(self.bus.tuser) == CPM5_RQ_USER_W, (
            f"CPM5 RQ tuser must be {CPM5_RQ_USER_W} (US+ is 137). "
            f"Got {len(self.bus.tuser)} - is the DUT presenting its US+ face by mistake?")
        assert self.seg_count in {1, 2}, "RQ straddles up to 2 TLP at 512-bit"
        self.discontinue_offset = 36
        self.parity_offset = 73

class Cpm5CqSource(CqSource):

    def _init(self):
        assert self.width == 512, \
            "this model is 512-bit only (1024 is forbidden)"
        assert len(self.bus.tuser) == CPM5_CQ_USER_W, (
            f"CPM5 CQ tuser must be {CPM5_CQ_USER_W} (US+ is 183). "
            f"Got {len(self.bus.tuser)}")
        assert self.seg_count in {1, 2}, "CQ straddles up to 2 TLP at 512-bit"
        self.byte_en_offset = 16
        self.discontinue_offset = 96
        self.parity_offset = 119
        self.inject_poison = 0

    async def _drive(self, obj):
        if self.inject_poison:
            obj.tuser |= (self.inject_poison & 0x3) << CQ_POISON_OFFSET
        return await super()._drive(obj)

@contextlib.contextmanager
def _cpm5_interfaces():
    saved_rq = usp_model.RqSink
    saved_cq = usp_model.CqSource
    usp_model.RqSink = Cpm5RqSink
    usp_model.CqSource = Cpm5CqSource
    try:
        yield
    finally:
        usp_model.RqSink = saved_rq
        usp_model.CqSource = saved_cq

class Cpm5PcieDevice(UltraScalePlusPcieDevice):
    def __init__(self, *args, **kwargs):
        with _cpm5_interfaces():
            super().__init__(*args, **kwargs)

        if self.rq_sink is not None and not isinstance(self.rq_sink, Cpm5RqSink):
            raise RuntimeError(
                "Cpm5PcieDevice: rq_sink is %r, not Cpm5RqSink - the installed cocotbext-pcie "
                "no longer resolves RqSink from cocotbext.pcie.xilinx.us.usp_model"
                % type(self.rq_sink))
        if self.cq_source is not None and not isinstance(self.cq_source, Cpm5CqSource):
            raise RuntimeError(
                "Cpm5PcieDevice: cq_source is %r, not Cpm5CqSource - see above"
                % type(self.cq_source))

    def poison_next_cq(self, bits=0b01):
        self.cq_source.inject_poison = bits & 0x3

    def stop_poisoning_cq(self):
        self.cq_source.inject_poison = 0


CPM5_RQ1024_USER_W = 373
RQ1024_DATA_W = 1024
RQ1024_BEAT_DWORDS = 32
RQ1024_THERMOMETER = (0b0000, 0b0001, 0b0011, 0b0111, 0b1111)
RQ1024_ONE_SLOT_IS_SOP = (0b0000, 0b0001)
RQ1024_ONE_SLOT_IS_EOP = (0b0000, 0b0001)

RQ1024_FIRST_BE_LO = 0
RQ1024_FIRST_BE_UNUSED_LO = 4
RQ1024_FIRST_BE_UNUSED_W = 12
RQ1024_LAST_BE_LO = 16
RQ1024_LAST_BE_UNUSED_LO = 20
RQ1024_LAST_BE_UNUSED_W = 12
RQ1024_ADDR_OFFSET_LO = 32
RQ1024_ADDR_OFFSET_W = 16
RQ1024_IS_SOP_LO = 48
RQ1024_IS_SOP_W = 4
RQ1024_SOP0_PTR_LO = 52
RQ1024_SOP0_PTR_W = 2
RQ1024_SOP_PTR_REST_LO = 54
RQ1024_SOP_PTR_REST_W = 6
RQ1024_IS_EOP_LO = 60
RQ1024_IS_EOP_W = 4
RQ1024_EOP0_PTR_LO = 64
RQ1024_EOP0_PTR_W = 5
RQ1024_EOP_PTR_REST_LO = 69
RQ1024_EOP_PTR_REST_W = 15
RQ1024_DISCONTINUE_LO = 84
RQ1024_SEQ_NUM0_LO = 349
RQ1024_SEQ_NUM_W = 6
RQ1024_SEQ_NUM_REST_LO = 355
RQ1024_SEQ_NUM_REST_W = 18

RQ1024_SOP_LANE_BYTES = 32


def rq1024_field(vec, lo, width):
    return (int(vec) >> lo) & ((1 << width) - 1)


def rq1024_beat_dwords(tdata, dword_count):
    return [(int(tdata) >> (32 * k)) & 0xffffffff for k in range(dword_count)]


def rq1024_expected_beats(dwords):
    return [list(dwords[k:k + RQ1024_BEAT_DWORDS])
            for k in range(0, len(dwords), RQ1024_BEAT_DWORDS)]


def rq1024_tlp(rx_frame):
    return Tlp(Tlp_us.unpack_us_rq(rx_frame))


def rq1024_check_tlp(sent_tlp, rx_frame):
    rx_tlp = rq1024_tlp(rx_frame)

    sent_bytes = bytes(sent_tlp.get_data())
    rx_bytes = bytes(rx_tlp.get_data())

    assert len(rx_bytes) == len(sent_bytes), (
        "RQ TLP carries %d payload bytes, the generic side issued %d"
        % (len(rx_bytes), len(sent_bytes)))

    for k in range(len(sent_bytes)):
        assert rx_bytes[k] == sent_bytes[k], (
            "RQ TLP payload byte %d is 0x%02x, the generic side issued 0x%02x"
            % (k, rx_bytes[k], sent_bytes[k]))

    assert sent_tlp == rx_tlp, (
        "RQ TLP %r is not the TLP the generic side issued %r" % (rx_tlp, sent_tlp))

    beats = [beat["dwords"] for beat in rx_frame.beats]
    expect = rq1024_expected_beats(rx_frame.data)
    assert beats == expect, (
        "RQ beat sequence carries %r dwords per beat, the one start slot geometry of a "
        "%d dword TLP is %r" % ([len(b) for b in beats], len(rx_frame.data),
                                [len(b) for b in expect]))

    return rx_tlp


class Cpm5Rq1024Sink:

    def __init__(self, bus, clock, reset=None, straddle_enc=1):
        self.bus = bus
        self.clock = clock
        self.reset = reset
        self.straddle_enc = int(straddle_enc)

        if bus._name:
            self.log = logging.getLogger(f"cocotb.{bus._entity._name}.{bus._name}")
        else:
            self.log = logging.getLogger(f"cocotb.{bus._entity._name}")

        assert len(self.bus.tdata) == RQ1024_DATA_W, (
            f"CPM5 RQ tdata must be {RQ1024_DATA_W} bits, got {len(self.bus.tdata)}")
        assert len(self.bus.tkeep) == RQ1024_BEAT_DWORDS, (
            f"CPM5 RQ tkeep must be {RQ1024_BEAT_DWORDS} bits, got {len(self.bus.tkeep)}")
        assert len(self.bus.tuser) == CPM5_RQ1024_USER_W, (
            f"CPM5 RQ tuser must be {CPM5_RQ1024_USER_W} bits at 1024, "
            f"got {len(self.bus.tuser)}")
        assert self.straddle_enc in (0, 1), (
            f"RQ_STRADDLE_ENC must be 0 or 1, got {self.straddle_enc}")

        self.queue = Queue()
        self.beats = []
        self.frame = None
        self.frame_beats = []

        self._pause = False
        self._pause_generator = None
        self._pause_cr = None

        self.bus.tready.setimmediatevalue(0)

        cocotb.start_soon(self._run())

    def count(self):
        return self.queue.qsize()

    def empty(self):
        return self.queue.empty()

    async def recv(self):
        return await self.queue.get()

    def clear_beats(self):
        self.beats = []

    def max_sop_per_beat(self):
        return max([beat["sop_count"] for beat in self.beats], default=0)

    def max_eop_per_beat(self):
        return max([beat["eop_count"] for beat in self.beats], default=0)

    @property
    def pause(self):
        return self._pause

    @pause.setter
    def pause(self, val):
        self._pause = bool(val)

    def set_pause_generator(self, generator=None):
        if self._pause_cr is not None:
            self._pause_cr.kill()
            self._pause_cr = None

        self._pause_generator = generator

        if self._pause_generator is not None:
            self._pause_cr = cocotb.start_soon(self._run_pause())

    def clear_pause_generator(self):
        self.set_pause_generator(None)

    async def _run_pause(self):
        clock_edge_event = RisingEdge(self.clock)

        for val in self._pause_generator:
            self.pause = val
            await clock_edge_event

    @staticmethod
    def _handshake(signal):
        try:
            return int(signal.value)
        except ValueError:
            return 0

    def _resolved(self, signal, name):
        try:
            return int(signal.value)
        except ValueError:
            raise AssertionError(
                f"CPM5 RQ {name} carries x or z on a beat the core accepts: "
                f"{signal.value}")

    async def _run(self):
        clock_edge_event = RisingEdge(self.clock)

        while True:
            await clock_edge_event

            if self.reset is not None and self._handshake(self.reset):
                self.bus.tready.value = 0
                self.frame = None
                self.frame_beats = []
                continue

            if self._handshake(self.bus.tvalid) and self._handshake(self.bus.tready):
                self._sink_beat(
                    self._resolved(self.bus.tdata, "tdata"),
                    self._resolved(self.bus.tkeep, "tkeep"),
                    self._resolved(self.bus.tlast, "tlast"),
                    self._resolved(self.bus.tuser, "tuser"))

            self.bus.tready.value = 0 if self._pause else 1

    def _check_sideband(self, tuser, is_sop, is_eop):
        assert is_sop in RQ1024_THERMOMETER, (
            "CPM5 RQ is_sop 0x%x is not a thermometer count: PG346 Table 28 admits only "
            "0b0000, 0b0001, 0b0011, 0b0111 and 0b1111" % is_sop)
        assert is_eop in RQ1024_THERMOMETER, (
            "CPM5 RQ is_eop 0x%x is not a thermometer count: PG346 Table 28 admits only "
            "0b0000, 0b0001, 0b0011, 0b0111 and 0b1111" % is_eop)
        assert is_sop in RQ1024_ONE_SLOT_IS_SOP, (
            "CPM5 RQ is_sop 0x%x claims %d TLP starts in one beat: the one start slot "
            "geometry admits 0b0000 and 0b0001" % (is_sop, bin(is_sop).count("1")))
        assert is_eop in RQ1024_ONE_SLOT_IS_EOP, (
            "CPM5 RQ is_eop 0x%x claims %d TLP ends in one beat: the one start slot "
            "geometry admits 0b0000 and 0b0001" % (is_eop, bin(is_eop).count("1")))

        sop0_ptr = rq1024_field(tuser, RQ1024_SOP0_PTR_LO, RQ1024_SOP0_PTR_W)

        if is_sop:
            assert sop0_ptr == 0, (
                "CPM5 RQ start is at byte lane %d: PG346 p.89 places a TLP that starts in "
                "a fresh beat at byte lane 0, is_sop0_ptr 2'b00"
                % (sop0_ptr * RQ1024_SOP_LANE_BYTES))

        assert rq1024_field(tuser, RQ1024_SOP_PTR_REST_LO, RQ1024_SOP_PTR_REST_W) == 0, (
            "CPM5 RQ is_sop1_ptr to is_sop3_ptr are not zero: there is one start slot")
        assert rq1024_field(tuser, RQ1024_EOP_PTR_REST_LO, RQ1024_EOP_PTR_REST_W) == 0, (
            "CPM5 RQ is_eop1_ptr to is_eop3_ptr are not zero: there is one end slot")
        assert rq1024_field(tuser, RQ1024_SEQ_NUM_REST_LO, RQ1024_SEQ_NUM_REST_W) == 0, (
            "CPM5 RQ seq_num1 to seq_num3 are not zero: one start slot carries one "
            "sequence number")
        assert rq1024_field(tuser, RQ1024_ADDR_OFFSET_LO, RQ1024_ADDR_OFFSET_W) == 0, (
            "CPM5 RQ addr_offset is not zero: the interface is in dword aligned mode")
        assert rq1024_field(tuser, RQ1024_DISCONTINUE_LO, 1) == 0, (
            "CPM5 RQ discontinue is asserted: this design aborts no TLP")
        assert rq1024_field(tuser, RQ1024_FIRST_BE_UNUSED_LO,
                            RQ1024_FIRST_BE_UNUSED_W) == 0, (
            "CPM5 RQ first_be[15:4] is not zero: one start slot uses first_be[3:0]")
        assert rq1024_field(tuser, RQ1024_LAST_BE_UNUSED_LO,
                            RQ1024_LAST_BE_UNUSED_W) == 0, (
            "CPM5 RQ last_be[31:20] is not zero: one start slot uses last_be[19:16]")

        return sop0_ptr

    def _framing(self, tkeep, tlast, is_sop, is_eop, eop0_ptr):
        if self.straddle_enc:
            assert tkeep == 0, (
                "CPM5 RQ tkeep is 0x%08x at RQ_STRADDLE_ENC 1: the core ignores tkeep on "
                "a straddling RQ interface, PG346 p.87, and the module drives it to zero"
                % tkeep)
            assert tlast == 0, (
                "CPM5 RQ tlast is asserted at RQ_STRADDLE_ENC 1: the core ignores tlast "
                "on a straddling RQ interface, PG346 p.87, and the module drives it to zero")
            sop = bool(is_sop)
            eop = bool(is_eop)
            dword_count = eop0_ptr + 1 if eop else RQ1024_BEAT_DWORDS
        else:
            assert is_sop == 0, (
                "CPM5 RQ is_sop is 0x%x at RQ_STRADDLE_ENC 0: tkeep and tlast are the "
                "framing and is_sop is driven to zero" % is_sop)
            assert is_eop == 0, (
                "CPM5 RQ is_eop is 0x%x at RQ_STRADDLE_ENC 0: tkeep and tlast are the "
                "framing and is_eop is driven to zero" % is_eop)
            keep_count = bin(tkeep).count("1")
            assert keep_count > 0, (
                "CPM5 RQ tkeep is zero on a beat the core accepts at RQ_STRADDLE_ENC 0")
            assert tkeep == (1 << keep_count) - 1, (
                "CPM5 RQ tkeep 0x%08x is not a contiguous run from byte lane 0" % tkeep)
            sop = self.frame is None
            eop = bool(tlast)
            dword_count = keep_count

        return sop, eop, dword_count

    def _sink_beat(self, tdata, tkeep, tlast, tuser):
        is_sop = rq1024_field(tuser, RQ1024_IS_SOP_LO, RQ1024_IS_SOP_W)
        is_eop = rq1024_field(tuser, RQ1024_IS_EOP_LO, RQ1024_IS_EOP_W)
        eop0_ptr = rq1024_field(tuser, RQ1024_EOP0_PTR_LO, RQ1024_EOP0_PTR_W)

        sop0_ptr = self._check_sideband(tuser, is_sop, is_eop)
        sop, eop, dword_count = self._framing(tkeep, tlast, is_sop, is_eop, eop0_ptr)

        if sop:
            assert self.frame is None, (
                "CPM5 RQ start while the previous TLP is still open: %r" % self.frame)
            self.frame = UsPcieFrame()
            self.frame.first_be = rq1024_field(tuser, RQ1024_FIRST_BE_LO, 4)
            self.frame.last_be = rq1024_field(tuser, RQ1024_LAST_BE_LO, 4)
            self.frame.seq_num = rq1024_field(tuser, RQ1024_SEQ_NUM0_LO, RQ1024_SEQ_NUM_W)
            self.frame_beats = []

        assert self.frame is not None, (
            "CPM5 RQ beat carries %d dwords with no open TLP: the start of this TLP was "
            "never presented" % dword_count)

        dwords = rq1024_beat_dwords(tdata, dword_count)
        self.frame.data.extend(dwords)

        beat = {
            "tdata": tdata,
            "tkeep": tkeep,
            "tlast": tlast,
            "tuser": tuser,
            "is_sop": is_sop,
            "is_eop": is_eop,
            "sop_count": bin(is_sop).count("1"),
            "eop_count": bin(is_eop).count("1"),
            "sop0_ptr": sop0_ptr,
            "eop0_ptr": eop0_ptr,
            "dwords": dwords,
        }
        self.beats.append(beat)
        self.frame_beats.append(beat)

        if eop:
            self.frame.beats = self.frame_beats
            self.log.info("RX CPM5 RQ 1024 frame: %r", self.frame)
            self.queue.put_nowait(self.frame)
            self.frame = None
            self.frame_beats = []
