#!/bin/bash
# ---------------------------------------------------------------------------
# File        : build.sh
# Description : Builds a test driver from the reference driver in the mounted
#               pcie library, out of tree and with the five edits this endpoint
#               requires, so the reference tree stays unmodified. Every edit
#               checks the text it expects and stops the build if it is gone.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../../.." && pwd)"
SRC="${NIA_VERILOG_PCIE:-$APP/verilog-pcie}/example/VCU118/fpga/driver"
BUILD="${BUILD:-$HOME/nia_pcie_hw/example_driver}"

echo "=== reference : $SRC"
echo "=== scratch   : $BUILD"
[ -d "$SRC" ] || { echo "FAIL: reference driver not found"; exit 1; }
if [ -z "${PATCH_ONLY:-}" ]; then
  [ -d "/lib/modules/$(uname -r)/build" ] || { echo "FAIL: no kernel headers for $(uname -r)"; exit 1; }
fi

rm -rf "$BUILD"; mkdir -p "$BUILD"
cp -a "$SRC"/* "$BUILD"/
C="$BUILD/example_driver.c"

python3 - "$C" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '\t{PCI_DEVICE(0x1234, 0x0001)},\n'
new = '\t{PCI_DEVICE(0x10ee, 0x0001)},\n'
if s.count(old) != 1:
    sys.exit("FAIL ID table: expected exactly one {PCI_DEVICE(0x1234, 0x0001)} line, found "
             "%d - upstream changed, review before patching" % s.count(old))
open(p, 'w').write(s.replace(old, new))
PY
echo "ID table patched: binds 10ee:0001, the identifier this design's endpoint reports"

python3 - "$C" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''	dev_info(dev, "write to BAR2");
	iowrite32(0x11223344, edev->bar[2]);

	dev_info(dev, "read from BAR2");
	dev_info(dev, "%08x", ioread32(edev->bar[2]));
'''
new = '''	if (edev->bar[2]) {
		dev_info(dev, "write to BAR2");
		iowrite32(0x11223344, edev->bar[2]);

		dev_info(dev, "read from BAR2");
		dev_info(dev, "%08x", ioread32(edev->bar[2]));
	} else {
		dev_info(dev, "BAR2 absent in this build - skipping BAR2 read/write test");
	}
'''
if s.count(old) != 1:
    sys.exit("FAIL BAR2 guard: expected exactly one BAR2 test block, found %d - reference "
             "changed, review before patching" % s.count(old))
open(p, 'w').write(s.replace(old, new))
PY
echo "BAR2 guard applied: the BAR is only touched if the build actually has it"

python3 - "$C" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

anchor = 'MODULE_VERSION(DRIVER_VERSION);\n'
if s.count(anchor) != 1:
    sys.exit("FAIL bench gate: MODULE_VERSION anchor not unique - reference changed")
s = s.replace(anchor, anchor + '''
static int bench;
module_param(bench, int, 0444);
MODULE_PARM_DESC(bench, "run the extended benchmark/completion-buffer suite (default 0; needs an MSI-X table that does not alias the register block)");
''')

guard = '''	if (cycles == 0) {
		dev_warn(edev->dev, "%s: cycle counter read 0 - benchmark did not run; skipping Mbps calculation (would divide by zero)",
				__func__);
		return;
	}

'''
sites = [
    '\tdev_info(edev->dev, "read %lld blocks of %lld bytes',
    '\tdev_info(edev->dev, "wrote %lld blocks of %lld bytes',
    '\tdev_info(edev->dev, "read %lld x %lld B',
]
for site in sites:
    if s.count(site) != 1:
        sys.exit("FAIL divide guards: site not unique (%d): %s" % (s.count(site), site.strip()))
    s = s.replace(site, guard + site)

old_if = '\tif (!mismatch) {\n'
if s.count(old_if) != 1:
    sys.exit("FAIL bench gate: `if (!mismatch) {` not unique - reference changed")
s = s.replace(old_if, '''	if (!mismatch && !bench)
		dev_info(dev, "extended benchmark suite skipped (bench=0)");

	if (!mismatch && bench) {
''')

open(p, 'w').write(s)
PY
echo "bench gate applied: cycles==0 guarded in 3 sites; extended suite behind module param bench=0"

python3 - "$C" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()

helper = '''
#define NIA_REG_BLOCK_END 0x1200u

static int nia_msix_window_safe(struct pci_dev *pdev)
{
	struct device *dev = &pdev->dev;
	int cap;
	u16 flags;
	u32 tbl, pba;
	unsigned int nvec, tbl_bir, pba_bir, tbl_off, pba_off, tbl_len, pba_len;

	cap = pci_find_capability(pdev, PCI_CAP_ID_MSIX);
	if (!cap) {
		dev_warn(dev, "msix-window: no MSI-X capability found - cannot verify the window");
		return -ENODEV;
	}

	pci_read_config_word(pdev, cap + PCI_MSIX_FLAGS, &flags);
	pci_read_config_dword(pdev, cap + PCI_MSIX_TABLE, &tbl);
	pci_read_config_dword(pdev, cap + PCI_MSIX_PBA, &pba);

	nvec    = (flags & PCI_MSIX_FLAGS_QSIZE) + 1;
	tbl_bir = tbl & PCI_MSIX_TABLE_BIR;
	pba_bir = pba & PCI_MSIX_PBA_BIR;
	tbl_off = tbl & PCI_MSIX_TABLE_OFFSET;
	pba_off = pba & PCI_MSIX_PBA_OFFSET;
	tbl_len = nvec * 16;
	pba_len = DIV_ROUND_UP(nvec, 64) * 8;

	dev_info(dev, "msix-window: MSI-X %u vectors; table BAR%u+0x%06x..0x%06x; PBA BAR%u+0x%06x..0x%06x; register block ends 0x%06x",
			nvec, tbl_bir, tbl_off, tbl_off + tbl_len - 1,
			pba_bir, pba_off, pba_off + pba_len - 1, NIA_REG_BLOCK_END - 1);

	if (tbl_bir == 0 && tbl_off < NIA_REG_BLOCK_END) {
		dev_err(dev, "msix-window: MSI-X TABLE overlaps the BAR0 register block - writes there would corrupt interrupt vectors");
		return -EADDRINUSE;
	}
	if (pba_bir == 0 && pba_off < NIA_REG_BLOCK_END) {
		dev_err(dev, "msix-window: MSI-X PBA overlaps the BAR0 register block");
		return -EADDRINUSE;
	}

	dev_info(dev, "msix-window: MSI-X window is clear of the register block");
	return 0;
}

'''

anchor = 'static irqreturn_t edev_intr(int irq, void *data)\n'
if s.count(anchor) != 1:
    sys.exit("FAIL MSI-X window check: edev_intr anchor not unique - reference changed")
s = s.replace(anchor, helper + anchor)

old = '\tif (!mismatch && bench) {\n'
if s.count(old) != 1:
    sys.exit("FAIL MSI-X window check: the bench gate must be present exactly once - apply it first")
s = s.replace(old, '\tif (!mismatch && bench && nia_msix_window_safe(pdev) == 0) {\n')

open(p, 'w').write(s)
PY
echo "MSI-X window check applied: table/PBA against the register block, at probe time"

if [ -n "${PATCH_ONLY:-}" ]; then
  echo "=== PATCH_ONLY: skipping make. Patched hunks:"
  grep -n -E 'module_param|cycles == 0|!mismatch|PCI_DEVICE\(0x10ee|edev->bar\[2\]\)|nia_msix_window_safe' "$C"
  echo "PATCH_ONLY: all five edits applied to $C"
  exit 0
fi
echo "=== make ==="
( cd "$BUILD" && make ) 2>&1 | tail -6
[ -f "$BUILD/example.ko" ] || { echo "FAIL: example.ko not produced"; exit 1; }
echo "PASS: $BUILD/example.ko ($(stat -c %s "$BUILD/example.ko") B)"

echo -n "=== reference tree modified files (MUST be 0): "
git -C "${NIA_VERILOG_PCIE:-$APP/verilog-pcie}" status --porcelain 2>/dev/null | wc -l
