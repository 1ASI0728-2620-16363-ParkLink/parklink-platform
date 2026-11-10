# Repository audit and adaptation decisions

## Verified sources

| Source | Branch / commit | Purpose |
|---|---|---|
| Maximoff19/PANAMERICANOS-MOBILE | main / 6fb9f1b6ecf3204d95ffe02ec627ec0494ba10fc | Actual mobile implementation, cloned intact in apps/mobile |
| 1ASI0728-2620-16363-ParkLink/ParkLink-Report | develop / b67ce266d87270b490f6411feddd67db89622ad5 | Requirements and architecture, reference/ParkLink-Report |

Both repositories were accessible through Git. The report is NOT backend code. Links in chapter V to a previous backend are background references, not proof of this implementation.

## Mobile inventory and reuse matrix

Flutter 3.44 / Dart 3.12.1; Material 3; manual role navigation; ChangeNotifier MVVM; repository/service data layer. Dependencies include flutter_map 8, latlong2, geolocator, http, flutter_secure_storage, SQLite, image_picker, Firebase Messaging and local notifications.

| Existing implementation | ParkLink use | Treatment |
|---|---|---|
| app_theme.dart | Shared dark theme, cards, inputs and buttons | Preserve 28px cards and 20px controls; apply documented palette and contrast |
| app_bottom_nav.dart | Role navigation | Reuse animated indicator, motion preferences, semantics and floating white bar |
| app_bottom_sheet.dart | Details, reservation and publication | Reuse light sheet, drag handle and 34px top corners |
| LoginScreen | Login / self-registration | Retain background image, introduction and white bottom card composition |
| ClientShellScreen / ClientRequestSheet | Parking map and booking | Reuse map-led shell and sheet interaction; replace taxi-specific state, not its business names blindly |
| flutter_map / map_theme.dart | Parking markers and map tiles | Retain tile provider and map behavior; add required attribution and list alternative |
| Service detail / summary / history | Reservation states / payment history | Replace transport models with parking-specific repository and view model |
| Admin dashboard cards | Owner spaces, agenda and income | Reuse surface tokens and visual grouping; not transport operational permissions |
| SessionStore | Secure credential storage pattern | New namespaced ParkLink session; never reuse a transport JWT |
| GPS tracking / offline service permits / transport sync | Not applicable | Keep original source as provenance; do not start background taxi workflows in ParkLink |
| vehicle_top / van / SUV / bus assets | Not parking inventory | Preserve source assets, do not show them as available spaces |
| Report chapter VI brand exports | ParkLink brand | Use actual supplied logo where available; no invented replacement brand |

## Contradictions resolved

- Report chapter III sometimes calls a hold a confirmation. Chapters IV–V explicitly distinguish them: only a matching payment outcome on an unexpired hold can confirm.
- Report chapter V uses Redis for Discovery; the request explicitly asks to evaluate PostGIS and independent PostgreSQL. Use a durable PostGIS read projection with event revisions; Redis remains an optional disposable cache. This is a documented deviation, not a new authority over reservations.
- Original accent is blue and some buttons use white text. ParkLink turquoise requires black text (report 6.1.1); preserve shapes and motion, fix contrast.
- Original app is a transport-control application, not simply a taxi marketplace. Driver device registration, offline trip execution and tracking cannot be reused as parking booking semantics.
- Late cancellation fee is unspecified. Fail closed for late cancellation until an explicit configured policy exists; show the policy before booking. Never silently invent a percentage.
- Web monitoring is query-only. Space editing, availability changes and booking commands remain mobile operations.

## Evidence boundaries

No screenshots or device usability assessment have been performed at audit time. Installed Flutter matches the source SDK. Docker CLI exists but its daemon was unavailable at initial inspection. Source inspection does not prove deployment, payments, capacity, latency or accessibility acceptance.
