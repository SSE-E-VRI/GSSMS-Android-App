"""
generate_fixtures.py
Generates the 10 fixtures specified in parity_plan.md §2 into tool/report_parity/fixtures/
"""
import os
import json

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..', '..', '..', 'D:', 'GSSMS-Android-APP', 'tool', 'report_parity', 'fixtures')
# Normalize path
FIXTURES_DIR = r'D:\GSSMS-Android-APP\tool\report_parity\fixtures'
os.makedirs(FIXTURES_DIR, exist_ok=True)

# 1. checklist_pm_full
f1 = {
    "id": "checklist_pm_full",
    "kind": "checklist",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000101",
    "workOrder": {
        "id": 101,
        "ticket_number": "JW-2026-000101",
        "station_name": "Thalanallur",
        "depot_name": "Depot 1",
        "assigned_to_name": "R. Kumar",
        "title": "Monthly Transformer PM",
        "description": "Routine monthly transformer maintenance",
        "asset_name": "TR-01",
        "updated_at": "2026-10-02T10:00:00Z",
        "execution_mode": "CHECKLIST",
        "status": "COMPLETED",
        "assigned_to": 12
    },
    "payload": {
        "id": 501,
        "work_order": 101,
        "date_of_maintenance": "2026-10-02",
        "technician_name": "R. Kumar",
        "remarks": "Completed successfully. Minor issues noted — all addressed · verified on-site.",
        "other_staff": "S. Sharma, K. Patel",
        "schedule_details": {
            "station_name": "Thalanallur",
            "template_name": "Monthly Transformer Checklist",
            "organization": {
                "railway_name": "Southern Railway",
                "division_name": "Chennai Division",
                "depot_name": "Tambaram Depot",
                "register_title": "Monthly PM Register"
            }
        },
        "verification": {
            "verified_by_name": "M. Supervisor",
            "verified_at": "2026-10-02T15:30:00Z",
            "remarks": "Approved with recommendations."
        },
        "lines": [
            # Group A: Transformer Body
            {
                "id": 1001,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Oil Level & Temperature",
                "inspection_point": "Check oil level gauge glass",
                "status": "OK",
                "status_label_snapshot": "Normal",
                "action_label_snapshot": "No action needed",
                "recorded_value": None,
                "checked_out": True,
                "excluded": False,
                "line_attachments": [{"file_path": "/parity-images/evidence_1.jpg", "caption": "Gauge photo"}]
            },
            {
                "id": 1002,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Oil Level & Temperature",
                "inspection_point": "Check winding temperature thermometer",
                "status": "NOT_OK",
                "status_option": 10,
                "action_option": 20,
                "status_label_snapshot": "High Temp",
                "action_label_snapshot": "Calibrate sensor",
                "deficiency_severity_label": "High",
                "status_options": [
                    {"id": 10, "label": "High Temp", "is_deficiency": True, "action_options": [{"id": 20, "label": "Calibrate sensor", "is_deficiency": False}]}
                ],
                "recorded_value": None,
                "checked_out": True,
                "excluded": False
            },
            {
                "id": 1003,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Oil Level & Temperature",
                "inspection_point": "Inspect silica gel breather colour",
                "status": "NOT_OK",
                "status_option": 11,
                "action_option": 21,
                "status_label_snapshot": "Pinkish (Wet)",
                "action_label_snapshot": "Replace silica gel",
                "status_options": [
                    {"id": 11, "label": "Pinkish (Wet)", "is_deficiency": False, "action_options": [{"id": 21, "label": "Replace silica gel", "is_deficiency": True}]}
                ],
                "recorded_value": None,
                "checked_out": True,
                "excluded": False
            },
            # Parameter run of 3 in Group A
            {
                "id": 1004,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Voltage Check",
                "inspection_point": "Phase voltages",
                "status": "OK",
                "recorded_value": json.dumps({"R": "230", "Y": "231"}),
                "unit": "V",
                "checked_out": True,
                "excluded": False
            },
            {
                "id": 1005,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Voltage Check",
                "inspection_point": "Line to line voltage",
                "status": "OK",
                "recorded_value": "415",
                "unit": "V",
                "checked_out": True,
                "excluded": False
            },
            {
                "id": 1006,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Voltage Check",
                "inspection_point": "Neutral offset",
                "status": "OK",
                "recorded_value": "",
                "unit": "V",
                "checked_out": True,
                "excluded": False
            },
            # Skipped lines
            {
                "id": 1007,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Skipped Line",
                "inspection_point": "Unchecked line",
                "status": "OK",
                "checked_out": False,
                "excluded": False
            },
            {
                "id": 1008,
                "asset_unique_id": "TR-BODY-01",
                "asset_category": "Transformer Main",
                "item_name": "Excluded Line",
                "inspection_point": "Supervisor excluded line",
                "status": "OK",
                "checked_out": True,
                "excluded": True
            },
            # Group B: Bushings & Terminations
            {
                "id": 1009,
                "asset_unique_id": "TR-BUSH-02",
                "asset_category": "Bushings",
                "item_name": "HV Bushings",
                "inspection_point": "Clean porcelain insulators",
                "status": "OK",
                "status_label_snapshot": "Cleaned",
                "checked_out": True,
                "excluded": False
            }
        ]
    }
}

