# Security and privacy baseline

Defensive source review only; no production penetration test, authenticated backend request or credential disclosure performed. This is not OWASP MASVS certification or a current dependency vulnerability scan.

| Area | Source observation | Remaining verification |
|---|---|---|
| Auth | JWT parsing, permissions fail closed; bearer access in memory; refresh in secure storage | staging enforcement, revocation/expiry, abuse controls |
| Session | controller generation guards, repository partial guards | AUD-02 restore race, refresh persistence/logout race |
| Credentials | secure storage wrapper suppresses final write/delete failures | AUD-03 fault injection/restart |
| Network | Dio 15s connect/receive timeouts, HTTPS-only guard for prod; platform default certificate validation | origin validation, redirect tests, TLS staging proxy |
| Media | thumbnail and preview pass token to supplied URL | AUD-01 origin isolation |
| Pinning | config flag says enableCertPinning, actual guard only enforces HTTPS | threat-model decision, rotation plan if required |
| Storage | operational JSON/outbox in private SharedPreferences, owner ID and backup; photos in app documents | encryption/retention policy, AUD-04 durable save/wipe |
| Photos | normalization strips EXIF on success; raw copy fallback on failure | AUD-05 privacy bypass, file cleanup after logout |
| Android exports | main launcher exported (expected), no other app-defined exported component found; plugin merged manifest not verified | lint/merged manifest, provider authorities and grants |
| Backup | allowBackup=false | device-to-device extraction behavior and release merged manifest |
| Permissions | foreground camera/location and image read, no app-defined background service or push permission | denial/permanent denial, photo picker least privilege, OEM behavior |
| Cleartext | shared config allows loopback/emulator exceptions in prod resources | AUD-07 flavor/environment binding |
| WebView/SQL | no app-authored WebView/JavaScript bridge or SQL database usage found in mobile lib | plugin/native/transitive surface not exhaustively reviewed |
| Logs | auth HTTP logs debug-only and redact named sensitive query keys | all release exception logging and URI/path data review |
| Dependencies | lockfile inventory captured | current advisory scan and transitive/native review NOT RUN |

Open P1 findings: AUD-01, AUD-02, AUD-03, AUD-04. See defect register for exact paths, reproduction, expected/actual, root cause, proposed fix and regression requirements. No secret values or signing properties were printed/read into this report.
