# ---------------------------------------------------------------------------
# File        : test_pcie_versal_msix_adapt.py
# Description : Acceptance testbench for pcie_versal_msix_adapt, driven against a
#               CPM5 MSI-X stub that reports the protocol violations it observes.
#               One test per requirement: the vector number is binary and stable
#               before the request, one request is outstanding at a time, one
#               accept per ready beat, an out of range or disabled index is dropped
#               rather than stalled, a function masked request is still forwarded,
#               a failed request is retransmitted a bounded number of times, the
#               static pins never move, the counters saturate, a reset in the
#               middle of a request leaves no state behind, and a random burst
#               loses and reorders nothing.
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
from cocotb.triggers import RisingEdge, ReadOnly, Timer

IRQ_INDEX_WIDTH = int(os.environ.get("PARAM_IRQ_INDEX_WIDTH", "6"))
MSIX_VECTOR_COUNT = int(os.environ.get("PARAM_MSIX_VECTOR_COUNT", "8"))
FAIL_RETRY_LIMIT = int(os.environ.get("PARAM_FAIL_RETRY_LIMIT", "3"))
STS_COUNT_WIDTH = int(os.environ.get("PARAM_STS_COUNT_WIDTH", "8"))

class Cpm5MsixStub:

    def __init__(self, dut, latency=2):
        self.dut = dut
        self.latency = latency
        self.seen = []
        self.fail_next = 0
        self.enable = 1
        self.mask = 0
        self.violations = []
        self.outstanding = False

    async def run(self):
        dut = self.dut
        dut.cfg_msix_sent.value = 0
        dut.cfg_msix_fail.value = 0
        dut.cfg_msix_vec_pending_status.value = 0
        last_int = 0
        prev_mint = 0
        cyc = 0
        pending = None
        wait = 0
        drive_sent = 0
        drive_fail = 0
        while True:
            await RisingEdge(dut.clk)
            cyc += 1
            dut.cfg_msix_sent.value = drive_sent
            dut.cfg_msix_fail.value = drive_fail
            dut.cfg_msix_enable.value = self.enable
            dut.cfg_msix_mask.value = self.mask
            drive_sent = 0
            drive_fail = 0

            await ReadOnly()
            try:
                cur = int(dut.cfg_msix_int_vector.value)
                mint = int(dut.cfg_msix_mint_vector.value)
                vp = int(dut.cfg_msix_vec_pending.value)
                fn = int(dut.cfg_msix_function_number.value)
            except ValueError:
                last_int = 0
                continue

            if cur and not last_int:
                if prev_mint != mint:
                    self.violations.append(
                        "D-1: mint_vector was %r the cycle before int_vector rose and %r on it "
                        "(cycle %d) - the vector number must be stable first"
                        % (prev_mint, mint, cyc))
                if vp != 0:
                    self.violations.append("D-7: vec_pending = 0b%02b on a request (must be 00)" % vp)
                if fn != 0:
                    self.violations.append("D-7: function_number = %d on a request (must be 0)" % fn)
                if self.outstanding:
                    self.violations.append("D-1: a second request while one was outstanding")
                self.outstanding = True
                self.seen.append((mint, cyc))
                pending = mint
                wait = self.latency
            last_int = cur
            prev_mint = mint

            if pending is not None:
                if wait > 0:
                    wait -= 1
                else:
                    if self.fail_next > 0:
                        self.fail_next -= 1
                        drive_fail = 1
                    else:
                        drive_sent = 1
                    pending = None
                    self.outstanding = False

    def check(self):
        assert not self.violations, "CPM5 protocol violations:\n  " + "\n  ".join(self.violations)

async def setup(dut, seed=None, latency=2):
    if seed is not None:
        random.seed(seed)
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    dut.rst.setimmediatevalue(1)
    dut.irq_index.setimmediatevalue(0)
    dut.irq_valid.setimmediatevalue(0)
    dut.cfg_msix_enable.setimmediatevalue(1)
    dut.cfg_msix_mask.setimmediatevalue(0)
    dut.cfg_msix_sent.setimmediatevalue(0)
    dut.cfg_msix_fail.setimmediatevalue(0)
    dut.cfg_msix_vec_pending_status.setimmediatevalue(0)
    stub = Cpm5MsixStub(dut, latency=latency)
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    cocotb.start_soon(stub.run())
    await RisingEdge(dut.clk)
    return stub