# 2. checklist_pm_minimal
f2 = {
    "id": "checklist_pm_minimal",
    "kind": "checklist",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000102",
    "workOrder": {
        "id": 102,
        "ticket_number": "JW-2026-000102",
        "station_name": "Katpadi",
        "depot_name": "Katpadi Depot",
        "assigned_to_name": "A. Singh",
        "title": "Minimal Checklist",
        "description": "Minimal check",
        "execution_mode": "CHECKLIST",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 502,
        "work_order": 102,
        "date_of_maintenance": "2026-10-01",
        "technician_name": "A. Singh",
        "remarks": "",
        "other_staff": "",
        "schedule_details": None,
        "verification": None,
        "lines": [
            {
                "id": 1020,
                "asset_unique_id": "GEN-01",
                "asset_category": "General",
                "item_name": "Visual Inspection",
                "inspection_point": "Check physical foundation",
                "status": "OK",
                "checked_out": True,
                "excluded": False
            }
        ]
    }
}

# 3. checklist_pm_long
long_lines = []
for g_idx in range(1, 4):
    for l_idx in range(1, 21):
        line_id = g_idx * 100 + l_idx
        # Group 1 has item spanning 25 rows? Wait, plan says: "60 lines in 3 groups, one item spanning 25 rows"
        # Let's make Group 1 have 25 lines with the same item_name!
        pass

long_lines = []
# Group 1: 30 lines, first item has 25 lines
for i in range(1, 26):
    long_lines.append({
        "id": 2000 + i,
        "asset_unique_id": "FEEDER-G1",
        "asset_category": "Feeder Bay",
        "item_name": "Continuous Parameter Run",
        "inspection_point": f"Feeder Checkpoint #{i:02d}",
        "status": "OK",
        "status_label_snapshot": "Normal",
        "recorded_value": f"{100 + i}",
        "unit": "A",
        "checked_out": True,
        "excluded": False
    })
for i in range(26, 31):
    long_lines.append({
        "id": 2000 + i,
        "asset_unique_id": "FEEDER-G1",
        "asset_category": "Feeder Bay",
        "item_name": f"Independent Item {i}",
        "inspection_point": f"General Checkpoint #{i:02d}",
        "status": "OK",
        "status_label_snapshot": "Normal",
        "checked_out": True,
        "excluded": False
    })
# Group 2: 15 lines
for i in range(1, 16):
    long_lines.append({
        "id": 2100 + i,
        "asset_unique_id": "ISOLATOR-G2",
        "asset_category": "Switchgear",
        "item_name": f"Isolator Check {i}",
        "inspection_point": f"Blade alignment #{i}",
        "status": "OK",
        "status_label_snapshot": "Aligned",
        "checked_out": True,
        "excluded": False
    })
