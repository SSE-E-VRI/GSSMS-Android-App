"""Cross-check the retained evidence supporting the acceptance report."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'docs' / 'acceptance' / 'evidence-2026-10-24'


def read(name):
    return json.loads((ROOT / (name + '.json')).read_text())


def value(name):
    return json.loads(dict(read(name)['line_values'])[1])


assert read('17-queue-final-12-5')[0]['payload']['value'] == '12.5'
assert read('18-after-restart-queue') == read('17-queue-final-12-5')
assert read('24-write-failure-queue') == []
assert read('25-storage-retry-queue')[0]['payload']['value'] == '21.5'
assert value('36-before-lost-response') == '21.5'
assert value('37-after-commit') == value('38-aftercommit-recovered') == '33.5'
assert read('36-before-lost-response')['counts'] == read('38-aftercommit-recovered')['counts']
assert read('41-overlay-restored-queue')[0]['payload']['value'] == '44.5'
assert value('41-overlay-server-old') == '33.5'
assert read('42-repeated-sync-result') == {'taps': 3, 'new_requests': 1}
assert value('43-explicit-sync-server') == '44.5'
assert read('46-permission-queue')[0]['status'] == 'FAILED'
assert read('46-permission-queue')[0]['payload']['value'] == '55.5'
assert value('46-permission-server') == '44.5'
assert read('49-other-account-queue') == []
assert read('50-token-expiry-queue')[0]['owner'] == 3
assert read('51-token-expiry-queue') == []
assert value('51-token-expiry-server') == '66.5'
events = [json.loads(line) for line in (ROOT / 'requests.jsonl').read_text().splitlines()]
for reading in ['21.5', '33.5']:
    attempts = [e for e in events if e['phase'] == 'received' and
                e['payload'].get('value') == reading]
    assert len(attempts) == 2, (reading, attempts)
    assert len({e['key'] for e in attempts}) == 1
assert 'Open Checklist' not in (ROOT / '11-offline-detail.xml').read_text()
assert 'Sign In' in (ROOT / '19-offline-restart-settled.xml').read_text()
assert '44.5' in (ROOT / '41-restarted-overlay-visible.xml').read_text()
expiry = (ROOT / 'server-expiry.stderr.log').read_text()
assert 'submit_line/ 401' in expiry and 'auth/refresh/ 200' in expiry
print('Retained evidence cross-checks passed; overall acceptance still FAIL (A1/A3).')
