package app.fluo.fluo

import android.content.Context
import android.provider.MediaStore

object Gallery {
    /** Highest image id in the gallery now, or 0 if empty or unreadable. */
    fun maxId(context: Context): Long = try {
        context.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Images.Media._ID),
            null, null, "${MediaStore.Images.Media._ID} DESC LIMIT 1",
        )?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
    } catch (e: SecurityException) {
        0L
    }
}
