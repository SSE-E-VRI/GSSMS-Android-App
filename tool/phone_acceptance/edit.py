"""Paced input for a numeric field at an observed screen location."""
import sys
import time
from phone import adb, snapshot

x, y, old_length, value, label = sys.argv[1:]
adb('shell', 'input', 'tap', x, y)
time.sleep(.5)
adb('shell', 'input', 'keyevent', '123')
time.sleep(.2)
for _ in range(int(old_length)):
    adb('shell', 'input', 'keyevent', '67')
    time.sleep(.08)
for character in value:
    adb('shell', 'input', 'text', character)
    time.sleep(.2)
time.sleep(1.5)
adb('shell', 'input', 'keyevent', '4')
snapshot(label)
