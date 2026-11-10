# ParkLink

A working local parking-marketplace vertical slice, adapted from the original Flutter PANAMERICANOS-MOBILE application. Eight independent NestJS services own eight independent PostgreSQL databases. RabbitMQ separates durable reservation commands from confirmed domain events. This is **not a production-complete delivery**; known gaps are listed below.

## Start locally

Prerequisites: Docker Desktop with sufficient disk/RAM, Node 22, and Flutter 3.44.1 / Dart 3.12.1 for mobile. Keep at least 10 GB free for native builds and container caches.

```sh
npm ci
node scripts/configure-local.mjs
docker compose up -d --build --wait
node scripts/seed-rich.mjs
```

`configure-local.mjs` creates random local credentials and refuses to overwrite an existing `.env`. For an existing setup without the new isolated OpenCode password, run `node scripts/configure-copilot.mjs` instead. Never print or commit the `.env` file.

| Component | Local address |
|---|---|
| Public API Gateway | http://localhost:3000 |
| Read-only owner dashboard | http://localhost:5173 |
| RabbitMQ management | http://localhost:15672 (credentials from private `.env`) |
| OpenCode, databases and internal services | Private Compose network only |

The rich seed creates a verified local client account `cliente@parklink.test`. Its randomly generated password is in the ignored, mode-0600 `.local/demo-accounts.json`; no default production password is shipped. Fixtures are explicitly fictitious and all payments are sandbox. Re-running the seed preserves identifiers and idempotency keys rather than deleting data. See [development data](docs/development-data.md).

## iOS Simulator

From `apps/mobile`, run:

```sh
flutter pub get
flutter run -d YOUR_SIMULATOR_UDID --debug --dart-define=PARKLINK_API_URL=http://localhost:3000
```

The currently used iPhone 18 Pro simulator is `734C0950-B1C9-46AB-AD70-0686E9EA95D8`. Xcode 27 installations may expose DeviceHub instead of Simulator.app. CocoaPods targets below iOS 15 are raised to 15 without lowering higher plugin requirements. No physical-device signing or App Store deployment has been performed.

Android emulator development uses `--dart-define=PARKLINK_API_URL=http://10.0.2.2:3000`. Production builds must use an HTTPS Gateway endpoint. The original transport entry remains in `legacy_transport_main.dart` for provenance and is not launched by ParkLink.

## Copilot

Double-tap the authenticated main screen, or press the labelled sparkle button. Choose an interval, then ask for the closest or cheapest parking space. Search results and all actions use actual services, not invented inventory. Mutations require a separate price/resource-bound confirmation; a hold does not itself charge or confirm a reservation.

The background process is an independent, isolated OpenCode 1.19.5 server using its official SDK. No personal OpenCode settings or credentials are mounted. Only its advertised zero-cost default provider is permitted. **The free provider timed out during live inference checks in this environment**; the UI truthfully identifies guided fallback when this happens. Runtime connectivity and application action flows are tested independently from generative-model availability. See [Copilot](docs/copilot.md) for the persona, permissions, data boundaries and consent protocol.

## Build and test

```sh
npm run build
npm run lint
npm test
npm run test:integration
npm audit --omit=dev
```

Integration tests require the running local Compose stack. They use real HTTP, PostgreSQL and RabbitMQ. Tests create clearly named fixtures; they do not reset production data. The Copilot integration test may spend up to 30 seconds waiting for the free provider before verifying the labelled guided fallback.

From `apps/mobile`:

```sh
flutter analyze
flutter test
```

`node scripts/copilot-smoke.mjs` specifically requires a real OpenCode-generated result and exits nonzero when fallback was used. It must not be described as a passing AI inference test if the free model is unavailable.

## Independent services and deployment preparation

Every service has its own `package.json`, `Dockerfile`, migration directory and `.env.example`. For example:

```sh
npm run build:shared
npm run build -w @parklink/reservation-service
docker compose up -d --build reservation-service
sh scripts/image.sh reservation-service registry.example.com/parklink immutable-commit-tag
```

