
---

The Android APK is signed with Flutter's debug key, which is enough to
sideload but not to publish on Play. Install it with
`adb install OpenWord-*-android.apk`, or enable installation from unknown
sources on the device.

iOS and macOS builds are not attached because they need an Apple signing
identity; build them yourself with `flutter build ipa` / `flutter build macos`.

Scripture text is the World English Bible (public domain), downloaded by the
app on first launch, not bundled here.
