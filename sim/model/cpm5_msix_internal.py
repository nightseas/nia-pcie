# ---------------------------------------------------------------------------
# File        : cpm5_msix_internal.py
# Description : The MSI-X Internal variant of the CPM5 device model. A subclass
#               that gives the function its dedicated MSI-X bar and intercepts
#               the table and PBA window; other accesses reach the base model.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import struct

import cocotb
from cocotb.triggers import RisingEdge

from cocotbext.pcie.core.tlp import Tlp, TlpType

from cpm5_pcie_device import Cpm5PcieDevice

MSIX_TABLE_BIR = 4
MSIX_TABLE_OFFSET = 0x0000
MSIX_PBA_BIR = 4
MSIX_PBA_OFFSET = 0x8000
MSIX_BAR_SIZE = 64 * 1024

def _init_signal(sig, width=None, initval=None):
    if sig is None:
        return None
    if width is not None and len(sig) != width:
        raise AssertionError("signal %r width %d, expected %d" % (sig._name, len(sig), width))
    if initval is not None:
        sig.setimmediatevalue(initval)
    return sig

class Cpm5MsixInternalDevice(Cpm5PcieDevice):

    def __init__(self, *args, **kwargs):
        self._p_int_vector = kwargs.pop("cfg_msix_int_vector", None)
        self._p_mint_vector = kwargs.pop("cfg_msix_mint_vector", None)
        self._p_function_number = kwargs.pop("cfg_msix_function_number", None)
        self._p_vec_pending = kwargs.pop("cfg_msix_vec_pending", None)
        self._p_sent = kwargs.pop("cfg_msix_sent", None)
        self._p_fail = kwargs.pop("cfg_msix_fail", None)
        self._p_vec_pending_status = kwargs.pop("cfg_msix_vec_pending_status", None)

        self.msix_bir_forced = (kwargs.get("pf0_msix_table_bir"), kwargs.get("pf0_msix_table_offset"))
        kwargs["pf0_msix_table_bir"] = MSIX_TABLE_BIR
        kwargs["pf0_msix_table_offset"] = MSIX_TABLE_OFFSET
        kwargs["pf0_msix_pba_bir"] = MSIX_PBA_BIR
        kwargs["pf0_msix_pba_offset"] = MSIX_PBA_OFFSET

        super().__init__(*args, **kwargs)

        self.msix_count = self.pf0_msix_table_size + 1
        self._tbl = bytearray(16 * self.msix_count)
        self._pba = bytearray(8 * ((self.msix_count + 63) // 64))

        self.observed_vectors = []
        self.delivered_vectors = []
        self.deferred_vectors = []
        self.failed_vectors = []
        self.msix_bar_reads = 0
        self.msix_bar_writes = 0
        self.force_fail_once = False

        self._pba_pending = set()

        _init_signal(self._p_sent, 1, 0)
        _init_signal(self._p_fail, 1, 0)
        _init_signal(self._p_vec_pending_status, 1, 0)

        cocotb.start_soon(self._run_cpm5_msix_internal_logic())

    def attach_cpm5_msix_pins(self, dut):
        self._p_int_vector = dut.cfg_msix_int_vector
        self._p_mint_vector = dut.cfg_msix_mint_vector
        self._p_function_number = dut.cfg_msix_function_number
        self._p_vec_pending = dut.cfg_msix_vec_pending
        self._p_sent = dut.cfg_msix_sent
        self._p_fail = dut.cfg_msix_fail
        self._p_vec_pending_status = dut.cfg_msix_vec_pending_status
        self._p_sent.setimmediatevalue(0)
        self._p_fail.setimmediatevalue(0)
        self._p_vec_pending_status.setimmediatevalue(0)
        self.log.info("CPM5 MSI-X-Internal sideband attached: int_vector(1) mint_vector(%d) "
                      "function_number(%d) vec_pending(%d); table size %d in BAR%d",
                      len(self._p_mint_vector), len(self._p_function_number),
                      len(self._p_vec_pending), self.msix_count, MSIX_TABLE_BIR)

    def configure_msix_bar(self):
        self.functions[0].configure_bar(MSIX_TABLE_BIR, MSIX_BAR_SIZE, ext=True, prefetch=True)

    def _msix_window_offset(self, addr):
        f = self.functions[0]
        bar = f.match_bar(addr)
        if not bar:
            return None
        if bar[0] != MSIX_TABLE_BIR:
            return None
        return bar[1]

    def _msix_region_read(self, off, nbytes):
        data = bytearray(nbytes)
        for i in range(nbytes):
            o = off + i
            if MSIX_TABLE_OFFSET <= o < MSIX_TABLE_OFFSET + len(self._tbl):
                data[i] = self._tbl[o - MSIX_TABLE_OFFSET]
            elif MSIX_PBA_OFFSET <= o < MSIX_PBA_OFFSET + len(self._pba):
                data[i] = self._pba[o - MSIX_PBA_OFFSET]
        return bytes(data)

    def _msix_region_write(self, off, data, first_be, last_be):
        n = len(data)
        for i in range(n):
            dw = i // 4
            lane = i % 4
            if n <= 4:
                be = first_be
            elif dw == 0:
                be = first_be
            elif dw == n // 4 - 1:
                be = last_be
            else:
                be = 0xF
            if not (be >> lane) & 1:
                continue
            o = off + i
            if MSIX_TABLE_OFFSET <= o < MSIX_TABLE_OFFSET + len(self._tbl):
                self._tbl[o - MSIX_TABLE_OFFSET] = data[i]
            elif MSIX_PBA_OFFSET <= o < MSIX_PBA_OFFSET + len(self._pba):
                pass

    async def upstream_recv(self, tlp):
        if tlp.fmt_type in {TlpType.MEM_READ, TlpType.MEM_READ_64,
                            TlpType.MEM_WRITE, TlpType.MEM_WRITE_64}:
            off = self._msix_window_offset(tlp.address)
            if off is not None:
                tlp.release_fc()
                if tlp.fmt_type in {TlpType.MEM_WRITE, TlpType.MEM_WRITE_64}:
                    self.msix_bar_writes += 1
                    self._msix_region_write(off, tlp.get_data(), tlp.first_be, tlp.last_be)
                    lvl = self.log.info if self.msix_bar_writes <= 8 else self.log.debug
                    lvl("CPM5 MSI-X: CLAIMED table/PBA WRITE #%d off=0x%04x len=%d "
                        "(the CIPS never forwards these to the PL, measured on hardware)",
                        self.msix_bar_writes, off, tlp.length * 4)
                else:
                    self.msix_bar_reads += 1
                    data = self._msix_region_read(off + tlp.get_first_be_offset(),
                                                 tlp.get_be_byte_count())
                    cpl = Tlp.create_completion_data_for_tlp(tlp, self.functions[0].pcie_id)
                    cpl.byte_count = tlp.get_be_byte_count()
                    cpl.lower_address = (tlp.address + tlp.get_first_be_offset()) & 0x7F
                    cpl.set_data(data.ljust(tlp.length * 4, b"\x00")[:tlp.length * 4])
                    self.log.debug("CPM5 MSI-X: claimed table/PBA READ off=0x%04x len=%d",
                                   off, tlp.length * 4)
                    await self.upstream_send(cpl)
                return
        return await super().upstream_recv(tlp)

    def msix_entry(self, vec):
        a_lo, a_hi, data, ctrl = struct.unpack_from("<LLLL", self._tbl, vec * 16)
        return (a_hi << 32) | a_lo, data, bool(ctrl & 1)

    def _pba_get(self, vec):
        return bool(self._pba[vec // 8] >> (vec % 8) & 1)

    def _pba_set(self, vec, val):
        if val:
            self._pba[vec // 8] |= 1 << (vec % 8)
            self._pba_pending.add(vec)
        else:
            self._pba[vec // 8] &= ~(1 << (vec % 8)) & 0xFF
            self._pba_pending.discard(vec)

    async def _run_cpm5_msix_internal_logic(self):
        clock_edge = RisingEdge(self.user_clk)
        last_int = 0

        while True:
            await clock_edge

            if self._p_sent is not None:
                self._p_sent.value = 0
            if self._p_fail is not None:
                self._p_fail.value = 0

            f = self.functions[0]
            fn_masked = bool(f.msix_cap.msix_function_mask)
            enabled = bool(f.msix_cap.msix_enable)

            cur_int = 0
            if self._p_int_vector is not None:
                try:
                    cur_int = int(self._p_int_vector.value)
                except ValueError:
                    cur_int = 0

            if cur_int and not last_int:
                vec = 0
                if self._p_mint_vector is not None:
                    try:
                        vec = int(self._p_mint_vector.value)
                    except ValueError:
                        vec = 0
                pend_mode = 0
                if self._p_vec_pending is not None:
                    try:
                        pend_mode = int(self._p_vec_pending.value)
                    except ValueError:
                        pend_mode = 0

                if pend_mode != 0:
                    raise AssertionError(
                        "cfg_msix_vec_pending = 0b%02b on an interrupt request; rule D-7 requires "
                        "0b00 (normal generation). PBA query/clear modes are not used." % pend_mode)

                if self.force_fail_once or vec >= self.msix_count:
                    why = "test hook" if self.force_fail_once else \
                          "vector %d >= advertised count %d" % (vec, self.msix_count)
                    self.force_fail_once = False
                    self.failed_vectors.append(vec)
                    self.log.info("CPM5 MSI-X: FAIL vector %d (%s)", vec, why)
                    if self._p_fail is not None:
                        self._p_fail.value = 1
                else:
                    self.observed_vectors.append(vec)
                    addr, data, vec_masked = self.msix_entry(vec)
                    if enabled and not fn_masked and not vec_masked:
                        self.log.info("CPM5 MSI-X: issue vector %d -> addr 0x%016x data 0x%08x",
                                      vec, addr, data)
                        await f.mem_write(addr, struct.pack("<L", data))
                        self.delivered_vectors.append(vec)
                        self._pba_set(vec, False)
                    else:
                        self._pba_set(vec, True)
                        self.deferred_vectors.append(vec)
                        self.log.info("CPM5 MSI-X: vector %d masked (fn=%d vec=%d enable=%d) -> PBA",
                                      vec, fn_masked, vec_masked, enabled)
                    if self._p_vec_pending_status is not None:
                        self._p_vec_pending_status.value = 1 if self._pba_get(vec) else 0
                    if self._p_sent is not None:
                        self._p_sent.value = 1

            last_int = cur_int

            if self._pba_pending and enabled and not fn_masked:
                for vec in sorted(self._pba_pending):
                    addr, data, vec_masked = self.msix_entry(vec)
                    if vec_masked:
                        continue
                    self.log.info("CPM5 MSI-X: PBA drain vector %d", vec)
                    self._pba_set(vec, False)
                    await f.mem_write(addr, struct.pack("<L", data))
                    self.delivered_vectors.append(vec)
                    break
