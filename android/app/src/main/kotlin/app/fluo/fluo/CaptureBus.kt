package app.fluo.fluo

import android.os.Handler
import android.os.Looper

/**
 * Lets the watch service tell the Flutter side something new arrived. If the
 * app is not on screen there is no listener, which is fine: the inbox keeps
 * the files and Dart drains it when it next starts or resumes.
 */
object CaptureBus {
    @Volatile
    var listener: (() -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())

    fun notifyCaptured() {
        val l = listener ?: return
        main.post { l() }
    }
}