# Group 3: 15 lines
for i in range(1, 16):
    long_lines.append({
        "id": 2200 + i,
        "asset_unique_id": "EARTH-G3",
        "asset_category": "Earthing System",
        "item_name": f"Earth Pit {i}",
        "inspection_point": f"Resistance test pit #{i}",
        "status": "OK",
        "status_label_snapshot": "Good",
        "recorded_value": f"{1.5 + (i * 0.1):.1f}",
        "unit": "Ohm",
        "checked_out": True,
        "excluded": False
    })

f3 = {
    "id": "checklist_pm_long",
    "kind": "checklist",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000103",
    "workOrder": {
        "id": 103,
        "ticket_number": "JW-2026-000103",
        "station_name": "Villupuram",
        "depot_name": "VRI Depot",
        "assigned_to_name": "T. Technician",
        "title": "Annual Substation Major Maintenance",
        "description": "Comprehensive annual checklist",
        "execution_mode": "CHECKLIST",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 503,
        "work_order": 103,
        "date_of_maintenance": "2026-09-30",
        "technician_name": "T. Technician",
        "remarks": "Completed across multiple bays. All parameters within permissible tolerances.",
        "schedule_details": {
            "station_name": "Villupuram",
            "template_name": "Annual Major Substation PM",
            "organization": {
                "railway_name": "Southern Railway",
                "division_name": "Tiruchirappalli Division",
                "depot_name": "Villupuram Depot"
            }
        },
        "verification": {
            "verified_by_name": "S. Supervisor",
            "verified_at": "2026-10-01T08:00:00Z",
            "remarks": "Major PM verified and closed."
        },
        "lines": long_lines
    }
}

# 4. breakdown_deficiency
f4 = {
    "id": "breakdown_deficiency",
    "kind": "complaint",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000104",
    "workOrder": {
        "id": 104,
        "ticket_number": "JW-2026-000104",
        "station_name": "Chengalpattu",
        "depot_name": "CGL Depot",
        "assigned_to_name": "V. Murugan",
        "title": "Deficiency Rectification - Circuit Breaker",
        "description": "Fix air pressure leakage in pneumatic drive",
        "asset_name": "CB-CGL-01",
        "execution_mode": "COMPLAINT",
        "status": "COMPLETED",
        "original_deficiency_details": {
            "asset_unique_id": "CB-CGL-01",
            "asset_category": "Circuit Breakers",
            "inspection_point": "Pneumatic pressure check",
            "severity": "High",
            "status_label": "Pressure Low",
            "action_label": "Replace seal gasket",
            "finding": "Air leaking from manifold connector during charging cycle."
        }
    },
    "payload": {
        "id": 604,
        "work_order": 104,
        "organization": {
            "railway_name": "Southern Railway",
            "division_name": "Chennai Division",
            "depot_name": "CGL Depot"
        },
        "initial_findings": "Found cracked nitrile O-ring on air manifold inlet pipe.",
        "action_taken": "Depressurized cylinder, removed worn gasket, installed new seal kit and leak-tested at 15 bar.",
        "final_remarks": "Operating smoothly without pressure drop over 2 hours.",
        "parameters": [
            {"parameter_name": "Initial Pressure", "recorded_value": "8.5", "unit": "bar"},
            {"parameter_name": "Holding Pressure", "recorded_value": "15.0", "unit": "bar"},
            {"parameter_name": "Charging Time", "recorded_value": "42", "unit": "sec"}
        ],
        "submission_history": [
            {
                "submission_no": 1,
                "timestamp": "2026-09-29T11:00:00Z",
                "updated_by_name": "V. Murugan",
                "initial_findings": "Initial draft findings.",
                "action_taken": "Work in progress.",
                "final_remarks": "",
                "photos": []
            },
            {
                "submission_no": 2,
                "timestamp": "2026-09-29T16:45:00Z",
                "updated_by_name": "V. Murugan",
                "initial_findings": "Found cracked nitrile O-ring on air manifold inlet pipe.",
                "action_taken": "Depressurized cylinder, removed worn gasket, installed new seal kit and leak-tested at 15 bar.",
                "final_remarks": "Operating smoothly without pressure drop over 2 hours.",
                "parameters": [
                    {"parameter_name": "Initial Pressure", "recorded_value": "8.5", "unit": "bar"},
                    {"parameter_name": "Holding Pressure", "recorded_value": "15.0", "unit": "bar"},
                    {"parameter_name": "Charging Time", "recorded_value": "42", "unit": "sec"}
                ],
                "photos": [
                    {"image": "/parity-images/before_1.jpg", "kind": "BEFORE", "photo_type": "BEFORE", "caption": "Leaking manifold connector"},
                    {"image": "/parity-images/portrait_1.jpg", "kind": "BEFORE", "photo_type": "BEFORE", "caption": "Cracked O-ring"},
                    {"image": "/parity-images/after_1.jpg", "kind": "AFTER", "photo_type": "AFTER", "caption": "New gasket assembly installed"},
                    {"image": "/parity-images/evidence_1.jpg", "kind": "AFTER", "photo_type": "AFTER", "caption": "Pressure gauge at 15 bar"},
                    {"image": "/parity-images/wide_1.jpg", "kind": "AFTER", "photo_type": "AFTER", "caption": "Overall completed cabinet"}
                ]
            }
        ],
        "verification": None
    }
}

