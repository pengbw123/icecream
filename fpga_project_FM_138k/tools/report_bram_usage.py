"""Attribute inferred BSRAM cells by hierarchy in the Gowin synthesis netlist.

Counts synthesis cells, not post-PnR physical blocks. The PnR report remains
authoritative for device capacity; those totals can use a different mapping.
"""
import collections
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KINDS = {"SDPB", "SDPX9B", "pROM", "pROMX9", "DPB", "DPX9B"}


def report():
    path = ROOT / "impl/gwsynthesis/fm_138k_rgb_hdmi.vg"
    text = path.read_text(encoding="utf-8")
    modules = {m.group(1): m.group(0) for m in re.finditer(
        r"(?ms)^module\s+(\S+)\s*\(.*?^endmodule", text)}
    rows = []

    def walk(name, instance):
        local = collections.Counter()
        for kind, child in re.findall(r"^\s*(\S+)\s+(\S+)\s*\(", modules[name], re.M):
            if kind in KINDS:
                local[kind] += 1
            elif kind in modules:
                walk(kind, instance + "/" + child)
        if local:
            rows.append((sum(local.values()), instance, dict(local)))

    walk("top_138k_hdmi", "top")
    print("SYNTHESIS CELL COUNTS; NOT POST-PNR PHYSICAL BLOCK COUNTS")
    for count, instance, kinds in sorted(rows, reverse=True):
        print("{:3d}  {}  {}".format(count, instance, kinds))
    print("Total inferred cells:", sum(row[0] for row in rows))


if __name__ == "__main__":
    report()
