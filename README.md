# Scorecard (Cricket + Football) – offline

## One-time setup
1. Install Flutter SDK: https://docs.flutter.dev/get-started/install
2. In this folder run:
   flutter create --platforms=android,windows .
   (keeps lib/ and pubspec.yaml; generates android/ and windows/ folders)
3. flutter pub get

## Run
flutter run -d windows
flutter run -d <android-device>

## Build
Android APK:   flutter build apk --release
   -> build/app/outputs/flutter-apk/app-release.apk
Windows EXE:   flutter build windows --release
   -> build/windows/x64/runner/Release/
   (needs Visual Studio with "Desktop development with C++")

## Notes
- Cricket: player names are typed once per innings (openers, new batters, each over's bowler).
- PDF button opens the print/preview dialog -> "Save as PDF" (Windows: Microsoft Print to PDF).