# 5. breakdown_complaint
f5 = {
    "id": "breakdown_complaint",
    "kind": "complaint",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000105",
    "workOrder": {
        "id": 105,
        "ticket_number": "JW-2026-000105",
        "station_name": "Arakkonam",
        "depot_name": "AJJ Depot",
        "assigned_to_name": "K. Raman",
        "title": "Emergency Breakdown - Battery Charger Fail",
        "description": "DC control supply failure alarm in control room",
        "asset_name": "CHG-AJJ-01",
        "execution_mode": "COMPLAINT",
        "status": "COMPLETED",
        "original_complaint_details": {
            "failure_date": "2026-09-28",
            "failure_time": "14:05:00",
            "department": "ELECTRICAL",
            "complainant_name": "Station Master AJJ",
            "description": "Alarm buzzed at 14:00. Output DC voltage dropped to 95V."
        }
    },
    "payload": {
        "id": 605,
        "work_order": 105,
        "organization": {
            "railway_name": "Southern Railway",
            "division_name": "Chennai Division",
            "depot_name": "AJJ Depot"
        },
        "initial_findings": "Thyristor bridge fuse blown on phase B.",
        "action_taken": "Replaced high-speed semiconductor fuse 100A. Checked filter capacitors and recalibrated float voltage.",
        "final_remarks": "Float voltage restored to 110V DC steady.",
        "parameters": [],
        "photos": [],
        "submission_history": [
            {
                "submission_no": 1,
                "timestamp": "2026-09-28T18:20:00Z",
                "updated_by_name": "K. Raman",
                "initial_findings": "Thyristor bridge fuse blown on phase B.",
                "action_taken": "Replaced high-speed semiconductor fuse 100A. Checked filter capacitors and recalibrated float voltage.",
                "final_remarks": "Float voltage restored to 110V DC steady.",
                "photos": []
            }
        ],
        "verification": {
            "verified_by_name": "E. Engineer",
            "verified_at": "2026-09-28T19:00:00Z",
            "remarks": "Verified DC voltage output and alarm clearance."
        }
    }
}