async def request(dut, index, timeout=400):
    dut.irq_index.value = index
    dut.irq_valid.value = 1
    for n in range(timeout):
        await ReadOnly()
        try:
            rdy = dut.irq_ready.value.binstr == "1"
        except Exception:
            rdy = False
        await RisingEdge(dut.clk)
        if rdy:
            dut.irq_valid.value = 0
            await settle(dut)
            return n + 1
    dut.irq_valid.value = 0
    raise AssertionError("irq_ready never asserted for index %d within %d cycles - the mapper is "
                         "STALLING, which deadlocks every event queue in the NIC" % (index, timeout))

async def settle(dut, limit=3000):
    for _ in range(limit):
        await ReadOnly()
        try:
            busy = dut.sts_busy.value.binstr == "1"
        except Exception:
            busy = True
        await RisingEdge(dut.clk)
        if not busy:
            await RisingEdge(dut.clk)
            await RisingEdge(dut.clk)
            return
    raise AssertionError("the mapper never returned to idle within %d cycles" % limit)

def sts(dut):
    return dict(
        sent=int(dut.sts_irq_sent_count.value),
        fail=int(dut.sts_irq_fail_count.value),
        dis=int(dut.sts_irq_drop_disabled.value),
        oor=int(dut.sts_irq_drop_oor.value),
        rty=int(dut.sts_irq_drop_retry.value),
        masked=int(dut.sts_irq_masked_seen.value),
    )

@cocotb.test()
async def test_vector_fidelity_binary_not_onehot(dut):
    stub = await setup(dut, seed=1)
    for idx in range(MSIX_VECTOR_COUNT):
        await request(dut, idx)
    stub.check()
    got = [v for v, _ in stub.seen]
    assert got == list(range(MSIX_VECTOR_COUNT)), \
        ("mint_vector sequence was %r, expected %r.\n"
         "If it looks like [1, 2, 4, 8, ...] the mapper built a CPM4 ONE-HOT; PG346 Table 44 p.127 "
         "says CPM5 carries the VECTOR NUMBER (contract Section 5.1)." % (got, list(range(MSIX_VECTOR_COUNT))))
    s = sts(dut)
    assert s["sent"] == MSIX_VECTOR_COUNT, "sent count %d, expected %d" % (s["sent"], MSIX_VECTOR_COUNT)
    assert s["fail"] == 0 and s["dis"] == 0 and s["oor"] == 0 and s["rty"] == 0, \
        "unexpected drops on the clean path: %r" % s
    dut._log.info("D-1/Section 5.1 vector fidelity: %d/%d indices arrived as their own number",
                  len(got), MSIX_VECTOR_COUNT)

@cocotb.test()
async def test_d2_one_accept_per_ready_beat(dut):
    stub = await setup(dut, seed=2, latency=2)
    dut.irq_index.value = 3
    dut.irq_valid.value = 1
    transfers = 0
    for _ in range(200):
        await ReadOnly()
        rdy = dut.irq_ready.value.binstr == "1"
        vld = dut.irq_valid.value.binstr == "1"
        await RisingEdge(dut.clk)
        if rdy and vld:
            transfers += 1
    dut.irq_valid.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
    stub.check()
    presented = len(stub.seen)
    assert transfers > 3, "the handshake never ran (%d transfers) - nothing was gated" % transfers
    assert presented == transfers, \
        ("%d beats were accepted (irq_valid && irq_ready) but %d interrupts were presented to the "
         "CIPS. Equality is the whole handshake contract; presentations > transfers is DEFECT-I5-1 "
         "(a second accept of the same beat, with a stale index)." % (transfers, presented))
    assert all(v == 3 for v, _ in stub.seen), \
        "every presentation must carry index 3; saw %r" % ([v for v, _ in stub.seen],)
    dut._log.info("D-2: %d accepted beats -> %d presentations, all index 3", transfers, presented)

