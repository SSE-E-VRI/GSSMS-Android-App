"""Run Django commands against the relocated disposable backend only."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKEND = Path('D:/gssms-test-backend/backend')
sys.path[:] = [str(BACKEND), str(Path(__file__).resolve().parent), *[
    p for p in sys.path if p and Path(p).resolve() != ROOT
]]
os.chdir(BACKEND)
os.environ['DJANGO_SETTINGS_MODULE'] = 'settings'

if __name__ == '__main__':
    if sys.argv[1:] == ['seed']:
        import django
        django.setup()
        from fixtures import seed
        seed()
        raise SystemExit(0)
    from django.core.management import execute_from_command_line
    execute_from_command_line([str(BACKEND / 'manage.py'), *sys.argv[1:]])
