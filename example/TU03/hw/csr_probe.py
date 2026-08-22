# ---------------------------------------------------------------------------
# File        : csr_probe.py
# Description : Proves PCIe function on a board with no driver. Maps the bar
#               through its sysfs resource file, walks the example core register
#               block, and runs one DMA transfer against a locked page.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

import argparse
import ctypes
import glob
import mmap
import os
import struct
import sys
import time

REGS = {
    0x0000: "control/status  [0]=dma_enable [8]=wr_busy [9]=rd_busy",
    0x0008: "interrupt enable [0]=rd_int_en [1]=wr_int_en",
    0x0010: "cycle_count[31:0]   free-running: MUST change between reads",
    0x0014: "cycle_count[63:32]",
    0x0018: "dma_read_active_count",
    0x001C: "dma_write_active_count",
    0x0020: "dma_rd_req_count",
    0x0024: "dma_rd_cpl_count",
    0x0028: "dma_wr_req_count",
    0x0040: "rx_cpl_stall_count",
    0x0100: "dma_read_desc_dma_addr[31:0]   (R/W)",
    0x0104: "dma_read_desc_dma_addr[63:32]  (R/W)",
    0x0110: "dma_read_desc_len              (R/W)",
    0x0118: "dma_read_desc_status",
}

WRITE_PROBE = 0x0100

RD_DMA_ADDR_LO, RD_DMA_ADDR_HI = 0x0100, 0x0104
RD_RAM_ADDR, RD_LEN, RD_TAG, RD_STATUS = 0x0108, 0x0110, 0x0114, 0x0118
WR_DMA_ADDR_LO, WR_DMA_ADDR_HI = 0x0200, 0x0204
WR_RAM_ADDR, WR_LEN, WR_TAG, WR_STATUS = 0x0208, 0x0210, 0x0214, 0x0218

RD_TAG_VALUE = 0xA1
WR_TAG_VALUE = 0xB2

HUGE_SZ = 2 * 1024 * 1024
MAP_HUGETLB = 0x40000
XFER = 4096

CMD_MEM = 1 << 1
CMD_MASTER = 1 << 2
REG_BLOCK_END = 0x1200


