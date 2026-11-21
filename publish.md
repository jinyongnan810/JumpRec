# App Store Release Runbook (`publish.md`)

Guide for creating a new App Store Connect release draft for **JumpRec** (`com.kinn.JumpRec`, App ID `6760456262`) using the `asc` CLI and simulator screenshot tooling.

---

## 1. Prerequisites

- **`asc` CLI `>= 6.6.1`** (required for `APP_IPHONE_DUO` validation and upload support):
  ```sh
  brew upgrade asc
  asc --version
  ```
- **Use the `kinn` profile** on every `asc` command (`--profile kinn`). The default profile (`macdevcleaner-release`) returns `403 Forbidden` for JumpRec.
- **Verify auth and current app status**:
  ```sh
  asc auth doctor
  ASC_TIMEOUT=90s asc --profile kinn status --app "6760456262" --output json --pretty
  asc --profile kinn builds list --app "6760456262" --limit 10 --output json
  ```
  Confirm the target build has `"processingState": "VALID"` and note its `id` (`<BUILD_ID>`).

---

## 2. Supported App Store Locales

JumpRec supports these App Store Connect locales (matching `knownRegions` in `JumpRec.xcodeproj`):

| App Store Locale | Language | Simulator Launch Flags | Privacy Policy File |
| --- | --- | --- | --- |
| `en-US` | English (U.S.) | `-AppleLanguages "(en)" -AppleLocale en_US` | `PRIVACY_POLICY.md` |
| `ja` | Japanese | `-AppleLanguages "(ja)" -AppleLocale ja_JP` | `PRIVACY_POLICY_ja.md` |
| `zh-Hans` | Chinese (Simplified) | `-AppleLanguages "(zh-Hans)" -AppleLocale zh_Hans_CN` | `PRIVACY_POLICY_zh-Hans.md` |
| `zh-Hant` | Chinese (Traditional) | `-AppleLanguages "(zh-Hant)" -AppleLocale zh_Hant_TW` | `PRIVACY_POLICY_zh-Hant.md` |
| `ko` | Korean | `-AppleLanguages "(ko)" -AppleLocale ko_KR` | `PRIVACY_POLICY_ko.md` |

---

## 3. Review Changes Since the Previous Release

Inspect git commits and view diffs since the last release tag (e.g., `v1.0.26..HEAD`):

```sh
git log --oneline <PREV_TAG>..HEAD
git diff <PREV_TAG>..HEAD -- "JumpRec/Views" "JumpRec Watch App/Views" "JumpRecShared"
```

Use this to determine:
1. **Release notes (`whatsNew`)**: Easy-to-read, user-friendly summary for all supported locales (avoid internal/technical details).
2. **Screenshots to update**: Which screens changed visually across iOS / watchOS and for which locales. Do **not** re-capture locales/screens that have no visual UI changes; App Store Connect inherits unchanged screenshots from the previous version.

---

## 4. Create the Draft Version & Attach Build

Use `asc release stage` to create the new `PREPARE_FOR_SUBMISSION` version, copy existing metadata (including `promotionalText`, `description`, `keywords`, `marketingUrl`, `supportUrl`) from the previous version, and attach the target build.

Preview first with `--dry-run`, then execute with `--confirm`:

```sh
asc --profile kinn release stage \
  --app "6760456262" \
  --version "<NEW_VERSION>" \
  --build-id "<BUILD_ID>" \
  --copy-metadata-from "<PREV_VERSION>" \
  --confirm \
  --output json \
  --pretty
```

Note the returned `versionId`, and check the created localization IDs:

```sh
asc --profile kinn localizations list --version "<VERSION_ID>" --output json --pretty
```

> **Cleanup note:** `asc release stage` creates a `.asc/` checkpoint directory in the repository root. Remove `.asc/` when finished so it is not left untracked in git.

---

## 5. Update Localized Metadata & Release Notes (`whatsNew`)

