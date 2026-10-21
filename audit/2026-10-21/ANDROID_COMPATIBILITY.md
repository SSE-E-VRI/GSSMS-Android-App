# Android compatibility

Declared min SDK 24, target/compile SDK 36. This is build configuration, not a verified compatibility range. ADB discovery succeeded with no devices attached; no emulator launched or physical device exercised.

| Configuration | Status | Required evidence |
|---|---|---|
| API 24 minimum | BLOCKED | install/launch, auth, picker, scanner, storage |
| API 36 target | BLOCKED | edge-to-edge, back, media/location permissions, process death |
| Current supported Android platform | NOT TESTED | identify available SDK/device and test current platform behaviors |
| Small phone/tablet/densities | BLOCKED | layout, long text, keyboard, screenshots |
| Landscape and rotation | BLOCKED | form/state retention, scanner lifecycle |
| Gesture and three-button navigation | BLOCKED | back stack, dialogs, system insets |
| Low memory/process death | BLOCKED | queue durability, session restoration, evidence picker result recovery |
| Denied/revoked permissions | BLOCKED | camera/location/gallery graceful recovery |
| Intermittent connectivity | BLOCKED | delayed retries, conflicts, token refresh, no duplicate mutation |
| Native libraries/ABI/16KB pages | NOT TESTED | resolved plugins and native packaging/device validation |

MainActivity extends FlutterActivity and declares common configuration changes, adjustResize and predictive back enabled. No retrieveLostData or restorationScopeId/restorable navigation usage found in lib; exercise Android activity/process loss during camera capture and unsaved forms before accepting restoration. No compatibility PASS assigned from source or host widget tests.
