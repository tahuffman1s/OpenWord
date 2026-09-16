
---

Every translation is bundled with the app — the World English Bible, the
Berean Standard Bible and the World English Bible, British Edition, all public
domain. There is no download step and no network access at all, which is why
the Android build asks for no permissions.

The Android APK is signed with Flutter's debug key, which is enough to
sideload but not to publish on Play. Install it with
`adb install OpenWord-*-android.apk`, or enable installation from unknown
sources on the device.

iOS and macOS builds are not attached because they need an Apple signing
identity; build them yourself with `flutter build ipa` / `flutter build macos`.
