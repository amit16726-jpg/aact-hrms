# Android and iPhone apps

The HRMS ships three ways onto a phone. All three use the same server, sign-in, permissions and English / Arabic screens.

| | How people get it | Needs |
|---|---|---|
| **Installable web app** | Open the HRMS address in Chrome (Android) or Safari (iPhone) → account menu → *Install the app on this device* | nothing extra |
| **Android app (APK / AAB)** | APK file shared with staff (allow "install unknown apps"), or Google Play | for Google Play: a Play Console account and a release keystore |
| **iPhone app (IPA)** | TestFlight or the App Store (or ad-hoc for registered devices) | an Apple Developer Program membership (paid, yearly) |

The native apps are built with **Capacitor 8** from the same code (`capacitor.config.json`, folders `android/` and `ios/`).
App id: `om.aact.hrms`, name **AACT HR**, version from `android/app/build.gradle` and the Xcode project (1.12.0).

**The server must be reachable from the phones over HTTPS** — a public address with the firewall open on 443, or the company VPN
on the phones. A phone outside the office cannot reach a server that only answers inside the office network.

## 1. Build with GitHub (recommended — no Android Studio or Mac needed)

1. GitHub → repository → *Settings → Secrets and variables → Actions → Variables* → add:
   - `TEST_SUPABASE_URL` = `https://nbseyccerlzerkmcwknw.supabase.co`, `TEST_SUPABASE_ANON_KEY` = the publishable key of the test project
     (the same values as in Vercel);
   - `PROD_SUPABASE_URL` = the company server address (e.g. `https://hr.aact.om`), `PROD_SUPABASE_ANON_KEY` = `ANON_KEY` from
     `/opt/aact-hrms/supabase/.env` on the server.
2. *Actions → Mobile apps → Run workflow* → choose **test** or **production** → *Run workflow*.
3. When the run is green, open it and download the **Artifacts**:
   - `android-…` → `AACT-HR-<server>-debug.apk` — install on any Android phone (Settings → allow install from this source);
     plus a signed release APK and an `.aab` for Google Play if the keystore secrets are set;
   - `ios-…` → a simulator build (proves the iPhone app compiles), plus `AACT-HR-<server>.ipa` if the Apple signing secrets are set.

### Signed Android release (Google Play)
Create the keystore once and keep it in the company password safe — **losing it means you can never update the app on Play**:
```powershell
keytool -genkeypair -v -keystore aact-hrms-release.keystore -alias aact-hrms -keyalg RSA -keysize 2048 -validity 10000
[Convert]::ToBase64String([IO.File]::ReadAllBytes("aact-hrms-release.keystore")) | Set-Clipboard
```
Add secrets: `ANDROID_KEYSTORE_BASE64` (paste), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`aact-hrms`), `ANDROID_KEY_PASSWORD`.
Upload the `.aab` in Google Play Console (internal testing first).

### Signed iPhone app (TestFlight / App Store)
1. Join the Apple Developer Program (company account).
2. In *Certificates, Identifiers & Profiles*: create the App ID `om.aact.hrms`, an **Apple Distribution** certificate (export it from
   Keychain as `.p12` with a password) and an **App Store** provisioning profile for the App ID (or *Ad Hoc* with the phones' UDIDs).
3. Add secrets: `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISION_PROFILE_BASE64`, `IOS_TEAM_ID`,
   and optionally `IOS_EXPORT_METHOD` (`app-store-connect` default, or `ad-hoc`).
   Base64 on a Mac: `base64 -i cert.p12 | pbcopy`.
4. Run the workflow, download the `.ipa`, upload it with Apple's **Transporter** app to App Store Connect → TestFlight.
   Create the app record in App Store Connect first (name, bundle id `om.aact.hrms`, privacy details).

## 2. Build on your own computer

```powershell
copy .env.mobile.example .env.mobile.local     # then edit the address and key
npm ci
npm run mobile:android                          # builds, copies into android/ and opens Android Studio
```
In Android Studio: *Build → Build App Bundle(s) / APK(s) → Build APK(s)*. Needs Android Studio (JDK 21 included).

iPhone: on a Mac with the current Xcode, `npm run mobile:ios`, choose your team under *Signing & Capabilities*, then
*Product → Archive*.

After every app change run `npm run mobile:sync` (or the workflow) so the phone apps get the new version; raise the version numbers
in `android/app/build.gradle` (`versionCode`, `versionName`) and in Xcode (*Version*, *Build*) before publishing an update.

## What differs inside the phone apps
- **Exports** (CSV, bank file, my-data copy) open the phone's share sheet — save to Files / Drive or send by e-mail / WhatsApp.
- **Printing** (payslip, letter, offer, settlement, statutory reports) is a browser feature and is hidden in the apps; use a computer.
- Password-reset and invitation e-mails open in the phone's browser; after setting the password, sign in in the app.
- No employee data is cached by the app; signing out clears the session.
