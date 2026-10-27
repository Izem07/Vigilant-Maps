# Vigilant – setup

## 1. Generate the native project folders
From this directory (after fixing your Flutter SDK):

```
flutter create --platforms=ios --org com.yourname .
flutter pub get
```

`flutter create .` keeps the existing `lib/` and `pubspec.yaml`.

## 2. Add the alert sound
Put an MP3 at `assets/sounds/radar_alert.mp3`. The build fails if that folder is missing.

## 3. Info.plist (`ios/Runner/Info.plist`, inside `<dict>`)

```xml
<!-- From the apple_maps_flutter README. Old Flutter versions needed it; current ones ignore it, so it's harmless. -->
<key>io.flutter.embedded_views_preview</key>
<true/>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Vigilant uses your location for turn-by-turn navigation and to warn you of reported speed traps.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Vigilant keeps warning you of reported speed traps while navigating in the background.</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>audio</string>
</array>
```

Also set `platform :ios, '13.0'` (or higher) in `ios/Podfile`.

## 4. Firebase
1. Create a project in the Firebase console and enable Firestore.
2. Add an iOS app with the same bundle ID and download `GoogleService-Info.plist` into `ios/Runner/` (add it to the Runner target in Xcode).
3. Deploy the rules and cleanup function:
   ```
   firebase deploy --only firestore:rules,functions
   ```

## 5. Run (needs a Mac with Xcode and a physical iPhone)
```
flutter run -d <your-iphone>
```

Long-press the map to route somewhere. Tap the green police button to report a trap.

## Before release
- `router.project-osrm.org` is a demo server and its policy doesn't allow production use. Self-host OSRM and update `_baseUrl` in `lib/services/router_service.dart`.
