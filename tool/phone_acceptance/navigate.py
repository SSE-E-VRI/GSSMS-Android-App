"""Open the prepared fixture from the observed home screen while online."""
import re
import sys
import time
import xml.etree.ElementTree as ET
from phone import adb, snapshot, OUT

prefix = sys.argv[1]


def tap_observed(label, target):
    for attempt in range(3):
        snapshot(label)
        nodes = ET.parse(OUT / f'{label}.xml').getroot().iter('node')
        matches = [n for n in nodes if target in
                   (n.attrib.get('text') or n.attrib.get('content-desc') or '')]
        if matches:
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', matches[0].attrib['bounds']))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            time.sleep(1)
            return
        time.sleep(1)
    raise RuntimeError(f'{target} absent; stopping rather than guessing coordinates')


tap_observed(prefix + '-home', 'Continue work')
tap_observed(prefix + '-detail', 'Open Checklist')
snapshot(prefix + '-form')
adb('shell', 'input', 'swipe', '500', '1900', '500', '1000', '600')
snapshot(prefix + '-visible')
