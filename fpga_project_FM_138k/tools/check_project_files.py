"""Verify that every module instantiated by the project's RTL files is listed
in fpga_project.gprj.

The Gowin IDE builds its hierarchy view from the project file list.  A module
that is instantiated but whose file is missing from the list makes the
hierarchy fail to expand ("black box"/unknown module).  Legacy modules that no
listed file instantiates are allowed to stay out of the project.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
gprj = (ROOT / 'fpga_project.gprj').read_text(encoding='utf-8')
listed = set(re.findall(r'<File path="([^"]+\.v)"', gprj))

# module name -> definition file, over every Verilog file in the tree
defines = {}
for v in (ROOT / 'src').rglob('*.v'):
    rel = v.relative_to(ROOT).as_posix()
    text = v.read_text(encoding='utf-8', errors='ignore')
    for name in re.findall(r'^\s*module\s+(\w+)', text, re.M):
        defines[name] = rel

missing = {}
for rel in sorted(listed):
    path = ROOT / rel
    if not path.exists():
        missing.setdefault(rel, set()).add('<file missing>')
        continue
    text = path.read_text(encoding='utf-8', errors='ignore')
    text = re.sub(r'//[^\n]*', '', text)
    for mod in re.findall(r'^\s*([A-Za-z_]\w*)\s*(?:#\s*\([^;]*?\))?\s+[A-Za-z_]\w*\s*\(', text, re.M):
        if mod in ('module', 'input', 'output', 'inout', 'wire', 'reg', 'always',
                   'assign', 'if', 'else', 'case', 'begin', 'for', 'initial',
                   'localparam', 'parameter', 'generate', 'end', 'function'):
            continue
        if mod not in defines:
            continue
        if defines[mod] not in listed:
            missing.setdefault(defines[mod], set()).add(mod)

if missing:
    print('MISSING from fpga_project.gprj (instantiated by listed RTL):')
    for rel, mods in missing.items():
        print('  ', rel, '->', ', '.join(sorted(mods)))
    sys.exit(1)
print('project file list OK:', len(listed), 'files listed, all instantiated modules present')
