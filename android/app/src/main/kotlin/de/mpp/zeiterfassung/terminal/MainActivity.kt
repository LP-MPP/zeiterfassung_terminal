package de.mpp.zeiterfassung.terminal

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "de.mpp.zeiterfassung/updates"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionInfo" -> result.success(versionInfo())
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallPermissionSettings" -> openInstallPermissionSettings(result)
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Kein APK-Pfad übergeben.", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun versionInfo(): Map<String, Any> {
        @Suppress("DEPRECATION")
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionCode" to versionCode,
            "versionName" to (info.versionName ?: "")
        )
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(true)
            return
        }

        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("settings_failed", "Update-Freigabe konnte nicht geöffnet werden.", error.message)
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        try {
            if (!canInstallPackages()) {
                result.error("permission_required", "Installationsfreigabe fehlt.", null)
                return
            }

            val downloadedApk = File(path).canonicalFile
            if (!downloadedApk.exists() || !downloadedApk.isFile || downloadedApk.length() <= 0L) {
                result.error("invalid_apk", "Die heruntergeladene APK ist ungültig.", null)
                return
            }

            // Dart's systemTemp path differs between some Android/Samsung builds.
            // Normalize the verified download into our known FileProvider folder
            // instead of rejecting an otherwise valid app-private cache path.
            val updateDirectory = File(cacheDir, "updates")
            if (!updateDirectory.exists() && !updateDirectory.mkdirs()) {
                result.error("cache_failed", "Update-Ordner konnte nicht erstellt werden.", null)
                return
            }
            val apk = File(updateDirectory, "zeiterfassung-terminal.apk").canonicalFile
            if (downloadedApk.path != apk.path) {
                downloadedApk.copyTo(apk, overwrite = true)
            }

            if (!apk.exists() || !apk.isFile || apk.length() != downloadedApk.length()) {
                result.error("copy_failed", "Die geprüfte APK konnte nicht vorbereitet werden.", null)
                return
            }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk
            )
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                data = uri
                clipData = ClipData.newRawUri("Zeiterfassung Update", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("install_failed", "Android-Installation konnte nicht gestartet werden.", error.message)
        }
    }
}
