"""Capture non-secret fixture counts/value for replay side-effect comparison."""
import json
import sqlite3
import sys
from phone import OUT

with sqlite3.connect('file:D:/gssms-test-backend/ui.sqlite3?mode=ro', uri=True) as db:
    tables = ['maintenance_maintenancerecord', 'maintenance_maintenancerecordline',
              'assets_assetspecificationmeasurement', 'assets_deficiency',
              'maintenance_workorderevent', 'core_activitylog']
    result = {'counts': {t: db.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]
                         for t in tables},
              'line_values': db.execute('SELECT id, recorded_value FROM maintenance_maintenancerecordline').fetchall()}
print(json.dumps(result))
if sys.argv[1:]:
    (OUT / f'{sys.argv[1]}.json').write_text(json.dumps(result, indent=2))