Update `whatsNew` for every active App Store Connect locale while keeping `promotionalText` intact:

```sh
asc --profile kinn localizations update --id "<LOCALIZATION_ID>" --whats-new "$WHATS_NEW"
```

### Adding a New Language to App Store Connect

When a new language is added to the app:
1. Add both **App Info** (`name`, `subtitle`, `privacyPolicyUrl`) and **Version** (`description`, `keywords`, `promotionalText`, `whatsNew`, `marketingUrl`, `supportUrl`) localizations—for example, by pulling metadata via `asc --profile kinn metadata pull`, adding the new `<locale>.json` files, previewing with `asc metadata push --dry-run`, and applying with `--confirm`.
   - Avoid repeating localized `subtitle` terms inside `keywords` (checked by `asc validate`).
2. Update the **Unlimited Workouts** In-App Purchase (`6814382464`, `com.kinn.JumpRec.unlimitedWorkouts`):
   ```sh
   asc --profile kinn iap versions create --iap-id "6814382464" --output json --pretty
   asc --profile kinn iap versions localizations create \
     --version-id "<IAP_VERSION_ID>" \
     --locale "<LOCALE>" \
     --name "<LOCALIZED_NAME>" \
     --description "<LOCALIZED_DESCRIPTION>"
   ```
   Remember to include the new IAP version when submitting the app version for review.

---

## 6. Capture & Update Screenshots

Screenshots are stored directly under `Screenshots/<locale>/<Device>/` (no date subdirectories). Only update the screenshots for locales and screens that changed visually or were newly added.

See [Docs/screenshot-data.md](Docs/screenshot-data.md) for fixture details (`--screenshot-data`, `--screenshot-state`, and default cyan accent).

### 6.1 Build the Debug Simulator Apps

Per [AGENTS.md](AGENTS.md), build the `JumpRec` scheme (and `JumpRec Watch App` if Watch screenshots are needed) with the Xcode MCP `BuildProject` tool (not shell `xcodebuild` with custom output paths). Locate `JumpRec.app` and `JumpRec Watch App.app` via `GetTargetBuildSettings` (`SYMROOT`).

### 6.2 Target Devices & Display Types

| App Store Display Type | Simulator Device | Folder Name | Native Resolution | Notes |
| --- | --- | --- | --- | --- |
| `IPHONE_61` | `iPhone 18 Pro` | `iPhone-18-Pro` | `1206 × 2622` | Standard `simctl io` |
| `IPHONE_65` | `iPhone 14 Plus` | `iPhone-14-Plus` | `1284 × 2778` | Create temporarily via `xcrun simctl create` if missing, then delete after |
| `IPHONE_DUO` | `iPhone Duo` | `iPhone-Duo` | `1398 × 2034` | Outer display; pass `--display=1` to `simctl io screenshot` |
| `WATCH_SERIES_10` | `Apple Watch` (46mm) | `Apple-Watch` | `416 × 496` | Bundle ID `com.kinn.JumpRec.watchkitapp` |

### 6.3 Capture Per Simulator (Serialized)

Boot **one simulator at a time** to avoid resource contention, and write updated PNGs directly into `Screenshots/<locale>/<Device>/`:

1. Boot, wait for ready, set clean `9:41` status bar (on iOS), and install the `.app`:
   ```sh
   xcrun simctl boot "<UDID>"
   xcrun simctl bootstatus "<UDID>" -b
   xcrun simctl status_bar "<UDID>" override \
     --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
     --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
   xcrun simctl install "<UDID>" "<PATH_TO_APP>"
   ```
