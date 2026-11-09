# Releasing Between Stops

How to ship new builds to TestFlight and submit the app to the App Store. The one-time setup is
done, and build 1.0.0 (1) is on TestFlight. The App Store submission is still to do.

Current Apple rules that apply (checked November 2026):

- Since **April 28, 2026**, App Store Connect only accepts builds made with **Xcode 26 or later
  and the iOS 26 SDK**. This project's CI builds with Xcode 26.6, and both release routes below
  use Xcode 26.
- Distribution needs a paid **Apple Developer Program** membership (99 USD a year). Running the app
  on your own phone from Xcode works with a free Apple Account, but the app stops opening after 7 days.
- Every app needs a **privacy policy URL**, **App Privacy answers**, the **age rating
  questionnaire** (ratings are now 4+, 9+, 13+, 16+, 18+, and the social-media questions became
  mandatory in September 2026), and at least one set of **6.9" iPhone screenshots**.
- To be available in the EU you must declare your **trader status** under the Digital Services Act.

## Current setup

| Item | Value |
| --- | --- |
| Team | `G5K6V5U6QM` (individual Apple Developer Program membership) |
| Bundle ID | `com.martinthommesen.betweenstops`, set in `Config/Signing.xcconfig` |
| App Store name | Between Stops: Commute Games ("Between Stops" was already in use) |
| Home-screen name | Between Stops (`CFBundleDisplayName` in `App/Info.plist`) |
| App record | App Store Connect app `6832542119`, SKU `betweenstops-1` |
| API key | Team key "GitHub upload", Admin access, stored as repository secrets |
| TestFlight group | "Internal", with automatic distribution on |

If Apple reports "Access Unavailable" or a workflow run fails with an agreement error, accept the
updated Program License Agreement at <https://developer.apple.com/account>. The Account Holder
must do this.

## Route A: with a Mac

### Run it on your iPhone

1. Install **Xcode 26** (or later) from the Mac App Store, then XcodeGen: `brew install xcodegen`.
2. In the repository: `xcodegen generate && open BetweenStops.xcodeproj`.
3. Xcode → Settings → Accounts: sign in with your Apple Account.
4. Connect your iPhone with a cable and unlock it. Then on the iPhone: Settings → Privacy &
   Security → **Developer Mode** → on, and restart when asked.
5. In Xcode, pick your iPhone as the run destination and press **Run** (⌘R). Signing is
   automatic. If the iPhone says the developer is untrusted: Settings → General → VPN & Device
   Management → trust your account.

### Upload to TestFlight and the App Store

1. Set the destination to **Any iOS Device (arm64)**, then **Product → Archive**.
2. When the Organizer opens: **Distribute App → App Store Connect → Distribute**. Xcode signs
   and uploads the build.
   - Alternatively, from Terminal: use an App Store Connect API key (see **Replacing the API key**
     under Route B) and run
     `ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/AuthKey_….p8 APP_TEAM_ID=… bash ci/release.sh`.
3. Before each further upload, raise the build number (`CURRENT_PROJECT_VERSION` in
   `project.yml`, or `BUILD_NUMBER=` for `ci/release.sh`). Raise `MARKETING_VERSION` for each new
   App Store version.
4. Continue with **Submit for review** below.

## Route B: without a Mac (GitHub Actions + TestFlight)

This is the route in use. A GitHub-hosted Mac builds, signs and uploads the app. You install it on
your iPhone with the TestFlight app.

1. **Run the workflow**: Actions → TestFlight → Run workflow. The build number is the workflow's
   run number, so it increases automatically. The first run took about 3 minutes.
2. **Wait for processing**: the build appears in App Store Connect → your app → TestFlight once
   Apple has processed it (5 to 30 minutes). The app declares that it uses no non-exempt
   encryption, so no export compliance question is normally asked.
3. **Install on your iPhone**: the Internal group gets new builds automatically. Install
   **TestFlight** from the App Store, accept the invite, and tap Install. TestFlight builds expire
   after 90 days.

To add internal testers, first add them in Users and Access, then add them to the group.

### Replacing the API key

1. App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **+**.
   Use Access **Admin**, because the build creates its distribution certificate and profile in the
   cloud. Download the `.p8` file (you can only download it once). Note the **Key ID** and the
   **Issuer ID** shown above the list.
2. Update the repository secrets (GitHub → this repository → Settings → Secrets and variables →
   Actions), then revoke the old key:

   | Secret | Value |
   | --- | --- |
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | the whole text of the `.p8` file, including the BEGIN/END lines |
   | `APP_TEAM_ID` | the Team ID |

## Submit for review (both routes)

In App Store Connect → your app. Ready-made copy is in `docs/app-store/`.

1. **App Information**: subtitle, Category **Games**, subcategories **Card** and **Puzzle**,
   content rights (no third-party content), and the **Age Rating** questionnaire. Answer None/No
   to everything, including the social-media and user-generated-content questions; the result
   should be 4+.
2. **Pricing and Availability**: Free, all territories (or your choice).
3. **App Privacy**: Privacy Policy URL, for example
   `https://github.com/JVE1814/play/blob/main/docs/app-store/privacy-policy.md` (or host
   `docs/app-store/privacy-policy.md` anywhere public). Data collection: **"No, we do not collect
   data from this app."** This matches `App/Resources/PrivacyInfo.xcprivacy`.
4. **Accessibility** (optional, recommended): declare VoiceOver, Larger Text, Dark Interface,
   Differentiate Without Color Alone, Sufficient Contrast and Reduced Motion. All are supported.
5. **Version 1.0 page**:
   - Screenshots: drag in the files from `docs/app-store/screenshots/` (1320 × 2868, the 6.9"
     size; App Store Connect scales them for smaller iPhones).
   - Promotional text, description, keywords, support URL and copyright from
     `docs/app-store/listing.md`.
   - Build: choose the uploaded build.
   - App Review Information: your contact details. No sign-in is required. Paste the review notes
     from `listing.md`.
   - Version release: manual or automatic, as you prefer.
6. **Business** (account level): complete the agreements, and the **Digital Services Act trader
   status** if you want EU availability.
7. Press **Add for Review → Submit**. Reviews usually finish within a day or two.

## Updating later

Raise `MARKETING_VERSION` (and the build number) in `project.yml`, push, check that CI is green,
then upload with either route and submit the new version the same way.
