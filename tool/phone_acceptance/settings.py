"""Disposable phone acceptance settings. Never use for deployment."""
import os
from pathlib import Path
from datetime import timedelta

os.environ['SECRET_KEY'] = 'phone-acceptance-only-disposable-signing-key-20261024'
os.environ['DEBUG'] = 'True'
os.environ['USE_SQLITE'] = 'True'
CELERY_BROKER_URL = 'memory://'

from gssms_project.settings import *  # noqa: F403,E402

DATABASES = {'default': {
    'ENGINE': 'django.db.backends.sqlite3',
    'NAME': Path('D:/gssms-test-backend/ui.sqlite3'),
    'OPTIONS': {'timeout': 20},
}}
ALLOWED_HOSTS = ['127.0.0.1', 'localhost', 'testserver']
EMAIL_BACKEND = 'django.core.mail.backends.locmem.EmailBackend'
CACHES = {'default': {'BACKEND': 'django.core.cache.backends.locmem.LocMemCache'}}
CHANNEL_LAYERS = {'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'}}
CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_BROKER_URL = 'memory://'
MEDIA_ROOT = Path('D:/gssms-test-backend/media')
SIMPLE_JWT = {**SIMPLE_JWT, 'SIGNING_KEY': SECRET_KEY,
              'ACCESS_TOKEN_LIFETIME': timedelta(seconds=15)}  # noqa: F405
MIDDLEWARE = ['faults.AcceptanceFaults', *MIDDLEWARE]  # noqa: F405
