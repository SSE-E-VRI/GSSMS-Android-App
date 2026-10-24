"""Reversible write fault scoped to dev preferences; never fill device storage."""
import time
from phone import adb, snapshot, PACKAGE

try:
    adb('shell', 'run-as', PACKAGE, 'chmod', '500', 'shared_prefs')
    adb('shell', 'run-as', PACKAGE, 'chmod', '400', 'shared_prefs/FlutterSharedPreferences.xml')
    adb('shell', 'input', 'tap', '300', '1340')
    time.sleep(.5)
    adb('shell', 'input', 'keyevent', '123')
    time.sleep(.3)
    adb('shell', 'input', 'text', '9')
    time.sleep(2)
    adb('shell', 'input', 'keyevent', '4')
    snapshot('24-storage-write-failure')
finally:
    adb('shell', 'run-as', PACKAGE, 'chmod', '771', 'shared_prefs')
    adb('shell', 'run-as', PACKAGE, 'chmod', '660', 'shared_prefs/FlutterSharedPreferences.xml')
