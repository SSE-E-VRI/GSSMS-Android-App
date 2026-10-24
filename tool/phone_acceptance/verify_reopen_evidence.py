"""Cross-check retained evidence for the focused F1/F2/F3 reacceptance."""
import json
import xml.etree.ElementTree as ET
from pathlib import Path

folder = Path(__file__).resolve().parents[2]/'docs/acceptance/reopen-2026-10-24'
def read(name):
    return json.loads((folder/(name+'.json')).read_text())
def text(name):
    return (folder/(name+'.xml')).read_text()

assert 'Open Checklist' in text('06-offline-detail')
assert 'Saved checklists' in text('26-final-cold-restore')
assert '93.5' in text('27-final-restored-value')
assert 'Saved on this phone' in text('27-final-restored-value')
buttons = [n for n in ET.fromstring(text('27-final-restored-value')).iter('node')
           if n.attrib.get('content-desc') == 'Connect to submit' or n.attrib.get('text') == 'Connect to submit']
assert len(buttons)==1 and buttons[0].attrib['enabled']=='false'
assert read('25-final-queue')[0]['payload']['value']=='93.5'
assert read('28-final-queue')==[]
assert json.loads(dict(read('28-final-server')['line_values'])[1])=='93.5'
assert read('14-refused-queue')==read('13-restricted-queue')
assert read('14-refused-queue')[0]['payload']['value']=='92.5'
assert json.loads(dict(read('14-refused-server')['line_values'])[1])=='0'
assert 'Sign In' in text('15-refusal-settled')
assert 'queued work is kept' in text('15-refusal-settled')
assert 'No assigned checklists downloaded' in text('21-other-offline-empty')
assert 'OFFLINE ACCEPTANCE ONLY' not in text('21-other-offline-empty')
assert read('21-other-offline-queue')==[]
assert read('29-cache-before-online-read')['lines'][0]['recorded_value']=='0'
assert read('30-cache-after-online-read')['lines'][0]['recorded_value']=='93.5'
print('Focused reopen evidence checks passed. Cache freshness F4 remains open.')
