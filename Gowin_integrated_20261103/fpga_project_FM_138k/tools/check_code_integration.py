"""Code-only integration checks. Never invokes synthesis or place/route."""
from pathlib import Path
import argparse
import concurrent.futures
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--iverilog-dir', default='')
    ap.add_argument('--gowin-simlib', required=True, help='gw5a/prim_sim.v')
    ap.add_argument('--extended', action='store_true', help='Real CPU/FM phone and CH376 mapped-key tests')
    ap.add_argument('--only', default='', help='Run one named check, for targeted reruns')
    ap.add_argument('--app-trace', default='', help='Optional external Android practice UART capture')
    args = ap.parse_args()
    iv = str(Path(args.iverilog_dir) / 'iverilog.exe') if args.iverilog_dir else shutil.which('iverilog')
    vvp = str(Path(args.iverilog_dir) / 'vvp.exe') if args.iverilog_dir else shutil.which('vvp')
    if not iv or not vvp:
        raise SystemExit('Icarus Verilog tools are required')
    out = ROOT / 'verification/code_integration'
    out.mkdir(parents=True, exist_ok=True)
    files = ET.parse(ROOT / 'fpga_project.gprj').findall('.//File')
    missing = [f.get('path') for f in files if not (ROOT / f.get('path')).exists()]
    assert not missing, missing
    rtl = [f.get('path') for f in files if f.get('path').endswith('.v') and '/dvi_tx/' not in f.get('path')]
    # The protected DVI IP is unused in the current camera TMDS path. Icarus
    # cannot decrypt it; the actual camera serializer uses the vendor primitives.
    for cst in ['src/acg720_rgb.cst', 'src/acg720_rgb_hdmi.cst']:
        pins = re.findall(r'IO_LOC\s+"([^"]+)"\s+([^;]+);', (ROOT / cst).read_text())
        locations = {}
        for port, pin in pins:
            assert pin not in locations, (cst, pin, port, locations.get(pin))
            locations[pin] = port
    low = (ROOT / 'src/ui_firmware/firmware.hex').read_text().splitlines()
    high = (ROOT / 'src/ui_firmware/firmware_high.hex').read_text().splitlines()
    assert len(low) == 24576 and len(high) == 4096
    assert low[16384:20480] == high and all(int(w, 16) == 0 for w in low[20480:])
    tasks = [
        ('tb_key_router', 'sim/incoming/tb_key_router.sv', 'KEY_ROUTER_OK'),
        ('tb_key_plan_fixed', 'sim/incoming/tb_key_plan_fixed.sv', 'KEY_PLAN_FIXED_OK'),
        ('tb_key_plan_full', 'sim/incoming/tb_key_plan_full.sv', 'KEY_PLAN_FULL_OK'),
        ('tb_key_plan_capability', 'sim/incoming/tb_key_plan_capability.sv', 'KEY_PLAN_CAPABILITY_OK'),
        ('tb_uploaded_practice', 'sim/incoming/tb_uploaded_practice.sv', 'UPLOADED_PRACTICE_OK'),
        ('tb_phone_reply_collision', 'sim/incoming/tb_phone_reply_collision.sv', 'PHONE_REPLY_COLLISION_OK'),
        ('tb_calibration_transaction', 'sim/incoming/tb_calibration_transaction.sv', 'CALIBRATION_TRANSACTION_OK'),
        ('tb_calibration_banner', 'sim/incoming/tb_calibration_banner.sv', 'CALIBRATION_BANNER_OK'),
        ('tb_calibration_sync', 'sim/incoming/tb_calibration_sync.sv', 'CALIBRATION_SYNC_OK'),
        ('tb_gesture_timbre', 'sim/tb_gesture_timbre.sv', 'PASS'),
        ('tb_integrated_key_identity', 'sim/tb_integrated_key_identity.sv', 'INTEGRATED_KEY_IDENTITY_OK'),
        ('tb_scope_touch_latency', 'sim/tb_scope_touch_latency.sv', 'PASS scope_touch_latency'),
        ('tb_integrated_mode_guard', 'sim/tb_integrated_mode_guard.sv', 'INTEGRATED_MODE_GUARD_OK'),
    ]
    if args.app_trace:
        tasks.append(('tb_app_practice_trace', 'sim/incoming/tb_app_practice_trace.sv', 'APP_138K_PRACTICE_TRACE_OK'))
    if args.extended:
        tasks += [
            ('tb_integrated_phone_smoke', 'sim/tb_integrated_phone_smoke.sv', 'INTEGRATED_PHONE_SMOKE_OK'),
            ('tb_integrated_key_plan_top', 'sim/tb_integrated_key_plan_top.sv', 'KEY_PLAN_TOP_OK'),
        ]

    def run(task):
        top, bench, marker = task
        executable = out / (top + '.vvp')
        text = (ROOT / bench).read_text() if bench else ''
        # Vendor simulation global reset must be an instance named GSR.
        if top.startswith('board_'):
            actual = top[len('board_'):]
            text = 'module ' + top + '; ' + actual + " dut(); GSR GSR(1'b1); endmodule\n"
        elif 'top_138k dut' in text:
            text = re.sub(r'(module\s+' + re.escape(top) + r'\s*;)', r"\1\n GSR GSR(1'b1);", text, count=1)
        if top == 'tb_calibration_transaction':
            text = text.replace('.*);', ".external_busy(1'b0),.key_plan_ready(1'b0),.keyboard_disconnected(1'b0),"
                                '.key_plan_active(),.key_plan_first(),.key_plan_valid(),.key_plan_notes(),.*);')
        if top == 'tb_app_practice_trace':
            text = text.replace("int melody[0:5]='{60,60,67,67,69,69};",
                                'int melody[0:5]; initial begin melody[0]=60;melody[1]=60;'
                                'melody[2]=67;melody[3]=67;melody[4]=69;melody[5]=69;end')
        fixture = out / (top + '.sv')
        fixture.write_text(text)
        # The current model has Icarus-compatible task exits/queue append;
        # the imported original is also preserved under sim/incoming.
        extra = ['sim/ch376_usb_model.sv'] if top == 'tb_integrated_key_plan_top' else []
        result = subprocess.run([iv, '-g2012', '-Wall', '-s', top, '-o', str(executable),
                                 str(fixture), args.gowin_simlib, *extra, *rtl],
                                cwd=ROOT, capture_output=True, text=True, errors='replace', timeout=180)
        (out / (top + '_compile.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            return {'name': top, 'pass': False, 'stage': 'elaboration'}
        if marker is None:
            return {'name': top, 'pass': True, 'stage': 'elaboration'}
        try:
            with (out / (top + '.log')).open('w') as log:
                plusargs = ['+PACKETS=' + str(Path(args.app_trace).resolve())] if top == 'tb_app_practice_trace' else []
                result = subprocess.run([vvp, str(executable), *plusargs], cwd=ROOT, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=1200 if args.extended else 180)
            log = (out / (top + '.log')).read_text()
            return {'name': top, 'pass': result.returncode == 0 and marker in log, 'stage': 'simulation'}
        except subprocess.TimeoutExpired:
            return {'name': top, 'pass': False, 'stage': 'timeout'}

    tasks += [('board_top_138k_hdmi', '', None), ('board_top_138k', '', None)]
    if args.only:
        tasks = [t for t in tasks if t[0] == args.only]
        assert tasks, 'Unknown check: ' + args.only
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(run, tasks):
            results.append(result)
            print(json.dumps(result), flush=True)
    report = {'synthesis_run': False, 'place_route_run': False, 'rtl_files': len(rtl), 'results': results}
    (out / (('result_' + args.only) if args.only else 'result') ).with_suffix('.json').write_text(json.dumps(report, indent=2))
    return 0 if all(x['pass'] for x in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