Image scripts build locally and deliberately do not push or deploy. Services support `node dist/main.js --migrate`; migrations use per-database advisory locks and checksums. The shared packages contain contracts and infrastructure utilities, not shared database entities.

`infrastructure/helm/parklink-service` is a template for one independent Helm release per service, with an existing Secret, migration Job, probes, HPA, PDB and optional Gateway ingress. Configure each service's unique managed PostgreSQL URL and AMQPS connection. Kubernetes examples include namespace/network policy and a three-node RabbitMQ Cluster Operator resource. These templates have not been validated against a live cluster and are not a claim of production readiness.

See [architecture](docs/architecture.md), [RabbitMQ](infrastructure/rabbitmq/README.md), [PostgreSQL operations](infrastructure/postgres/operations.md) and [repository audit/reuse matrix](docs/repository-audit.md).

## Main API contracts

All protected endpoints require `Authorization: Bearer <JWT>`. Amounts are integer PEN céntimos. Dates use RFC3339; the UI presents Lima time. Internal services expose `/health`, `/ready` and `/metrics`. Development Swagger is at each service's internal `/docs`; only the Gateway is a public API entry point.

| Endpoint | Purpose |
|---|---|
| `POST /auth/register`, `/auth/login` | Account and mobile session |
| `POST /auth/monitor-login` | Read-only owner-monitoring session |
| `GET /auth/me` | Authenticated profile |
| `POST /spaces`, `PUT /spaces/:id`, `GET /spaces/mine` | Owner publication/revision |
| `GET /discovery/search` | Geographic query with interval, price, feature and nearest/cheapest sort |
| `POST /reservations/commands/hold\|confirm\|cancel` | Durable acceptance, requires `Idempotency-Key`, returns 202 |
| `GET /operations/:id` | Persisted command result; 202 acceptance does not mean success |
| `GET /reservations/mine`, `/reservations/owner`, `/reservations/:id` | Authorized reservation queries |
| `GET /payments/mine`, `/payments/owner`, `/payments/:id` | Financial state/history |
| `GET /owner/dashboard` | Read-only aggregation, explicitly indicates truncation |
| `/notifications` and `/notifications/preferences` | In-app delivery and preferences |
| `GET /copilot/status`, `POST /copilot/chat` | Runtime status and authenticated dialogue |
| `POST /copilot/propose-hold`, `/copilot/propose-action` | Exact server-generated consent proposal |
| `POST /copilot/confirm/:id`, `GET /copilot/commands/:id` | Human approval and durable action result |

The command/event exchanges and queue contracts are documented in the RabbitMQ guide. Discovery is informational; Reservation always revalidates availability. Free cancellation includes the exact 60-minute boundary. Late fees are intentionally not invented; without configured terms, late cancellation is refused.

## Known gaps before production

- Private photo uploads/object storage, recurring opening hours/blockout editor, paid extensions, profile editing and verified owner onboarding are incomplete.
- Push/email delivery, fiscal receipts, token refresh/revocation and full tactical repository-port separation are incomplete.
- Mercado Pago adapter code is prepared but not provider-certified or tested with real credentials; never treat sandbox transactions as real charges.
- Production mTLS, asymmetric JWT key distribution, least-privilege database runtime/migration roles, broker users and egress policies require completion.
- Metrics above the current 500-row query window are explicitly marked partial; no production load/SLO test is claimed.
- No external deployment, image push, paid AI consumption or real payment was performed.

## Public snapshot notes

This is the integrated workspace for the separately published ParkLink components. Component repositories are snapshots of paths in this workspace and do not independently contain the root npm workspace configuration or shared packages. Use this repository to build and run the full system.

Local environment files, signing credentials, Firebase configuration, and the legacy Google Maps API key are intentionally excluded. Provide your own Firebase configuration and, when using legacy Google Maps features, a restricted `GOOGLE_MAPS_API_KEY` via Flutter `--dart-define`.