2. Launch per locale using the launch flags in Section 2 and capture native-resolution PNGs with `xcrun simctl io <UDID> screenshot` (adding `--display=1` on `iPhone Duo`):
   - **Ready (`01-ready.png`)**: launch with `--screenshot-data` and wait ~4s on first launch after boot/install so the initial view is rendered (not a blank launch screen).
   - **Active (`02-active.png`)**: launch with `--screenshot-data --screenshot-state active` and wait ~2–4s.
   - **Workout Complete (`06-complete.png` on iOS / `03-complete.png` on Watch)**: launch with `--screenshot-data --screenshot-state complete` and wait ~5s on iOS so `SessionCompleteView`'s staggered fade-in finishes completely.
   - **Interactive screens (`03-history.png`, `04-records.png`, `05-workout-details.png`, `07-settings.png` on iOS; `04-settings.png` on Watch)**: launch with `--screenshot-data`, use Xcode MCP `DeviceInteractionStartSession` + `DeviceInteractionSynthesize` (via subagent) to navigate (e.g., Settings sheet; History → May 2026 → Personal Records / May 26 workout), capture via `xcrun simctl io <UDID> screenshot`, and end the interaction session.
3. Visually inspect captured PNGs to confirm there are no blank screens, mid-transition fades, or clipped text.
4. Shut down the simulator before booting the next one (`xcrun simctl shutdown "<UDID>"`). Delete any temporary simulator created for `iPhone 14 Plus`.

### 6.4 Strip Opaque Alpha Channel & Validate

`xcrun simctl io screenshot` writes `RGBA` PNGs, which App Store Connect rejects. Strip the unused alpha channel so every updated PNG is `8-bit/color RGB` without altering RGB pixels (e.g. via CoreGraphics `CGImageAlphaInfo.noneSkipLast`), verify with `file`, then validate updated sets with `asc`:

```sh
asc --profile kinn screenshots validate --path Screenshots/<LOCALE>/iPhone-18-Pro --device-type IPHONE_61
asc --profile kinn screenshots validate --path Screenshots/<LOCALE>/iPhone-14-Plus --device-type IPHONE_65
asc --profile kinn screenshots validate --path Screenshots/<LOCALE>/iPhone-Duo --device-type IPHONE_DUO
asc --profile kinn screenshots validate --path Screenshots/<LOCALE>/Apple-Watch --device-type WATCH_SERIES_10
```

Confirm `errorCount: 0` and `warningCount: 0` on all validated sets.

---

## 7. Upload Updated Screenshots

Upload only the locales and display types that were updated or newly added (preview with `--dry-run` first if needed):

```sh
asc --profile kinn screenshots upload --version-localization "<LOCALIZATION_ID>" --path Screenshots/<LOCALE>/iPhone-18-Pro --device-type IPHONE_61 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<LOCALIZATION_ID>" --path Screenshots/<LOCALE>/iPhone-14-Plus --device-type IPHONE_65 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<LOCALIZATION_ID>" --path Screenshots/<LOCALE>/iPhone-Duo --device-type IPHONE_DUO --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<LOCALIZATION_ID>" --path Screenshots/<LOCALE>/Apple-Watch --device-type WATCH_SERIES_10 --replace --confirm --output json
```

Verify all uploaded items report `"state": "COMPLETE"`.

---

## 8. Final Validation & Cleanup

1. Remove `.asc/` if created by `asc release stage`:
   ```sh
   rm -rf .asc
   ```
2. Run App Store Connect readiness and status checks:
   ```sh
   asc --profile kinn validate --app "6760456262" --version "<NEW_VERSION>" --output json --pretty
   ASC_TIMEOUT=90s asc --profile kinn status --app "6760456262" --output json --pretty
   ```
   Confirm `errors: 0`, `warnings: 0`, `blocking: 0`, `appstore.state == "PREPARE_FOR_SUBMISSION"`, and check `phasedRelease.configured` (new versions start with phased release unconfigured—enable in App Store Connect if desired before submitting for review).
3. If distributing in Mainland China (`CHN`), verify **General → App Compliance** in App Store Connect (AIGC and Security Assessment declarations).
4. If repository files were changed, run `make lint` and check `git status`.
