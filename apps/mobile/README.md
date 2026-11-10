# ParkLink Mobile

Flutter mobile application for ParkLink. This snapshot also contains legacy transport features inherited from the original application.

## Setup

```sh
flutter pub get
flutter run --dart-define=PARKLINK_API_URL=http://localhost:3000
```

Firebase configuration files and signing credentials are not included. Supply your own configuration if you need Firebase. Legacy Google Maps functionality requires `--dart-define=GOOGLE_MAPS_API_KEY=...` with your own restricted key.

The complete integrated workspace, backend services, and deployment configuration are available in [parklink-platform](https://github.com/1ASI0728-2620-16363-ParkLink/parklink-platform).
