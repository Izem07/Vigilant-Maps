<p align="center">
  <img src="assets/icon/icon.jpg" width="128" alt="Vigilant icon">
</p>

<h1 align="center">Vigilant</h1>

<p align="center">
  Turn-by-turn navigation with live, crowdsourced police and speed trap alerts.<br>
  Built with Flutter for iOS. Runs entirely on free services.
</p>

---

## Features

- **Apple Maps**: native iOS map rendering, no API key needed
- **Address search**: find places and addresses through OpenStreetMap (Nominatim)
- **Turn-by-turn navigation**: shows the next turn and the distance to it, and recalculates the route if you go off course
- **Crowdsourced trap reports**: tap once to report police at your location, and every nearby driver sees it live
- **Proximity alerts**: an on-screen warning and a chime when a reported trap is within about half a mile
- **Self-expiring reports**: reports disappear after 30 minutes

## How to use

| Action | How |
|---|---|
| Set a destination | Type in the search bar and press Enter, then tap a result. Or long-press the map. |
| Report police | Tap the green 🚓 button |
| See a report's details | Tap a pin on the map |
| End navigation | Tap the red button in the bottom-left corner |

## Tech stack

| Layer | Technology | Cost |
|---|---|---|
| App | Flutter / Dart | Free |
| Map | [`apple_maps_flutter`](https://pub.dev/packages/apple_maps_flutter) (MapKit) | Free |
| Location | [`geolocator`](https://pub.dev/packages/geolocator) | Free |
| Routing | [OSRM](https://project-osrm.org/) | Free |
| Search | [Nominatim](https://nominatim.org/) (OpenStreetMap) | Free |
| Trap database | Firebase Cloud Firestore | Free tier |
| iOS builds | GitHub Actions (macOS runner) | Free for public repos |

### Finding nearby traps cheaply

Each report is tagged with a 5-character **geohash**, a grid square about 5 km across. The app listens only to the driver's square and the 8 around it, an area about 15 km wide. It switches squares as the driver moves. Database reads stay small, so the app fits within Firebase's free tier.

## Project structure

```
lib/
├── main.dart                     # Starts Firebase and launches the app
├── screens/
│   └── map_screen.dart           # Map, search, navigation and alert UI
└── services/
    ├── router_service.dart       # OSRM routes and turn instructions
    ├── search_service.dart       # Nominatim address search
    ├── radar_service.dart        # Firestore trap reports and nearby queries
    └── geohash.dart              # Geohash encoder and neighbour lookup
assets/
├── icon/icon.jpg                 # App icon
└── sounds/                       # radar_alert.mp3 goes here
functions/index.js                # Scheduled job that deletes expired reports
firestore.rules                   # Database security rules
.github/workflows/build-ios.yml   # Builds an unsigned .ipa on every push
```

## Building and installing

You don't need a Mac. GitHub Actions builds the app on every push to `main`.

1. Open the [Actions tab](../../actions) and select the latest successful run.
2. Download the **Vigilant-ipa** file and unzip it.
3. Install `Vigilant.ipa` on your iPhone with [Sideloadly](https://sideloadly.io/) (Windows or macOS) or [AltStore](https://altstore.io/).

> With a free Apple ID, sideloaded apps expire after 7 days and must be reinstalled.

### Building locally (needs macOS and Xcode)

```bash
flutter create --platforms=ios --org com.vigilant .
cp GoogleService-Info.plist ios/Runner/
flutter pub get
dart run flutter_launcher_icons
flutter run
```

See [`SETUP.md`](SETUP.md) for the `Info.plist` keys and the Podfile setting.

## Firebase setup

1. Create a Firebase project, enable **Cloud Firestore**, and register an iOS app with the bundle ID `com.vigilant.app`.
2. Put the downloaded `GoogleService-Info.plist` in the repo root. CI copies it into the iOS project.
3. Deploy the security rules and cleanup function:
   ```bash
   firebase deploy --only firestore:rules,functions
   ```
   The scheduled cleanup function needs the Blaze plan. Without it, the app still hides reports older than 30 minutes.

## Roadmap

- [ ] Alert sound (`assets/sounds/radar_alert.mp3`)
- [ ] Report types: speed camera and speed trap, alongside police
- [ ] Upvote or dismiss reports ("still there?")
- [ ] Voice directions
- [ ] Self-hosted OSRM for public release

## Notes

- The public OSRM and Nominatim servers are for light, non-commercial use. Self-host both before any wide release.
- Nominatim allows at most 1 request a second and doesn't allow search-as-you-type, so searches run only when you press Enter.
- Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors.