# 6. breakdown_jobwork
f6 = {
    "id": "breakdown_jobwork",
    "kind": "complaint",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000106",
    "workOrder": {
        "id": 106,
        "ticket_number": "JW-2026-000106",
        "station_name": "Tambaram",
        "depot_name": "TBM Depot",
        "assigned_to_name": "M. Das",
        "title": "General Yard Cable Trench Inspection & Repair",
        "description": "Concrete slab cover displaced by vehicle movement",
        "asset_name": None,
        "execution_mode": "COMPLAINT",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 606,
        "work_order": 106,
        "organization": None,
        "initial_findings": "Two trench slabs damaged; signal cable exposed but unhurt.",
        "action_taken": "Fabricated and laid two heavy-duty RCC cover slabs.",
        "final_remarks": "Trench sealed securely.",
        "parameters": [],
        "photos": [],
        "submission_history": [
            {
                "submission_no": 1,
                "timestamp": "2026-09-27T12:00:00Z",
                "updated_by_name": "M. Das",
                "initial_findings": "Two trench slabs damaged; signal cable exposed but unhurt.",
                "action_taken": "Fabricated and laid two heavy-duty RCC cover slabs.",
                "final_remarks": "Trench sealed securely.",
                "photos": []
            }
        ],
        "verification": None
    }
}

# 7. inspection_pointwise
f7 = {
    "id": "inspection_pointwise",
    "kind": "inspection",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000107",
    "workOrder": {
        "id": 107,
        "ticket_number": "JW-2026-000107",
        "station_name": "Thalanallur",
        "depot_name": "Depot 1",
        "assigned_to_name": "P. Inspector",
        "title": "Detailed Substation Safety Inspection",
        "description": "Routine quarterly safety and compliance inspection",
        "execution_mode": "INSPECTION",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 707,
        "ticket_number": "JW-2026-000107",
        "is_pointwise": True,
        "inspection_details": {
            "title": "Quarterly Electrical Safety Audit",
            "inspection_no": "INSP-2026-042",
            "inspector_name": "P. Inspector",
            "inspection_date": "2026-09-25",
            "inspection_time": "10:30:00",
            "station_name": "Thalanallur",
            "remarks": "Overall installation compliant with safety guidelines. Observations noted below.",
            "general_evidence_photos": [
                {"image": "/parity-images/wide_1.jpg", "caption": "Control room general overview"},
                {"image": "/parity-images/evidence_1.jpg", "caption": "Yard perimeter fence intact"}
            ]
        },
        "submission_history": [
            {
                "submission_no": 1,
                "timestamp": "2026-09-25T14:30:00Z",
                "submitted_by_name": "P. Inspector",
                "point_snapshots": [
                    {
                        "point_job_work_id": 701,
                        "point_number": 1,
                        "observation": "Lightning arrester surge counter reading",
                        "asset_name": "LA-01",
                        "priority": "LOW",
                        "initial_findings": "Counter reading 14 recorded.",
                        "action_taken": "",
                        "final_remarks": "Observation only — no corrective action required",
                        "corrective_action_performed": False,
                        "technical_parameters": [],
                        "before_photos": [],
                        "after_photos": [],
                        "inspection_evidence_photos": []
                    },
                    {
                        "point_job_work_id": 702,
                        "point_number": 2,
                        "observation": "Earth resistance measurement at main pit #1",
                        "asset_name": "EARTH-01",
                        "priority": "HIGH",
                        "initial_findings": "Resistance measured 4.8 ohms (standard <= 2.0 ohms).",
                        "action_taken": "Treated pit with bentonite compound and water.",
                        "final_remarks": "Resistance reduced to 1.8 ohms.",
                        "corrective_action_performed": True,
                        "technical_parameters": [
                            {"parameter_name": "Initial Resistance", "recorded_value": "4.8", "unit": "Ohm"},
                            {"parameter_name": "Final Resistance", "recorded_value": "1.8", "unit": "Ohm"}
                        ],
                        "inspection_evidence_photos": [
                            {"image": "/parity-images/evidence_1.jpg", "caption": "Earth tester reading 4.8 Ohm"}
                        ],
                        "before_photos": [
                            {"image": "/parity-images/before_1.jpg", "caption": "Dry soil in earth pit"}
                        ],
                        "after_photos": [
                            {"image": "/parity-images/after_1.jpg", "caption": "Moist pit after chemical treatment"}
                        ]
                    },
                    {
                        "point_job_work_id": 703,
                        "point_number": 3,
                        "observation": "Battery bank terminal torque check",
                        "asset_name": "BAT-BANK",
                        "priority": "MEDIUM",
                        "initial_findings": "Two cell interconnections loose.",
                        "action_taken": "Torqued all terminals to 12 Nm.",
                        "final_remarks": "Re-torqued and applied petroleum jelly.",
                        "corrective_action_performed": True,
                        "technical_parameters": [
                            {"parameter_name": "Applied Torque", "recorded_value": "12", "unit": "Nm"}
                        ],
                        "inspection_evidence_photos": [],
                        "before_photos": [],
                        "after_photos": []
                    }
                ]
            }
        ],
        "verification": {
            "verified_by_name": "Chief Safety Officer",
            "verified_at": "2026-09-26T09:15:00Z",
            "remarks": "Safety compliance verified."
        }
    }
}