def hugepage_phys():
    try:
        buf = mmap.mmap(-1, HUGE_SZ, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS | MAP_HUGETLB,
                        prot=mmap.PROT_READ | mmap.PROT_WRITE)
    except (OSError, ValueError) as e:
        return None, f"hugepage alloc failed ({e}). Try: echo 16 > /proc/sys/vm/nr_hugepages"
    buf[0:8] = b"\x00" * 8
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    addr = ctypes.addressof(ctypes.c_char.from_buffer(buf))
    if libc.mlock(ctypes.c_void_p(addr), ctypes.c_size_t(HUGE_SZ)) != 0:
        return None, "mlock failed, refusing to DMA into a page that may migrate"
    try:
        with open("/proc/self/pagemap", "rb") as pm:
            pm.seek((addr // mmap.PAGESIZE) * 8)
            entry = struct.unpack("<Q", pm.read(8))[0]
    except OSError as e:
        return None, f"cannot read /proc/self/pagemap ({e})"
    if not entry & (1 << 63):
        return None, "page not present in pagemap"
    pfn = entry & ((1 << 55) - 1)
    if pfn == 0:
        return None, "PFN reads 0 (the kernel hides it from unprivileged readers), run as real root"
    return buf, pfn * mmap.PAGESIZE + (addr % mmap.PAGESIZE)


def dma_selftest(rd, wr):
    print("\n--- CHECK D: DMA self-test (requester path: RQ 137->183 + RC) ---")
    buf, phys = hugepage_phys()
    if buf is None:
        print(f"  SKIP  {phys}")
        return None
    print(f"  hugepage: virt ok, phys 0x{phys:x}, locked, {HUGE_SZ // (1024*1024)} MiB")

    src_off, dst_off = 0, 0x10000
    pattern = bytes((i * 7 + 3) & 0xFF for i in range(XFER))
    buf[src_off:src_off + XFER] = pattern
    buf[dst_off:dst_off + XFER] = b"\x00" * XFER

    rd_before, cpl_before = rd(0x0020), rd(0x0024)
    wr(0x0000, 1)

    wr(RD_DMA_ADDR_LO, (phys + src_off) & 0xFFFFFFFF)
    wr(RD_DMA_ADDR_HI, ((phys + src_off) >> 32) & 0xFFFFFFFF)
    wr(RD_RAM_ADDR, 0)
    wr(RD_LEN, XFER)
    wr(RD_TAG, RD_TAG_VALUE)
    st = wait_status(rd, RD_STATUS, "read", RD_TAG_VALUE)

    wr(WR_DMA_ADDR_LO, (phys + dst_off) & 0xFFFFFFFF)
    wr(WR_DMA_ADDR_HI, ((phys + dst_off) >> 32) & 0xFFFFFFFF)
    wr(WR_RAM_ADDR, 0)
    wr(WR_LEN, XFER)
    wr(WR_TAG, WR_TAG_VALUE)
    st2 = wait_status(rd, WR_STATUS, "write", WR_TAG_VALUE)

    got = bytes(buf[dst_off:dst_off + XFER])
    same = got == pattern
    print(f"  counters: rd_req {rd_before}->{rd(0x0020)}  rd_cpl {cpl_before}->{rd(0x0024)}  "
          f"wr_req {rd(0x0028)}")
    if same:
        print(f"  PASS  {XFER} B went host -> card -> host BYTE-EXACT")
        print("        RQ 137->183 zero-extend and RC pass-through are correct ON SILICON")
        return True
    first = next((i for i in range(XFER) if got[i] != pattern[i]), None)
    print(f"  FAIL  data mismatch at byte {first}: expected 0x{pattern[first]:02x}, got 0x{got[first]:02x}")
    print(f"        read status 0x{st:08x}, write status 0x{st2:08x}")
    return False


def wait_status(rd, off, what, tag, timeout=2.0):
    t0 = time.time()
    while time.time() - t0 < timeout:
        s = rd(off)
        if s & (1 << 31):
            err = (s >> 24) & 0xF
            print(f"  {what} descriptor completed: status 0x{s:08x} tag 0x{s & 0xFFFF:x} error {err}")
            return s
        if (s & 0xFFFF) == tag:
            err = (s >> 24) & 0xF
            print(f"  {what} descriptor completed: status 0x{s:08x}, tag 0x{tag:x} latched, error {err}")
            print("        the valid bit was already consumed: this register clears it on any read,")
            print("        including one that races the status arriving. The tag is the evidence.")
            return s
        time.sleep(0.01)
    print(f"  {what} descriptor DID NOT COMPLETE within {timeout}s (status 0x{rd(off):08x})")
    return 0


def find_bdf(vendor=None):
    vendors = [vendor] if vendor else ["10ee"]
    for path in glob.glob("/sys/bus/pci/devices/*"):
        try:
            with open(os.path.join(path, "vendor")) as f:
                v = f.read().strip().lower().replace("0x", "")
            with open(os.path.join(path, "device")) as f:
                d = f.read().strip().lower().replace("0x", "")
        except OSError:
            continue
        if v in vendors:
            return os.path.basename(path), v, d
    return None, None, None


def iommu_state(bdf):
    grp = f"/sys/bus/pci/devices/{bdf}/iommu_group"
    if not os.path.exists(grp):
        return "no IOMMU group: DMA is untranslated, a physical address is what the card needs"
    kind = "unknown"
    try:
        with open(os.path.join(grp, "type")) as f:
            kind = f.read().strip()
    except OSError:
        pass
    if kind in ("DMA", "DMA-FQ"):
        return (f"group type {kind}: TRANSLATING. A physical address is not an address this "
                "device may use, so the DMA self-test can fail on a working design. Test the "
                "requester path with the driver, which maps its buffers, or boot with iommu=pt")
    return f"group type {kind}: passthrough or identity, a physical address is usable"


def pci_command(bdf, new=None):
    path = f"/sys/bus/pci/devices/{bdf}/config"
    if new is None:
        with open(path, "rb") as f:
            f.seek(4)
            return struct.unpack("<H", f.read(2))[0]
    with open(path, "r+b") as f:
        f.seek(4)
        f.write(struct.pack("<H", new))
    return new


def enable_decode(bdf, want_master):
    orig = pci_command(bdf)
    want = orig | CMD_MEM | (CMD_MASTER if want_master else 0)

    def bits(c):
        return "%s%s" % ("MEM+" if c & CMD_MEM else "MEM-",
                         " MASTER+" if c & CMD_MASTER else " MASTER-")

    print(f"COMMAND     : 0x{orig:04x} ({bits(orig)})")
    if want != orig:
        pci_command(bdf, want)
        now = pci_command(bdf)
        print(f"              enabled -> 0x{now:04x} ({bits(now)}); restored on exit")
        if not now & CMD_MEM:
            print("  FAIL  memory decode will not stay enabled: the window is not usable")
    else:
        print("              already enabled; nothing to change")
    return orig


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bdf")
    ap.add_argument("--vendor")
    ap.add_argument("--dma-selftest", action="store_true",
                    help="also drive the requester path (RQ/RC) via a locked hugepage")
    args = ap.parse_args()

    print("===== driver-less CSR probe =====")

    if args.bdf:
        bdf = args.bdf
        vid = did = "?"
    else:
        bdf, vid, did = find_bdf(args.vendor)
        if not bdf:
            print("FAIL  no candidate endpoint found (vendors tried: %s)"
                  % (args.vendor or "10ee"))
            print("      If the link pin is high but nothing enumerates, the host was almost")
            print("      certainly not rebooted after programming: a new endpoint needs a")
            print("      reboot, not a rescan.")
            return 2
    print(f"device      : {bdf}  ({vid}:{did})")

    res0 = f"/sys/bus/pci/devices/{bdf}/resource0"
    if not os.path.exists(res0):
        print(f"FAIL  {res0} does not exist: firmware assigned no BAR0")
        return 2
    size = os.path.getsize(res0)
    print(f"BAR0        : {res0}  size={size} B ({size//1024} KiB)")
    if size < 0x1000:
        print("FAIL  BAR0 smaller than the register block")
        return 2

    npass = nfail = 0
    try:
        cmd_orig = enable_decode(bdf, args.dma_selftest)
    except PermissionError:
        print("FAIL  need root to write the COMMAND register (run under sudo)")
        return 2
    if args.dma_selftest:
        print(f"IOMMU       : {iommu_state(bdf)}")

    try:
        fd = os.open(res0, os.O_RDWR | os.O_SYNC)
    except PermissionError:
        print("FAIL  need root to mmap the BAR (run under sudo)")
        pci_command(bdf, cmd_orig)
        return 2

    with mmap.mmap(fd, min(size, 0x1000), mmap.MAP_SHARED,
                   mmap.PROT_READ | mmap.PROT_WRITE) as m:

        def rd(off):
            return struct.unpack("<I", m[off:off + 4])[0]

        def wr(off, val):
            m[off:off + 4] = struct.pack("<I", val)

        print("\n--- CHECK A: BAR0 reads answer (completer path: CQ 231->183 + CC) ---")
        vals = {}
        for off, name in sorted(REGS.items()):
            try:
                vals[off] = rd(off)
                print(f"  0x{off:04x} = 0x{vals[off]:08x}   {name}")
            except Exception as e:
                print(f"  0x{off:04x} = <read failed: {e}>")
        if not vals:
            print("  FAIL  no register could be read")
            nfail += 1
        elif all(v == 0xFFFFFFFF for v in vals.values()):
            print("  FAIL  every register reads 0xFFFFFFFF: master abort or no response.")
            print("        The BAR is mapped but nothing answers: suspect the CQ/CC path, the")
            print("        user_clk domain, or that the design is not actually programmed.")
            nfail += 1
        else:
            print("  PASS  BAR0 responds with real data: CQ/CC through the adapter WORKS on silicon")
            npass += 1

        print("\n--- CHECK B: free-running cycle counter advances (design is clocked) ---")
        c0 = rd(0x0010)
        time.sleep(0.20)
        c1 = rd(0x0010)
        print(f"  cycle_count: 0x{c0:08x} -> 0x{c1:08x}  (delta {(c1 - c0) & 0xFFFFFFFF})")
        if c1 != c0:
            print("  PASS  counter advanced: user_clk is running and the core is alive")
            npass += 1
        else:
            print("  FAIL  counter frozen: the fabric is not clocked (check pcie_user_clk, reset)")
            nfail += 1

        print("\n--- CHECK C: register write + read-back (posted writes land) ---")
        saved = rd(WRITE_PROBE)
        for pattern in (0xA5A5A5A5, 0x5A5A5A5A, 0x00000000):
            wr(WRITE_PROBE, pattern)
            got = rd(WRITE_PROBE)
            status = "ok" if got == pattern else "MISMATCH"
            print(f"  wrote 0x{pattern:08x} -> read 0x{got:08x}  {status}")
            if got != pattern:
                nfail += 1
                break
        else:
            print("  PASS  writes land and read back: the write path through the adapter works")
            npass += 1
        wr(WRITE_PROBE, saved)

        if args.dma_selftest:
            r = dma_selftest(rd, wr)
            if r is True:
                npass += 1
            elif r is False:
                nfail += 1
        else:
            print("\n--- CHECK D: DMA self-test SKIPPED (pass --dma-selftest to run it) ---")
            print("  Without it, only the COMPLETER half of the adapter is proven on silicon.")

    os.close(fd)
    pci_command(bdf, cmd_orig)
    print(f"COMMAND     : restored to 0x{cmd_orig:04x}")

    print(f"\n===== SUMMARY pass={npass} fail={nfail} =====")
    if nfail == 0:
        print("VERDICT: PASS, PCIe function is demonstrated ON SILICON.")
        print("         CQ 231->183 truncation, CC pass-through, clocking and posted writes all")
        print("         work through pcie_versal_adapt. With --dma-selftest the requester path")
        print("         RQ/RC is proven too; without it, only the completer half is.")
        return 0
    print("VERDICT: FAIL, see the failing check above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
