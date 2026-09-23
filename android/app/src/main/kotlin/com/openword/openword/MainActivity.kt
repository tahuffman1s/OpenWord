package com.openword.openword

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * The Android half of the update check.
 *
 * Dart downloads the release; this hands the file to the system package
 * installer, which asks the reader to confirm before anything is installed.
 * Nothing here installs silently — a sideloaded app cannot, and should not.
 *
 * Two things are worth knowing, because both of them used to look like the
 * app being broken:
 *
 *  - Permission to install has to be granted per app on Android 8 and later.
 *    Asking for it opens a settings screen, which means leaving the app; the
 *    install is held until the reader comes back, and then goes ahead by
 *    itself rather than reporting a failure.
 *  - Android refuses to replace an installed app with one signed by a
 *    different key, and says only "App not installed". The signatures are
 *    compared here first, so the app can explain what is wrong and offer to
 *    remove the old copy.
 *
 * It is an [AudioServiceActivity] rather than a plain FlutterActivity so
 * that reading aloud can go on with the screen off: the media service and
 * this activity share one Flutter engine, and the channel above is set up
 * on that engine the same as ever.
 */
class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "openword/updates"
        const val APK_TYPE = "application/vnd.android.package-archive"

        /** Coming back from the "install unknown apps" settings screen. */
        const val REQUEST_INSTALL_PERMISSION = 4201
    }

    /** The install waiting on permission, and the caller waiting on it. */
    private var pendingInstall: File? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Downloads land in the one directory file_paths.xml
                    // shares, so the installer can be handed a content:// URI
                    // for them.
                    "updateDirectory" -> {
                        val directory = File(cacheDir, "updates")
                        directory.mkdirs()
                        result.success(directory.absolutePath)
                    }

                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no-path", "No file to install", null)
                        } else {
                            install(File(path), result)
                        }
                    }

                    // Offered when the signatures do not match: the old copy
                    // has to go before the new one can be installed.
                    "uninstall" -> {
                        uninstall(result)
                    }

                    "open" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("no-url", "No link to open", null)
                        } else {
                            open(url, result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun install(file: File, result: MethodChannel.Result) {
        if (!file.exists()) {
            result.error("missing", "The download is no longer there", null)
            return
        }

        // Android O and later asks each app separately for permission to
        // install. Hold the install, open that screen, and carry on when the
        // reader comes back with it granted.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingInstall = file
            pendingResult = result
            try {
                startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                    REQUEST_INSTALL_PERMISSION,
                )
            } catch (error: Exception) {
                pendingInstall = null
                pendingResult = null
                result.error(
                    "no-permission-screen",
                    "Allow OpenWord to install unknown apps in Settings, " +
                        "then tap Install again",
                    null,
                )
            }
            return
        }

        val mismatch = signatureMismatch(file)
        if (mismatch != null) {
            result.error("signature-mismatch", mismatch, null)
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.updates",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, APK_TYPE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("install-failed", error.message, null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_INSTALL_PERMISSION) return

        val file = pendingInstall
        val result = pendingResult
        pendingInstall = null
        pendingResult = null
        if (file == null || result == null) return

        val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
        if (allowed) {
            // The permission is granted; go straight on with the install the
            // reader asked for before being sent to Settings.
            install(file, result)
        } else {
            result.error(
                "not-allowed",
                "OpenWord is not allowed to install apps, so the update " +
                    "cannot be installed from here. The release page has the " +
                    "same file.",
                null,
            )
        }
    }

    /**
     * Compares the certificate of the downloaded APK with the one the
     * installed app was signed by, and describes the difference if there is
     * one. Null means the install can go ahead.
     *
     * A release signed with a different key than the installed copy cannot
     * replace it: the installer refuses with nothing but "App not installed".
     */
    private fun signatureMismatch(file: File): String? {
        val installed = certificates(packageName)
        val downloaded = archiveCertificates(file)
        if (installed.isEmpty() || downloaded.isEmpty()) return null
        if (installed.intersect(downloaded).isNotEmpty()) return null
        return "This release was signed with a different key than the copy " +
            "you have (${installed.first().take(8)} installed, " +
            "${downloaded.first().take(8)} in the download), and Android " +
            "will not replace an app with one signed by another key. " +
            "Removing the copy you have and installing this one keeps your " +
            "bookmarks and notes off the device, so back them up first if " +
            "you want them."
    }

    private fun certificates(packageName: String): Set<String> = try {
        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        fingerprints(packageManager.getPackageInfo(packageName, flags))
    } catch (error: Exception) {
        emptySet()
    }

    private fun archiveCertificates(file: File): Set<String> = try {
        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        if (info == null) emptySet() else fingerprints(info)
    } catch (error: Exception) {
        emptySet()
    }

    private fun fingerprints(info: android.content.pm.PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signing = info.signingInfo
            when {
                signing == null -> emptyArray()
                signing.hasMultipleSigners() -> signing.apkContentsSigners
                else -> signing.signingCertificateHistory
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }

        val digest = MessageDigest.getInstance("SHA-256")
        return signatures
            .filterNotNull()
            .map { signature ->
                digest.digest(signature.toByteArray()).joinToString("") {
                    "%02x".format(it)
                }
            }
            .toSet()
    }

    /** Opens the system's uninstall prompt for OpenWord itself. */
    private fun uninstall(result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(Intent.ACTION_DELETE, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("uninstall-failed", error.message, null)
        }
    }

    private fun open(url: String, result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("open-failed", error.message, null)
        }
    }
}
