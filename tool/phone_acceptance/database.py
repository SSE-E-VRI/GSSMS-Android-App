"""Snapshot/reset the exact disposable database; stop its server before reset."""
import sqlite3
import sys
from pathlib import Path

DATABASE = Path('D:/gssms-test-backend/ui.sqlite3')
BASELINE = DATABASE.with_name('ui.phone-baseline-20261024.sqlite3')
action = sys.argv[1]
assert action in ('snapshot', 'reset')
source, destination = (DATABASE, BASELINE) if action == 'snapshot' else (BASELINE, DATABASE)
assert source.is_file()
if action == 'snapshot':
    assert not destination.exists(), 'Baseline already exists; do not overwrite'
with sqlite3.connect(f'file:{source.as_posix()}?mode=ro', uri=True) as src:
    with sqlite3.connect(destination) as dst:
        src.backup(dst)
        assert dst.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
print(f'{action}: {destination}')
