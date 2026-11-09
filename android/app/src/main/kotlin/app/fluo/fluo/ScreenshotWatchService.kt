package app.fluo.fluo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentUris
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * Foreground service that watches the gallery while a review session is on.
 * Each new screenshot is copied into the private inbox straight away, so it is
 * safe even if the Flutter side is not running.
 */
class ScreenshotWatchService : Service() {
    private var thread: HandlerThread? = null
    private var observer: ContentObserver? = null
    private lateinit var prefs: CapturePrefs
    private val failures = HashMap<Long, Int>()

    override fun onCreate() {
        super.onCreate()
        prefs = CapturePrefs(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // After a system restart there is no intent. Only carry on if a watch
        // was really running.
        if (intent == null && !prefs.watching) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Never import the whole gallery: with no baseline, start from now.
        if (prefs.lastId == 0L) prefs.lastId = Gallery.maxId(this)
        startInForeground()
        register()
        scan() // catch anything that arrived before the observer was attached
        return START_STICKY
    }

    private fun startInForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Screenshot watching", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Shown while Fluo is watching for new screenshots." }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Fluo is watching for screenshots")
            .setContentText("New screenshots go to your review session.")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun register() {
        if (observer != null) return
        val t = HandlerThread("fluo-screenshot-watch").also { it.start() }
        thread = t
        val o = object : ContentObserver(Handler(t.looper)) {
            override fun onChange(selfChange: Boolean) = scan()
            override fun onChange(selfChange: Boolean, uri: Uri?) = scan()
        }
        contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, o)
        observer = o
    }

    @Synchronized
    private fun scan() {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val projection = buildList {
            add(MediaStore.Images.Media._ID)
            add(MediaStore.Images.Media.DISPLAY_NAME)
            add(MediaStore.Images.Media.MIME_TYPE)
            add(MediaStore.Images.Media.DATE_ADDED)
            add(MediaStore.Images.Media.DATE_TAKEN)
            add(MediaStore.Images.Media.WIDTH)
            add(MediaStore.Images.Media.HEIGHT)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(MediaStore.Images.Media.RELATIVE_PATH)
                add(MediaStore.Images.Media.IS_PENDING)
            } else {
                @Suppress("DEPRECATION") add(MediaStore.Images.Media.DATA)
            }
        }.toTypedArray()

        try {
            contentResolver.query(
                collection, projection, "${MediaStore.Images.Media._ID} > ?",
                arrayOf(prefs.lastId.toString()), "${MediaStore.Images.Media._ID} ASC",
            )?.use { c ->
                val iId = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val iName = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val iMime = c.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
                val iAdded = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
                val iTaken = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
                val iW = c.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
                val iH = c.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
                val iPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    c.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)
                else @Suppress("DEPRECATION") c.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                val iPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    c.getColumnIndexOrThrow(MediaStore.Images.Media.IS_PENDING) else -1

                var captured = false
                while (c.moveToNext()) {
                    val id = c.getLong(iId)
                    // A row still being written: stop here and look again on the
                    // next change. Do not move past it or it would be skipped.
                    if (iPending >= 0 && c.getInt(iPending) == 1) break

                    val name = c.getString(iName)
                    if (ScreenshotFilter.isScreenshot(c.getString(iPath), name)) {
                        val taken = c.getLong(iTaken)
                        val capturedAt = if (taken > 0) taken else c.getLong(iAdded) * 1000
                        val inboxName = InboxName(
                            id, capturedAt, c.getInt(iW), c.getInt(iH),
                            InboxName.extFor(c.getString(iMime), name),
                        )
                        if (copyToInbox(ContentUris.withAppendedId(collection, id), inboxName)) {
                            captured = true
                        } else {
                            val n = (failures[id] ?: 0) + 1
                            failures[id] = n
                            if (n < MAX_COPY_TRIES) break // try again on the next change
                            Log.w(TAG, "Giving up on media $id after $n tries")
                        }
                    }
                    prefs.lastId = id
                }
                if (captured) CaptureBus.notifyCaptured()
            }
        } catch (e: SecurityException) {
            // Access was taken away while watching. Dart notices on resume.
            Log.w(TAG, "Lost photo access", e)
        }
    }

    private fun copyToInbox(uri: Uri, name: InboxName): Boolean {
        val dir = prefs.inbox
        val target = File(dir, name.fileName())
        if (target.exists()) return true
        val tmp = File(dir, name.fileName() + ".part")
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                tmp.outputStream().use { out -> input.copyTo(out) }
            } ?: return false
            tmp.renameTo(target)
        } catch (e: Exception) {
            Log.w(TAG, "Copy failed for $uri", e)
            tmp.delete()
            false
        }
    }

    override fun onDestroy() {
        observer?.let { contentResolver.unregisterContentObserver(it) }
        observer = null
        thread?.quitSafely()
        thread = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "FluoCapture"
        private const val CHANNEL_ID = "fluo_capture"
        private const val NOTIFICATION_ID = 4101
        private const val MAX_COPY_TRIES = 3

        fun start(context: android.content.Context) {
            val i = Intent(context, ScreenshotWatchService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
            else context.startService(i)
        }

        fun stop(context: android.content.Context) {
            context.stopService(Intent(context, ScreenshotWatchService::class.java))
        }
    }
}
