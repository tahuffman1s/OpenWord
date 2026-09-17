package com.openword.openword

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The Android half of the update check.
 *
 * Dart downloads the release; this hands the file to the system package
 * installer, which asks the reader to confirm before anything is installed.
 * Nothing here installs silently — a sideloaded app cannot, and should not.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "openword/updates"
        const val APK_TYPE = "application/vnd.android.package-archive"
    }

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
        try {
            // Android O and later asks each app separately for permission to
            // install; send the reader to that screen rather than failing.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.error(
                    "not-allowed",
                    "Allow OpenWord to install unknown apps, then try again",
                    null,
                )
                return
            }

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