# 8. inspection_legacy
f8 = {
    "id": "inspection_legacy",
    "kind": "inspection",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000108",
    "workOrder": {
        "id": 108,
        "ticket_number": "JW-2026-000108",
        "station_name": "Jolarpettai",
        "depot_name": "JTJ Depot",
        "assigned_to_name": "B. Natarajan",
        "title": "Legacy Form Station Inspection",
        "description": "Legacy format inspection record",
        "execution_mode": "INSPECTION",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 708,
        "ticket_number": "JW-2026-000108",
        "is_pointwise": False,
        "inspection_details": {
            "title": "Station Illumination & Cabling Walkthrough",
            "inspection_no": "INSP-LEG-09",
            "inspector_name": "B. Natarajan",
            "inspection_date": "2026-09-20",
            "inspection_time": "16:00:00",
            "station_name": "Jolarpettai",
            "remarks": "General platform lighting and emergency backup check.",
            "points": [
                {"point_number": 1, "description": "Platform 1 lighting distribution box inspection", "priority": "HIGH"},
                {"point_number": 2, "description": "DG set auto-start changeover test", "priority": "MEDIUM"},
                {"point_number": 3, "description": "Signaling cable duct cover integrity", "priority": "LOW"}
            ]
        },
        "findings_summary": "Distribution box MCB tripped on line 2; DG changeover delayed by 8s.",
        "action_taken": "Reset line 2, replaced timer relay on AMF panel.",
        "technician_remarks": "All systems operating normally after component replacement.",
        "corrective_action_performed": True,
        "technical_parameters": [
            {"parameter_name": "DG Changeover Time", "recorded_value": "3.5", "unit": "sec"}
        ],
        "photos": [
            {"image": "/parity-images/before_1.jpg", "photo_type": "BEFORE", "caption": "Faulty timer relay in AMF panel"},
            {"image": "/parity-images/after_1.jpg", "photo_type": "AFTER", "caption": "New electronic timer installed"}
        ],
        "verification": None
    }
}

