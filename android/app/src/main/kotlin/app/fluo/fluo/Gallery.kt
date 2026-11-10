package app.fluo.fluo

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore

object Gallery {
    /**
     * Highest image id in the gallery now, or 0 if empty or unreadable.
     *
     * Do not put `LIMIT` in the sort order: Android 11+ rejects it with an
     * IllegalArgumentException, which used to make starting a session fail.
     */
    fun maxId(context: Context): Long = try {
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(MediaStore.Images.Media._ID)
        val cursor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val args = Bundle().apply {
                putStringArray(
                    android.content.ContentResolver.QUERY_ARG_SORT_COLUMNS,
                    arrayOf(MediaStore.Images.Media._ID),
                )
                putInt(
                    android.content.ContentResolver.QUERY_ARG_SORT_DIRECTION,
                    android.content.ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
                )
                putInt(android.content.ContentResolver.QUERY_ARG_LIMIT, 1)
            }
            context.contentResolver.query(uri, projection, args, null)
        } else {
            context.contentResolver.query(uri, projection, null, null, "${MediaStore.Images.Media._ID} DESC")
        }
        cursor?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
    } catch (e: SecurityException) {
        0L
    }
}
