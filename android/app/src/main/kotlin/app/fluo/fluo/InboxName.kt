package app.fluo.fluo

/**
 * Metadata travels in the inbox file name, so a screenshot copied while the
 * Flutter engine is not running needs no side files:
 * `<mediaId>_<capturedAtMs>_<width>x<height>.<ext>`.
 */
data class InboxName(
    val mediaId: Long,
    val capturedAtMs: Long,
    val width: Int,
    val height: Int,
    val ext: String,
) {
    fun fileName(): String = "${mediaId}_${capturedAtMs}_${width}x$height.$ext"

    companion object {
        private val pattern = Regex("""^(\d+)_(\d+)_(\d+)x(\d+)\.([a-z0-9]{1,5})$""")

        /** Null for temp files (`.part`) and anything that is not ours. */
        fun parse(name: String): InboxName? {
            val m = pattern.matchEntire(name) ?: return null
            val (id, at, w, h, ext) = m.destructured
            return InboxName(id.toLong(), at.toLong(), w.toInt(), h.toInt(), ext)
        }

        /** png, jpg or webp from the mime type, else from the file name. */
        fun extFor(mime: String?, displayName: String?): String {
            when (mime?.lowercase()) {
                "image/png" -> return "png"
                "image/jpeg" -> return "jpg"
                "image/webp" -> return "webp"
            }
            val e = displayName?.substringAfterLast('.', "")?.lowercase().orEmpty()
            return if (Regex("[a-z0-9]{1,5}").matches(e)) e else "png"
        }
    }
}
