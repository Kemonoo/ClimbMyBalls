package app.hibi.climb

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Updates (lib/update/): may Climb install apps, and opening the installer. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "climb/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallApps" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "openInstallAppsSettings" -> {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "installApk" -> {
                    val uri = FileProvider.getUriForFile(this, "$packageName.updates", java.io.File(call.argument<String>("path")!!))
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
