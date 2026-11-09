package app.fluo.fluo

import android.content.Context
import android.content.SharedPreferences
import java.io.File

/** Small state shared by the channel and the service. */
class CapturePrefs(context: Context) {
    private val p: SharedPreferences =
        context.applicationContext.getSharedPreferences("fluo_capture", Context.MODE_PRIVATE)
    private val appContext = context.applicationContext

    /** Highest gallery id already seen. Only newer rows are considered. */
    var lastId: Long
        get() = p.getLong("last_id", 0L)
        set(v) = p.edit().putLong("last_id", v).apply()

    /** True between start and stop, so a system restart of the service knows. */
    var watching: Boolean
        get() = p.getBoolean("watching", false)
        set(v) = p.edit().putBoolean("watching", v).apply()

    /** Whether we ever showed the permission prompt (to spot "don't ask again"). */
    var asked: Boolean
        get() = p.getBoolean("asked", false)
        set(v) = p.edit().putBoolean("asked", v).apply()

    val inbox: File
        get() = File(appContext.filesDir, "inbox").also { it.mkdirs() }
}