@cocotb.test()
async def test_d1_one_outstanding_request(dut):
    stub = await setup(dut, seed=3, latency=5)
    for idx in [0, 1, 2, 1, 0, MSIX_VECTOR_COUNT - 1]:
        await request(dut, idx)
    stub.check()
    assert [v for v, _ in stub.seen] == [0, 1, 2, 1, 0, MSIX_VECTOR_COUNT - 1], \
        "order or content wrong: %r" % (stub.seen,)

@cocotb.test()
async def test_d4_out_of_range_is_dropped_not_stalled(dut):
    if MSIX_VECTOR_COUNT >= 2 ** IRQ_INDEX_WIDTH:
        cocotb.log.info("skipped: no representable out-of-range index in this configuration "
                        "(MSIX_VECTOR_COUNT=%d, 2**IRQ_INDEX_WIDTH=%d)"
                        % (MSIX_VECTOR_COUNT, 2 ** IRQ_INDEX_WIDTH))
        return
    stub = await setup(dut, seed=4)
    before = len(stub.seen)
    oor_index = MSIX_VECTOR_COUNT
    await request(dut, oor_index)
    await request(dut, 2 ** IRQ_INDEX_WIDTH - 1)
    stub.check()
    assert len(stub.seen) == before, \
        "an out-of-range vector was presented to the CIPS: %r" % (stub.seen[before:],)
    s = sts(dut)
    assert s["oor"] == 2, "drop_oor = %d, expected 2" % s["oor"]
    assert s["sent"] == 0, "sent = %d on an out-of-range request" % s["sent"]
    await request(dut, 0)
    assert sts(dut)["sent"] == 1, "the mapper did not recover after an out-of-range drop"

@cocotb.test()
async def test_d5_disabled_is_dropped_not_stalled(dut):
    stub = await setup(dut, seed=5)
    stub.enable = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    before = len(stub.seen)
    await request(dut, 2)
    await request(dut, 3)
    stub.check()
    assert len(stub.seen) == before, "a request was presented while MSI-X was disabled"
    assert sts(dut)["dis"] == 2, "drop_disabled = %d, expected 2" % sts(dut)["dis"]
    stub.enable = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await request(dut, 4)
    stub.check()
    assert [v for v, _ in stub.seen][-1] == 4, "delivery did not resume after re-enable"

@cocotb.test()
async def test_d6_function_masked_is_still_forwarded(dut):
    stub = await setup(dut, seed=6)
    stub.mask = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await request(dut, 5)
    stub.check()
    assert [v for v, _ in stub.seen] == [5], \
        ("a function-masked interrupt was NOT forwarded (stub saw %r). D-6: the CPM5 core queues it "
         "in its own PBA and delivers it on unmask, so filtering here loses it." % (stub.seen,))
    s = sts(dut)
    assert s["sent"] == 1, "sent = %d; the core acknowledged, so it must be counted" % s["sent"]
    assert s["masked"] == 1, "sts_irq_masked_seen did not record the masked delivery"
    assert s["dis"] == 0, "a masked interrupt must not be counted as a disabled drop"

@cocotb.test()
async def test_d3_fail_is_retransmitted_then_bounded(dut):
    stub = await setup(dut, seed=7)
    stub.fail_next = 1
    await request(dut, 1)
    stub.check()
    got = [v for v, _ in stub.seen]
    assert got == [1, 1], "expected exactly one retransmission of vector 1, saw %r" % got
    s = sts(dut)
    assert s["fail"] == 1 and s["sent"] == 1 and s["rty"] == 0, "counters after one retry: %r" % s

    stub.seen.clear()
    stub.fail_next = FAIL_RETRY_LIMIT + 5
    await request(dut, 2, timeout=2000)
    stub.check()
    attempts = len([v for v, _ in stub.seen if v == 2])
    assert attempts == FAIL_RETRY_LIMIT + 1, \
        ("vector 2 was presented %d times; D-3 allows the first attempt plus FAIL_RETRY_LIMIT=%d "
         "retries = %d. Unbounded retry would livelock mqnic's EQ arbiter."
         % (attempts, FAIL_RETRY_LIMIT, FAIL_RETRY_LIMIT + 1))
    s = sts(dut)
    assert s["rty"] == 1, "drop_retry = %d, expected 1 - the give-up must be VISIBLE" % s["rty"]
    stub.fail_next = 0
    await request(dut, 3)
    stub.check()

