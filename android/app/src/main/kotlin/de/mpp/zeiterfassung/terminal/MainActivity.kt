package de.mpp.zeiterfassung.terminal

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

            val apk = File(path).canonicalFile
            val cacheRoot = cacheDir.canonicalFile
            if (!apk.exists() || !apk.isFile || !apk.path.startsWith(cacheRoot.path + File.separator)) {
                result.error("invalid_apk", "Die heruntergeladene APK ist ungültig.", null)
                return
            }

            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
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
