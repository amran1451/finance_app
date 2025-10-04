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

## Troubleshooting: Unable to update Dart SDK on Windows

If the Flutter tool shows repeated errors like `Unable to update Dart SDK` or
PowerShell reports that `Rename-Item` cannot rename the
`C:\src\flutter\bin\cache\dart-sdk` folder, the cached SDK is usually locked
by another process. To recover:

1. Close Visual Studio Code, Android Studio, terminals, and any running Dart or
   Flutter processes.
2. Open a new **elevated** PowerShell window (Run as administrator).
3. Delete the stale cache folder manually:
   ```powershell
   Remove-Item "C:\src\flutter\bin\cache\dart-sdk" -Recurse -Force
   ```
4. Rerun `flutter doctor` (or the original command). Flutter will download a
   fresh Dart SDK into the cache and the update should complete successfully.

If the deletion is blocked, reboot Windows to release file locks and repeat the
steps above.

## Dependency maintenance

After updating dependencies, run:

```bash
flutter pub get
# При проблемах с кешем: flutter pub cache repair
```

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

## Регрессионные проверки категорий

1. Запустите приложение, откройте управление категориями и создайте новую категорию или папку.
2. Создайте операцию, выбрав добавленную категорию, и убедитесь, что запись успешно сохраняется.
3. Перезапустите приложение: после повторного входа категория и созданная операция должны отображаться и использоваться без дополнительных действий.
