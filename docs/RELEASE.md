# Releasing Between Stops

Your manual steps to put the app on your own iPhone and submit it to the App Store. Nothing here
has been done for you: no App Store Connect records, certificates or keys exist yet.

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

## 0. One-time setup (both routes)

1. Join the Apple Developer Program at <https://developer.apple.com/programs/> (individual is
   fine). Note your **Team ID** (developer.apple.com → Account → Membership details).
2. Pick a bundle ID you own, e.g. `com.yourname.betweenstops`, and put it with your Team ID in
   **`Config/Signing.xcconfig`**:

   ```
   APP_BUNDLE_ID = com.yourname.betweenstops
   APP_DEVELOPMENT_TEAM = AB12CD34EF
   ```

   Commit that change. It contains no secrets.
3. Register the bundle ID: developer.apple.com → Certificates, Identifiers & Profiles →
   Identifiers → **+** → App IDs → App. Use description "Between Stops", the explicit bundle ID
   above, and no extra capabilities.
4. Create the app record: <https://appstoreconnect.apple.com> → Apps → **+** → New App.
   - Platform: iOS. Name: **Between Stops** (if it is taken, pick another and update
     `CFBundleDisplayName` in `App/Info.plist`). Primary language: English (U.S.).
   - Bundle ID: the one above. SKU: anything, e.g. `betweenstops-1`. User access: Full Access.

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
   - Alternatively, from Terminal: create an App Store Connect API key (see Route B, step 1) and
     run `ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/AuthKey_….p8 APP_TEAM_ID=… bash ci/release.sh`.
3. Before each further upload, raise the build number (`CURRENT_PROJECT_VERSION` in
   `project.yml`, or `BUILD_NUMBER=` for `ci/release.sh`). Raise `MARKETING_VERSION` for each new
   App Store version.
4. Continue with **Submit for review** below.

## Route B: without a Mac (GitHub Actions + TestFlight)

A GitHub-hosted Mac builds, signs and uploads the app. You install it on your iPhone with the
TestFlight app.

1. **Create an App Store Connect API key**: App Store Connect → Users and Access →
   Integrations → App Store Connect API → Team Keys → **+**. Name it "GitHub upload", with
   Access **Admin**. Admin is needed because the build creates its distribution certificate and
   profile in the cloud. Download the `.p8` file (you can only download it once). Note the
   **Key ID** and the **Issuer ID** shown above the list.
2. **Add four repository secrets**: GitHub → this repository → Settings → Secrets and variables
   → Actions → New repository secret:

   | Secret | Value |
   | --- | --- |
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | the whole text of the `.p8` file, including the BEGIN/END lines |
   | `APP_TEAM_ID` | your Team ID |

3. **Install the workflow**: on github.com, open `docs/release/testflight.yml`, copy its
   contents, then Add file → Create new file → name it `.github/workflows/testflight.yml` →
   paste → commit to `main`. Don't change `.github/workflows/ci.yml`.
4. **Run it**: Actions → TestFlight → Run workflow. It takes about 10 to 15 minutes. The build
   number is the workflow's run number, so it increases automatically.
5. **Install on your iPhone**: wait until the build shows in App Store Connect → your app →
   TestFlight (processing takes 5 to 30 minutes). Answer the export compliance question if it
   appears. The app declares that it uses no non-exempt encryption, so normally nothing is asked.
   Under Internal Testing, create a group, add yourself, and enable the build. Install
   **TestFlight** from the App Store on your iPhone, accept the invite, and tap Install.
   TestFlight builds expire after 90 days.

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
