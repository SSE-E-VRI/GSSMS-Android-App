# Open-source notification delivery policy

Status: binding design constraint for Draft PR #12; implementation not yet approved for production.

## Allowed architecture
- Flutter application, Dio and Riverpod for the client.
- Django REST Framework and PostgreSQL for the authoritative inbox, subject to backend repository verification.
- Authenticated HTTPS polling as the initial transport; no third-party notification service is necessary for an in-app inbox.
- Optional later self-hosted WebSocket delivery using open-source Django Channels and an appropriately licensed broker, only after operational review.
- Android system notifications, if added later, use an open-source Flutter local notification library after dependency/license verification. This does not itself provide reliable closed-app remote push.

## Disallowed without a new explicit decision
- Firebase Cloud Messaging, proprietary push gateways, paid SaaS notification providers, closed-source SDKs, analytics/telemetry services, or undocumented external services.
- Claiming guaranteed closed-app Android push using polling or WebSockets alone. Android background execution restrictions require a separately verified delivery design.

## Smallest next implementation slice
1. Validate current InboxApi route assumptions against the actual backend before enabling any requests in the UI.
2. Add deterministic model and API adapter tests, run Flutter analyze and targeted tests.
3. Introduce a read-only inbox behind an off-by-default capability flag only after a working backend endpoint exists.
4. Keep the existing derived-alert screen unchanged until the server inbox has verified parity.

## Security and release gates
- Server-side recipient authorization, cross-account isolation, TLS, logout cleanup, and privacy-safe payloads are mandatory.
- No credentials or push tokens in GitHub source or logs.
- Every third-party dependency must have an OSI-approved license and its license obligations recorded before addition.
- No merge, tag, signing, deployment or release as part of this branch.
