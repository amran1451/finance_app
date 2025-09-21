# finance_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android build commands

Execute the following commands locally to produce a universal debug APK with 32-bit and 64-bit support:

```bash
flutter clean
flutter pub get

# Universal debug APK (includes arm + arm64)
flutter build apk --debug --target-platform=android-arm,android-arm64

# Or split per ABI (grab the arm64-v8a APK for modern devices)
# flutter build apk --split-per-abi

adb uninstall com.example.finance_app
adb install build/app/outputs/flutter-apk/app-debug.apk
```
