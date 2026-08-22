#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# File        : probe_cpm5_params.py
# Description : Prints CPM5 IP parameter names, defaults and legal values from
#               the installed IP database, so a CPM_CONFIG word is never
#               guessed: Vivado ignores a misspelled word without an error.
# Author      : Xiaohai Li <haixiaolee@gmail.com>
#
#
# Copyright (c) 2026 Xiaohai Li <haixiaolee@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause-Views
# ---------------------------------------------------------------------------
import os
import re
import sys

XML = os.environ.get("XML", "")
pat = re.compile(sys.argv[1] if len(sys.argv) > 1 else r"CPM_PCIE1_PF0_(BAR|MSIX)")

if not XML:
    sys.exit("set XML to the CPM5 component.xml of your install: "
             "<install>/data/ip/xilinx/cpm5_v1_0/component.xml")

try:
    text = open(XML, encoding="utf-8", errors="replace").read()
except OSError as e:
    sys.exit("FAIL: cannot read %s (%s)" % (XML, e))

P = re.compile(
    r"<spirit:parameter>\s*<spirit:name>([^<]+)</spirit:name>\s*"
    r"(?:<spirit:displayName>([^<]*)</spirit:displayName>\s*)?"
    r"<spirit:value\b([^>]*)>([^<]*)</spirit:value>",
    re.S)

C = re.compile(r"<spirit:choice>\s*<spirit:name>([^<]+)</spirit:name>(.*?)</spirit:choice>", re.S)
E = re.compile(r"<spirit:enumeration[^>]*>([^<]*)</spirit:enumeration>")

choices = {m.group(1): E.findall(m.group(2)) for m in C.finditer(text)}

hits = 0
for m in P.finditer(text):
    name, disp, attrs, default = m.group(1), (m.group(2) or ""), m.group(3), m.group(4)
    if not pat.search(name):
        continue
    hits += 1
    cref = re.search(r'spirit:choiceRef="([^"]+)"', attrs)
    legal = ""
    if cref:
        vals = choices.get(cref.group(1))
        legal = "legal={%s}" % ",".join(vals) if vals else "legal=<choice %s NOT FOUND>" % cref.group(1)
    print("%-52s = %-14s %-26s %s   # %s" % (
        name, default, ("[%s]" % cref.group(1)) if cref else "", legal, disp))

print("--- %d parameter(s) matched %s in %s" % (hits, pat.pattern, XML))
if hits == 0:
    print("MISSING %s  <-- the parameter does not exist in this IP" % pat.pattern)
