package app.fluo.fluo

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.File

/**
 * Receives screenshots sent to Fluo from the system share sheet (the fallback
 * for when automatic detection misses one). Each image is copied into a private
 * folder at once; Dart then asks which album it belongs in.
 */
object ShareIntake {
    private const val TAG = "FluoShare"

    fun dir(context: Context): File =
        File(context.applicationContext.filesDir, "shared").also { it.mkdirs() }

    /** Copies every image in a SEND or SEND_MULTIPLE intent. Returns how many were stored. */
    fun handle(context: Context, intent: Intent?): Int {
        if (intent == null) return 0
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return 0
        val uris = uris(intent)
        var stored = 0
        val stamp = System.currentTimeMillis()
        uris.forEachIndexed { i, uri ->
            val mime = try { context.contentResolver.getType(uri) } catch (e: Exception) { null }
            if (mime != null && !mime.startsWith("image/")) return@forEachIndexed
            val ext = InboxName.extFor(mime, uri.lastPathSegment)
            val target = File(dir(context), "shared_${stamp}_$i.$ext")
            val tmp = File(dir(context), target.name + ".part")
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    tmp.outputStream().use { out -> input.copyTo(out) }
                } ?: return@forEachIndexed
                if (tmp.renameTo(target)) stored++
            } catch (e: Exception) {
                Log.w(TAG, "Could not copy shared image $uri", e)
                tmp.delete()
            }
        }
        // Do not process the same intent again if the activity is recreated.
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.clipData = null
        return stored
    }

    @Suppress("DEPRECATION")
    private fun uris(intent: Intent): List<Uri> {
        val out = ArrayList<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            val u = if (Build.VERSION.SDK_INT >= 33)
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (u != null) out.add(u)
        } else {
            val l = if (Build.VERSION.SDK_INT >= 33)
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (l != null) out.addAll(l)
        }
        if (out.isEmpty()) {
            val cd = intent.clipData
            if (cd != null) for (i in 0 until cd.itemCount) cd.getItemAt(i).uri?.let { out.add(it) }
        }
        return out
    }

    /** Files waiting for an album, oldest first. */
    fun waiting(context: Context): List<File> =
        (dir(context).listFiles() ?: emptyArray())
            .filter { it.isFile && !it.name.endsWith(".part") }
            .sortedBy { it.name }
}