@cocotb.test()
async def test_d7_static_pins_never_move(dut):
    stub = await setup(dut, seed=8)
    bad = []

    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            await ReadOnly()
            try:
                vp = int(dut.cfg_msix_vec_pending.value)
                fn = int(dut.cfg_msix_function_number.value)
            except ValueError:
                continue
            if vp != 0:
                bad.append("vec_pending = 0b%02b (modes 01 PBA-query / 10 PBA-clear are unused)" % vp)
            if fn != 0:
                bad.append("function_number = %d (PF_COUNT=1, VF_COUNT=0)" % fn)

    cocotb.start_soon(monitor())
    for idx in range(min(4, MSIX_VECTOR_COUNT)):
        await request(dut, idx)
    stub.check()
    assert not bad, "D-7 violated on %d cycles: %s" % (len(bad), sorted(set(bad)))
    assert len(stub.seen) == min(4, MSIX_VECTOR_COUNT), \
        "expected %d presentations, saw %d" % (min(4, MSIX_VECTOR_COUNT), len(stub.seen))

@cocotb.test()
async def test_d9_reset_mid_request_is_clean(dut):
    stub = await setup(dut, seed=9, latency=20)
    dut.irq_index.value = 4
    dut.irq_valid.value = 1
    for _ in range(6):
        await RisingEdge(dut.clk)
    await ReadOnly()
    assert int(dut.sts_busy.value) == 1, "the mapper should be busy here"
    await RisingEdge(dut.clk)
    dut.rst.value = 1
    dut.irq_valid.value = 0
    spurious = 0
    for _ in range(8):
        await ReadOnly()
        if dut.irq_ready.value.binstr == "1":
            spurious += 1
        await RisingEdge(dut.clk)
    assert spurious == 0, ("irq_ready pulsed %d times during reset; mqnic's EQ arbiter would count "
                           "that as an accept (D-9)" % spurious)
    assert int(dut.cfg_msix_int_vector.value) == 0, "int_vector not cleared by reset"
    dut.rst.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)
    s = sts(dut)
    assert all(v == 0 for k, v in s.items()), "counters not cleared by reset: %r" % s
    assert int(dut.sts_busy.value) == 0, "still busy after reset"
    stub.outstanding = False
    await request(dut, 1)
    stub.check()
    assert sts(dut)["sent"] == 1, "the mapper did not work after reset"

@cocotb.test()
async def test_d8_counters_saturate(dut):
    stub = await setup(dut, seed=10)
    lim = (1 << STS_COUNT_WIDTH) - 1
    n = lim + 4
    if n > 600:
        cocotb.log.info("skipped: STS_COUNT_WIDTH=%d makes saturation too slow to be worth it; "
                        "run the sat_ job (STS_COUNT_WIDTH=4)" % STS_COUNT_WIDTH)
        return
    for i in range(n):
        await request(dut, i % MSIX_VECTOR_COUNT)
    stub.check()
    got = sts(dut)["sent"]
    assert got == lim, ("sent count %d after %d requests; expected saturation at %d. A wrapping "
                        "counter would read %d." % (got, n, lim, n & lim))

@cocotb.test()
async def test_random_burst_no_loss_no_reorder(dut):
    seed = int(os.environ.get("NIA_SEED", "1"))
    stub = await setup(dut, seed=seed, latency=1)
    expect = []
    for _ in range(40):
        idx = random.randrange(MSIX_VECTOR_COUNT)
        expect.append(idx)
        stub.latency = random.randrange(0, 6)
        for _ in range(random.randrange(0, 4)):
            await RisingEdge(dut.clk)
        await request(dut, idx)
    stub.check()
    got = [v for v, _ in stub.seen]
    assert got == expect, "burst mismatch\n  got    %r\n  expect %r" % (got, expect)
    assert sts(dut)["sent"] == min(len(expect), (1 << STS_COUNT_WIDTH) - 1)
    dut._log.info("soak: %d requests, seed %d, all delivered in order", len(expect), seed)
