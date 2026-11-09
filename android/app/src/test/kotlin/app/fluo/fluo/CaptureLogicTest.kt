package app.fluo.fluo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotFilterTest {
    @Test fun pixelFolder() =
        assertTrue(ScreenshotFilter.isScreenshot("Pictures/Screenshots/", "Screenshot_20261109-120000.png"))

    @Test fun samsungAndXiaomiDcimFolder() {
        assertTrue(ScreenshotFilter.isScreenshot("DCIM/Screenshots/", "20261109_120000.jpg"))
        assertTrue(ScreenshotFilter.isScreenshot("DCIM/Camera/", "Screenshot_2026-11-09-12-00-00-123_com.app.jpg"))
    }

    @Test fun legacyFullPath() =
        assertTrue(ScreenshotFilter.isScreenshot("/storage/emulated/0/Pictures/Screenshots/a.png", "a.png"))

    @Test fun caseInsensitive() = assertTrue(ScreenshotFilter.isScreenshot("pictures/SCREENSHOTS/", "x.png"))

    @Test fun localisedFolders() {
        assertTrue(ScreenshotFilter.isScreenshot("Pictures/Capturas de pantalla/", "x.png"))
        assertTrue(ScreenshotFilter.isScreenshot("Pictures/Bildschirmfotos/", "x.png"))
        assertTrue(ScreenshotFilter.isScreenshot("DCIM/截屏/", "x.png"))
        assertTrue(ScreenshotFilter.isScreenshot("Pictures/スクリーンショット/", "x.png"))
    }

    @Test fun cameraPhotosAreNot() {
        assertFalse(ScreenshotFilter.isScreenshot("DCIM/Camera/", "IMG_20261109_120000.jpg"))
        assertFalse(ScreenshotFilter.isScreenshot("Pictures/WhatsApp/", "IMG-2026-WA0001.jpg"))
    }

    @Test fun nullsAreNotScreenshots() = assertFalse(ScreenshotFilter.isScreenshot(null, null))
}

class InboxNameTest {
    @Test fun roundTrip() {
        val n = InboxName(1234, 1700000000000, 1080, 2400, "png")
        assertEquals("1234_1700000000000_1080x2400.png", n.fileName())
        assertEquals(n, InboxName.parse(n.fileName()))
    }

    @Test fun partFilesAreIgnored() =
        assertNull(InboxName.parse("1234_1700000000000_1080x2400.png.part"))

    @Test fun strangersAreIgnored() {
        assertNull(InboxName.parse("notes.txt"))
        assertNull(InboxName.parse("../1_2_3x4.png"))
        assertNull(InboxName.parse("1_2_3x4.exe-with-dash"))
        assertNull(InboxName.parse(""))
    }

    @Test fun extensionFromMimeThenName() {
        assertEquals("png", InboxName.extFor("image/png", "a.jpg"))
        assertEquals("jpg", InboxName.extFor("image/jpeg", null))
        assertEquals("webp", InboxName.extFor("image/webp", null))
        assertEquals("heic", InboxName.extFor("image/heic", "a.HEIC"))
        assertEquals("png", InboxName.extFor(null, "noext"))
        assertEquals("png", InboxName.extFor(null, "weird.../../x"))
    }
}
