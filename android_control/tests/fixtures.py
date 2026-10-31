"""Generate reference bytes using the already-tested desktop implementation."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pc_control"))
from protocol import preset_packets
p = {"adsr": {"attack_ms":30,"decay_ms":500,"sustain":.18,"release_ms":800}, "anchors":[]}
for a,(name,note) in enumerate(zip(("C2","C3","C4","C6"),(36,48,60,84))):
    p["anchors"].append({"name":name,"midi_note":note,"amplitudes":[((a*16+h)%11)/10 for h in range(16)],"decay_ms":[(a*16+h)*1100 for h in range(16)]})
Path(sys.argv[1]).write_bytes(b"".join(preset_packets(p)))
