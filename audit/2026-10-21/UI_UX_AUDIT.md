# UI/UX and accessibility baseline

Device visual verification: BLOCKED. ADB reports no devices. No emulator screenshots, TalkBack session or visual inspection of the running app performed. Widget test execution is separate evidence and cannot certify all UI behavior.

Inventory covers all 32 screen files in [screen inventory](evidence/screen-inventory.md). Source defines shared theme tokens, spacing/radii, light/dark themes and persisted theme selection. Reusable components include status/severity chips, section cards/headers, loading skeletons, empty/error banners, confirmation dialogs, organization/date filters, authenticated image previews, sticky actions and sync badge.

Existing `test/golden/text_scale_golden_test.dart` is an overflow tolerance harness across seven principal screens at scales 1.0, 1.3, 1.5 and both themes. It is not proof of screenshot parity, contrast, TalkBack order or 200% text support. Energy placeholder exposes internal GAP codes/backend details to end users (`energy_placeholder_screen.dart:40` onward); product copy should be reviewed with AUD-06.

Required per-screen checks: 320dp phone and tablet; portrait/landscape; 100/150/200% text; light/dark; IME covering final field/submit; scroll and long error strings; 48dp interactive targets; measured contrast; screen reader labels/focus order; loading/disabled submit and retry states; gesture/three-button back; edge-to-edge insets on target/current Android; dialog focus and dismissal; empty results and pagination truncation notice.

No PASS is assigned to those device checks. Reuse the functional matrix, capture device screenshots and accessibility scanner/manual results after a device becomes available. Do not treat typography lint warnings as a complete visual audit.
