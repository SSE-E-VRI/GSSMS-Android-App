"""Prepare only the existing, synthetic October phone-test database."""
import json
import secrets
import os
from pathlib import Path
from django.conf import settings
from django.core.management import call_command
from django.utils import timezone
from accounts.models import User
from maintenance.models import MaintenanceItem, MaintenanceRecord, MaintenanceRecordLine, WorkOrder
from rbac.models import Role, UserRole


def seed():
    assert Path(settings.DATABASES['default']['NAME']).resolve() == Path('D:/gssms-test-backend/ui.sqlite3')
    assert set(User.objects.values_list('username', flat=True)) <= {
        'audit_seed_tech', 'audit_seed_sup', 'phone_slice_other'
    }, 'Unexpected database users; refusing to seed'
    call_command('seed_rbac', verbosity=0)
    output = Path(os.environ.get('GSSMS_PHONE_TEST_OUTPUT',
        Path(__file__).resolve().parents[2] / 'build' / 'phone-acceptance'))
    output.mkdir(parents=True, exist_ok=True)
    credential_file = output / 'credentials.json'
    credentials = json.loads(credential_file.read_text()) if credential_file.exists() else {
        'username': 'audit_seed_tech', 'password': secrets.token_hex(12),
        'other_username': 'phone_slice_other', 'other_password': secrets.token_hex(12),
    }
    credential_file.write_text(json.dumps(credentials), encoding='utf-8')
    role = Role.objects.get(name='MAINTENANCE_STAFF')
    for username, password in [(credentials['username'], credentials['password']),
                               (credentials['other_username'], credentials['other_password'])]:
        user, _ = User.objects.get_or_create(username=username)
        user.org_depot_id = 1
        user.is_active = True
        user.set_password(password)
        user.save()
        UserRole.objects.filter(user=user).delete()
        UserRole.objects.create(user=user, role=role)
    technician = User.objects.get(username=credentials['username'])
    WorkOrder.objects.filter(pk=1).update(
        title='OFFLINE ACCEPTANCE ONLY', status='IN_PROGRESS', assigned_to=technician)
    MaintenanceRecord.objects.filter(pk=1).update(
        technician=technician, date_of_maintenance=timezone.now(), remarks='disposable acceptance')
    MaintenanceItem.objects.filter(pk=1).update(
        value_type='DECIMAL', item_kind='RECORD_PARAMETER', inspection_point='Offline reading')
    MaintenanceRecordLine.objects.filter(maintenance_record_id=1).update(
        checked_out=True, checkout_source='TECHNICIAN', excluded=False,
        recorded_value='0', status='OK', observation_action='',
        checkpoint_snapshot='Offline reading', applicability='REQUIRED_APPLICABLE')
    print(json.dumps({'work_order': 1, 'record': 1, 'line': 1,
                      'technician': technician.pk, 'fully_checked_out': True}))


def reassign(other=False):
    assert Path(settings.DATABASES['default']['NAME']).resolve() == Path('D:/gssms-test-backend/ui.sqlite3')
    user = User.objects.get(username='phone_slice_other' if other else 'audit_seed_tech')
    WorkOrder.objects.filter(pk=1).update(assigned_to=user)
    print(f'Disposable work order 1 assigned to user {user.pk}')
