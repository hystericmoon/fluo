package app.fluo.fluo

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge between Dart and the screenshot watcher.
 *
 * Methods: permission, requestPermission, openSettings, start, stop, drain, ack.
 * Events: a `null` ping whenever a new screenshot reached the inbox.
 */
class CaptureChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val prefs = CapturePrefs(activity)
    private var pendingResult: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "app.fluo/capture").setMethodCallHandler(this)
        EventChannel(messenger, "app.fluo/capture/events").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permission" -> result.success(status())
            "requestPermission" -> request(result)
            "openSettings" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "start" -> {
                if (status() != "granted") {
                    result.error("no_access", "Photo access is not granted", null)
                    return
                }
                // Baseline: only screenshots taken from now on count.
                prefs.lastId = Gallery.maxId(activity)
                prefs.watching = true
                ScreenshotWatchService.start(activity)
                result.success(null)
            }
            "stop" -> {
                prefs.watching = false
                ScreenshotWatchService.stop(activity)
                result.success(null)
            }
            "drain" -> result.success(drain())
            "ack" -> {
                ack(call.arguments as? List<*> ?: emptyList<Any>())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---- permission --------------------------------------------------------

    private fun granted(p: String) =
        activity.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun status(): String {
        val sdk = Build.VERSION.SDK_INT
        val ok = when {
            sdk >= 33 -> granted(Manifest.permission.READ_MEDIA_IMAGES)
            else -> granted(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        if (ok) return "granted"
        if (sdk >= 34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)) return "limited"
        val mainPerm = if (sdk >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        // Asked before and the system will not show the prompt again.
        if (prefs.asked && !activity.shouldShowRequestPermissionRationale(mainPerm)) return "permanentlyDenied"
        return "denied"
    }

    private fun request(result: MethodChannel.Result) {
        if (status() == "granted") {
            result.success("granted")
            return
        }
        if (pendingResult != null) {
            result.error("busy", "A permission request is already open", null)
            return
        }
        val perms = buildList {
            when {
                Build.VERSION.SDK_INT >= 34 -> {
                    add(Manifest.permission.READ_MEDIA_IMAGES)
                    add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                }
                Build.VERSION.SDK_INT >= 33 -> add(Manifest.permission.READ_MEDIA_IMAGES)
                else -> add(Manifest.permission.READ_EXTERNAL_STORAGE)
            }
            // Lets the "watching" notification show. Not required to work.
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()
        pendingResult = result
        prefs.asked = true
        activity.requestPermissions(perms, REQUEST_CODE)
    }

    /** Called from MainActivity. */
    fun onPermissionResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingResult?.success(status())
        pendingResult = null
        return true
    }

    // ---- inbox -------------------------------------------------------------

    private fun drain(): List<Map<String, Any>> =
        (prefs.inbox.listFiles() ?: emptyArray())
            .mapNotNull { f -> InboxName.parse(f.name)?.let { f to it } }
            .sortedBy { it.second.capturedAtMs }
            .map { (f, n) ->
                mapOf(
                    "path" to f.absolutePath,
                    "capturedAtMs" to n.capturedAtMs,
                    "width" to n.width,
                    "height" to n.height,
                )
            }

    private fun ack(paths: List<*>) {
        val inbox = prefs.inbox.canonicalFile
        for (p in paths) {
            val f = File(p as? String ?: continue).canonicalFile
            // Only ever delete inside the inbox.
            if (f.parentFile == inbox) f.delete()
        }
    }

    // ---- events ------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        CaptureBus.listener = { events?.success(null) }
    }

    override fun onCancel(arguments: Any?) {
        CaptureBus.listener = null
    }

    fun dispose() {
        CaptureBus.listener = null
        pendingResult = null
    }

    companion object {
        const val REQUEST_CODE = 7410
    }
}
