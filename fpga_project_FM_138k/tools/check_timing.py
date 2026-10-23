"""Fail a build whose Gowin timing report misses any constrained clock.

Gowin can return success and generate a .fs even when setup timing fails.
Use after gw_sh and before treating that bitstream as a release candidate.
"""
import argparse
import html
import re
from pathlib import Path


def check(base):
    root = Path(__file__).resolve().parents[1]
    report = root / 'impl' / 'pnr' / (base + '_tr_content.html')
    text = html.unescape(re.sub(r'<[^>]+>', ' ', report.read_text(encoding='utf-8')))
    text = re.sub(r'\s+', ' ', text)
    frequency = re.search(r'Max Frequency Summary:(.*?)Total Negative Slack Summary:', text)
    slack = re.search(r'Total Negative Slack Summary:(.*?)Timing Details', text)
    if not frequency or not slack:
        raise ValueError('missing timing summary: ' + str(report))
    clocks = re.findall(r'\d+\s+(\S+)\s+([\d.]+)\(MHz\)\s+([\d.]+)\(MHz\)', frequency[1])
    no_paths = re.findall(r'No timing paths to get frequency of (\S+?)!', frequency[1])
    rows = re.findall(r'(\S+)\s+(Setup|Hold)\s+(-?[\d.]+)\s+(\d+)', slack[1])
    if not clocks or len(rows) != 2 * (len(clocks) + len(no_paths)):
        raise ValueError('incomplete clock/setup/hold summaries')
    failures = []
    for name, required, actual in clocks:
        print('{}: required {} MHz, Fmax {} MHz'.format(name, required, actual))
        if float(actual) < float(required):
            failures.append(name + ' Fmax below constraint')
        if {kind for clock, kind, _, _ in rows if clock == name} != {'Setup', 'Hold'}:
            failures.append(name + ' missing setup/hold result')
    for name in no_paths:
        print('{}: Gowin reports no data timing paths'.format(name))
        if {kind for clock, kind, _, _ in rows if clock == name} != {'Setup', 'Hold'}:
            failures.append(name + ' missing setup/hold result')
    for name, kind, tns, endpoints in rows:
        if float(tns) < 0 or int(endpoints) != 0:
            failures.append('{} {}: TNS {} ns, {} failing endpoints'.format(name, kind, tns, endpoints))
    if failures:
        raise ValueError('\n'.join(failures))
    print('PASS all constrained clocks: setup/hold TNS = 0')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', help='Gowin output basename, for example fm_138k_rgb_hdmi')
    args = parser.parse_args()
    try:
        check(args.base)
    except (ValueError, OSError) as error:
        parser.exit(1, 'TIMING FAILED: {}\nDo not program this build.\n'.format(error))
