
---

Every translation is bundled with the app — the World English Bible, the
Berean Standard Bible and the World English Bible, British Edition, all public
domain — along with the book introductions and the maps. Nothing is
downloaded to read it.

From 1.5.0 the app does one thing over the network: it asks GitHub, once a
day, whether a newer release is out, and on Android can fetch and install it
for you. That is the only reason it now asks for the internet and
install-packages permissions, and it can be switched off in Settings, after
which nothing reaches the network at all.

Install the Android APK with `adb install OpenWord-*-android.apk`, or allow
installation from unknown sources on the device. It is not published on Play.

iOS and macOS builds are not attached because they need an Apple signing
identity; build them yourself with `flutter build ipa` / `flutter build macos`.
