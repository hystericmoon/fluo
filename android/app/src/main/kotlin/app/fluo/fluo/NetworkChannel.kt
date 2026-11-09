package app.fluo.fluo

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "Is the current connection unmetered?" for the Wi-Fi only update setting.
 * Unmetered covers Wi-Fi and Ethernet but not a metered hotspot, which is
 * what "do not use mobile data" really means. Needs only ACCESS_NETWORK_STATE.
 */
class NetworkChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    init {
        MethodChannel(messenger, "app.fluo/network").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "unmetered" -> result.success(isUnmetered())
            else -> result.notImplemented()
        }
    }

    private fun isUnmetered(): Boolean {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }
}
