# Fluo privacy policy

Draft for the Play Console privacy-policy URL. Publish this text on a page you control. Fill in the two placeholders marked TODO first (operator name, contact email), and the effective date.

Effective date: TODO
Operator: TODO (name or company)
Contact: TODO (email)

## The short version
Fluo keeps everything on your phone. There are no accounts and no cloud. Fluo does not collect, store on a server, or sell your data, and it has no ads or analytics. Nothing leaves your phone except what you choose to share.

## What Fluo stores, and where
- **Screenshots you review.** While a review session is on, Fluo copies new screenshots into its own private folder on your phone. Your original files in the gallery are not changed.
- **Your work.** Albums, captions, notes, crop and mark-up data, and your settings are saved in a database on your phone.
- Both are kept only in Fluo's private storage on the device. Fluo has no server to send them to. Fluo does not open internet connections: the app does not request the Android internet permission.

## Permissions, and why
- **Photos and media (`READ_MEDIA_IMAGES`, and on Android 14 `READ_MEDIA_VISUAL_USER_SELECTED`; `READ_EXTERNAL_STORAGE` on Android 12 and older):** to find new screenshots while a review session is on. Fluo does not browse or upload your other photos.
- **Notifications:** to show the notice that a review session is watching for screenshots.
- **Foreground service:** keeps that watching going while you use another app. It runs only while a session is on.
- **Network state:** only to ask Android whether your connection is metered, for the "Wi-Fi only" update setting. This is not internet access.

## What leaves your phone
Only what you choose to share. When you export (a Claude pack, PDF, long image or images), Fluo builds the files on your phone and opens the Android share sheet. You pick the app or person that receives them, and what they do with the files is covered by their own policies. Redactions you draw are baked into exported images. Original, unedited screenshots are left out of exports unless you switch that on.

## Updates
Fluo can use Google Play's in-app updates when it was installed from Google Play. That check is made by Google Play, under Google's privacy policy, not by Fluo code.

## Deleting your data
Delete an album or a screenshot in Fluo to remove it. Uninstalling Fluo removes all of its data from your phone. Because nothing is stored elsewhere, there is nothing to request from us.

## Children
Fluo is a professional tool and is not directed at children under 13.

## Changes
If this policy changes, the new version will be published at the same address with a new effective date.
