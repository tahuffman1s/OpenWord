import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Android will only replace an installed app with one signed
// by the same key, so a release has to be signed with a key that outlives the
// machine that built it. The key is never in the repository: it comes from
// android/key.properties locally, or from the environment in CI, where the
// workflow writes it out of a secret.
//
// Without one the build falls back to Flutter's debug key — fine for
// `flutter run`, useless for an update, because that keystore is generated
// afresh on every machine.
val keystoreProperties = Properties().apply {
    val properties = rootProject.file("key.properties")
    if (properties.exists()) properties.inputStream().use { load(it) }
}

fun signingValue(property: String, variable: String): String? =
    (keystoreProperties.getProperty(property) ?: System.getenv(variable))
        ?.takeIf { it.isNotBlank() }

val releaseKeystore: File? = signingValue("storeFile", "OPENWORD_KEYSTORE")
    ?.let { path -> file(path).takeIf { it.exists() } }
val releaseStorePassword = signingValue("storePassword", "OPENWORD_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "OPENWORD_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "OPENWORD_KEY_PASSWORD")
val hasReleaseKey = releaseKeystore != null &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

android {
    namespace = "com.openword.openword"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.openword.openword"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = releaseKeystore
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "OpenWord: no release key, signing with the debug key. " +
                        "An APK signed this way cannot update an installed " +
                        "copy — see the Releases section of the README.",
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // FileProvider, for handing a downloaded release to the system installer.
    implementation("androidx.core:core-ktx:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
