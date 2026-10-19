"""
generate_stress_fixtures.py
Derives the 3 WP-M stress fixtures from existing fixtures (real API JSON shapes):
  checklist_pm_stress, breakdown_long, rectification_long
Run after generate_fixtures.py / make_fixture_images.py. Does not touch other fixtures.
"""
import copy
import json
import os

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixtures')


def load(n):
    with open(os.path.join(D, n + '.json'), encoding='utf-8') as f:
        return json.load(f)


def save(d):
    p = os.path.join(D, d['id'] + '.json')
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
    print('Wrote', p)


# ---- checklist_pm_stress
c = copy.deepcopy(load('checklist_pm_full'))
c['id'] = 'checklist_pm_stress'
c['ticket'] = 'JW-2026-000111'
c['workOrder'].update(id=111, ticket_number='JW-2026-000111')
c['payload'].update(id=511, work_order=111)
c['payload']['remarks'] = (
    "Completed successfully across all bays.\n"
    "Oil sample drawn from main tank and sent to the divisional lab.\n"
    "Silica gel breather replaced; old stock returned to store.\n"
    "Next PM due after the monsoon inspection round."
)
c['payload']['schedule_details']['template_name'] = (
    "Quarterly Traction Substation Transformer, Bushing, Breather, Cooling Fan and "
    "Protection Relay Preventive Maintenance Checklist (Rev. 7)"
)
assert len(c['payload']['schedule_details']['template_name']) >= 120
c['payload']['verification']['remarks'] = "Approved with recommendations.\nRe-check breather colour after 15 days."
long_cells = [
    ("Oil Level, Temperature and Winding Temperature Indicator Assembly",
     "Check oil level gauge glass, magnetic oil gauge and the winding temperature thermometer pocket for leakage",
     "Observed within permissible limits but seepage noted at the gasket joint",
     "Tighten flange bolts and re-check after loading for twenty four hours"),
    ("Oil Level, Temperature and Winding Temperature Indicator Assembly",
     "Verify alarm and trip contacts of the temperature indicators",
     "Contacts operated correctly at the preset values",
     "No action needed"),
]
for ln, (it, ip, sl, al) in zip(c['payload']['lines'][:2], long_cells):
    ln['item_name'] = it
    ln['inspection_point'] = ip
    ln['status_label_snapshot'] = sl
    ln['action_label_snapshot'] = al
c['payload']['lines'][0]['remarks'] = "Seepage at gasket.\nPhoto attached.\nRe-torque on next visit."
c['payload']['lines'][1]['remarks'] = "Alarm set 85 C, trip 95 C.\nVerified with calibrated injector."
c['payload']['lines'][2]['observation_action'] = "Silica gel pink for about 70% of the volume.\nReplaced with fresh charge.\nOld gel sent to regeneration."
save(c)

# ---- breakdown_long
b = copy.deepcopy(load('breakdown_deficiency'))
b['id'] = 'breakdown_long'
b['ticket'] = 'JW-2026-000112'
b['workOrder'].update(id=112, ticket_number='JW-2026-000112')
b['payload'].update(id=612, work_order=112)
P1 = ("Found cracked nitrile O-ring on air manifold inlet pipe and a loose compression fitting on the "
      "secondary line, causing a slow audible leak during the charging cycle.\n\n"
      "The pressure switch was also found chattering because of moisture in the sensing line.\n\n"
      "No other abnormality was seen on the drive mechanism.")
P2 = ("Depressurized the cylinder, isolated the supply and removed the worn gasket.\n\n"
      "Installed a new seal kit, replaced the compression fitting and drained the sensing line.\n\n"
      "Leak-tested at 15 bar for two hours with soap solution and a calibrated gauge.")
P3 = ("Operating smoothly without pressure drop over 2 hours.\n\n"
      "Breaker closed and opened five times with normal charging time.\n\n"
      "Advised the station staff to drain the air receiver every shift.")
photos = []
for i in range(7):
    photos.append({"image": "/parity-images/%s.jpg" % ["before_1", "portrait_1", "before_2"][i % 3],
                   "kind": "BEFORE", "photo_type": "BEFORE", "caption": "Before photo %d of 7: manifold area" % (i + 1)})
for i in range(4):
    photos.append({"image": "/parity-images/%s.jpg" % ["after_1", "wide_1", "after_2"][i % 3],
                   "kind": "AFTER", "photo_type": "AFTER", "caption": "After photo %d of 4: completed work" % (i + 1)})
b['payload'].update(initial_findings=P1, action_taken=P2, final_remarks=P3)
sub = b['payload']['submission_history'][-1]
sub.update(initial_findings=P1, action_taken=P2, final_remarks=P3, photos=photos)
save(b)

# ---- rectification_long
r = copy.deepcopy(load('rectification_mixed'))
r['id'] = 'rectification_long'
r['ticket'] = 'JW-2026-000113'
r['workOrder'].update(id=113, ticket_number='JW-2026-000113')
r['payload'].update(id=813, ticket_number='JW-2026-000113')
tmpl = r['payload']['items']
items = []
for n in range(6):
    it = copy.deepcopy(tmpl[n % 3])
    it['id'] = 920 + n
    it['checkpoint'] = it['checkpoint'] + ' (position %d)' % (n + 1)
    it['finding'] = it['finding'] + ' Observed during the quarterly round; condition worsened since the last visit.'
    items.append(it)
items[1]['reason_not_rectified'] = (
    "Spare terminal block out of stock in depot store. Indent #842 placed.\n"
    "Material expected in 10 days as per stores.\n"
    "Interim measure: terminal taped and the circuit monitored every shift."
)
items[4]['outcome'] = 'NOT_RECTIFIED'
items[4]['reason_not_rectified'] = "Shutdown not granted by traffic control.\nRe-planned for the next power block."
items[5]['photos'] = [{"image": "/parity-images/before_1.jpg", "kind": "BEFORE"},
                      {"image": "/parity-images/portrait_1.jpg", "kind": "BEFORE"},
                      {"image": "/parity-images/after_1.jpg", "kind": "AFTER"}]
r['payload']['items'] = items
r['payload']['final_outcome'] = "6 items reviewed: 3 rectified on site, 2 pending spares, 1 awaiting shutdown.\nOverall yard safe."
save(r)