# 9. rectification_mixed
f9 = {
    "id": "rectification_mixed",
    "kind": "rectification",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000109",
    "workOrder": {
        "id": 109,
        "ticket_number": "JW-2026-000109",
        "station_name": None,
        "depot_name": "MAS Depot",
        "assigned_to_name": "R. Vignesh",
        "title": "Grouped Deficiency Rectification Batch #4",
        "description": "Batch rectification of 3 logged deficiencies",
        "execution_mode": "RECTIFICATION",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 809,
        "ticket_number": "JW-2026-000109",
        "report_date": "2026-09-24",
        "station_name": "Chennai Central",
        "technician_name": "R. Vignesh",
        "other_staff": "M. Kumar",
        "organization": {
            "railway_name": "Southern Railway",
            "division_name": "Chennai Division",
            "depot_name": "MAS Central Depot"
        },
        "verified_by": "Senior Divisional Electrical Engineer",
        "verified_at": "2026-09-24T17:30:00Z",
        "verification_remarks": "Item 1 approved. Item 2 material requisition noted.",
        "final_outcome": "2 items addressed (1 rectified on site, 1 spare pending). Overall yard safe.",
        "items": [
            {
                "id": 901,
                "asset_unique_id": "BAY-4-ISO",
                "checkpoint": "Auxiliary contact alignment",
                "source_ticket": "JW-2026-000088",
                "source_date": "2026-09-15",
                "finding": "Auxiliary switch not making contact during manual open.",
                "action_taken": "Cleaned contacts with electro-cleaner and readjusted driving linkage.",
                "outcome": "RECTIFIED",
                "reason_not_rectified": None,
                "photos": [
                    {"image": "/parity-images/before_1.jpg", "kind": "BEFORE"},
                    {"image": "/parity-images/after_1.jpg", "kind": "AFTER"}
                ]
            },
            {
                "id": 902,
                "asset_unique_id": "CT-SEC-02",
                "checkpoint": "Terminal block hairline crack",
                "source_ticket": "JW-2026-000089",
                "source_date": "2026-09-16",
                "finding": "Cracked secondary terminal block on CT phase Y.",
                "action_taken": "Inspected insulation resistance (measured > 100M ohm).",
                "outcome": "NOT_RECTIFIED",
                "reason_not_rectified": "Spare terminal block out of stock in depot store. Indent #842 placed.",
                "photos": [
                    {"image": "/parity-images/before_1.jpg", "kind": "BEFORE"}
                ]
            },
            {
                "id": 903,
                "asset_unique_id": "LIGHT-MAST-1",
                "checkpoint": "Aviation warning lamp bulb",
                "source_ticket": "JW-2026-000092",
                "source_date": "2026-09-18",
                "finding": "Aviation bulb fused on top of mast.",
                "action_taken": "",
                "outcome": "PENDING",
                "reason_not_rectified": None,
                "photos": []
            }
        ]
    }
}

# 10. rectification_single
f10 = {
    "id": "rectification_single",
    "kind": "rectification",
    "generatedAt": "2026-10-03T04:00:00Z",
    "ticket": "JW-2026-000110",
    "workOrder": {
        "id": 110,
        "ticket_number": "JW-2026-000110",
        "station_name": None,
        "depot_name": "TBM Depot",
        "assigned_to_name": "P. Sundaram",
        "title": "Single Item Rectification",
        "description": "Fix single isolator lock",
        "execution_mode": "RECTIFICATION",
        "status": "COMPLETED"
    },
    "payload": {
        "id": 810,
        "ticket_number": "JW-2026-000110",
        "report_date": "2026-09-22",
        "station_name": None,
        "technician_name": "P. Sundaram",
        "other_staff": "",
        "organization": None,
        "verified_by": None,
        "verified_at": None,
        "verification_remarks": "",
        "final_outcome": "Deficiency closed.",
        "items": [
            {
                "id": 910,
                "asset_unique_id": "ISO-LOCK-01",
                "checkpoint": "Mechanical interlock mechanism",
                "source_ticket": "JW-2026-000075",
                "source_date": "2026-09-10",
                "finding": "Castleton key interlock jammed with rust.",
                "action_taken": "Dismantled lock barrel, cleaned with kerosene, lubricated with graphite powder.",
                "outcome": "RECTIFIED",
                "reason_not_rectified": None,
                "photos": [
                    {"image": "/parity-images/before_1.jpg", "kind": "BEFORE"},
                    {"image": "/parity-images/after_1.jpg", "kind": "AFTER"}
                ]
            }
        ]
    }
}

fixtures = [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10]
for f in fixtures:
    p = os.path.join(FIXTURES_DIR, f"{f['id']}.json")
    with open(p, 'w', encoding='utf-8') as out:
        json.dump(f, out, indent=2)
    print(f"Wrote fixture: {p}")

print("All 10 fixtures generated successfully.")
