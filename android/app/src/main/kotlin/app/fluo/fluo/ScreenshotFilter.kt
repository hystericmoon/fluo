package app.fluo.fluo

/**
 * Decides whether a gallery row is a screenshot. Android has no reliable flag,
 * so this is a heuristic on the folder and file name. Kept free of Android
 * classes so it can be unit tested on the JVM.
 */
object ScreenshotFilter {
    // Folder and file names OEMs use. English first, then common localisations.
    private val tokens = listOf(
        "screenshot", "screen shot", "screen_shot", "screen-shot",
        "captura de pantalla", "capturas de pantalla", "captura_de_pantalla",
        "bildschirmfoto", "capture d'écran", "capture d’écran", "captures d'écran",
        "schermafbeelding", "skärmbild", "schermata",
        "截屏", "截图", "スクリーンショット", "스크린샷",
    )

    /** [relativePath] is e.g. "Pictures/Screenshots/" (API 29+) or a full path. */
    fun isScreenshot(relativePath: String?, displayName: String?): Boolean {
        val hay = ((relativePath ?: "") + "/" + (displayName ?: "")).lowercase()
        return tokens.any { hay.contains(it) }
    }
}
