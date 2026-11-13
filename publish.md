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
  asc --profile kinn status --app "6760456262" --output json --pretty
  asc --profile kinn builds list --app "6760456262" --limit 10 --output json
  ```
  Confirm the target build has `"processingState": "VALID"` and note its `id` (`<BUILD_ID>`).

---

## 2. Review Changes Since the Previous Release

Inspect git commits and view diffs since the last release tag (e.g., `v1.0.25..HEAD`):

```sh
git log --oneline <PREV_TAG>..HEAD
git diff <PREV_TAG>..HEAD -- "JumpRec/Views" "JumpRec Watch App/Views"
```

Use this to determine:
1. **Release notes (`whatsNew`)**: Easy-to-read, user-friendly summary in `en-US` and `ja` (avoid internal technical details).
2. **Screenshots to update**: Which screens changed visually across iOS / watchOS.

---

## 3. Create the Draft Version & Attach Build

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

## 4. Update Localized Release Notes (`whatsNew`)

Update `whatsNew` for both `en-US` and `ja` while keeping `promotionalText` intact:

```sh
asc --profile kinn localizations update --id "<EN_US_LOCALIZATION_ID>" --whats-new "$EN_WHATS_NEW"
asc --profile kinn localizations update --id "<JA_LOCALIZATION_ID>" --whats-new "$JA_WHATS_NEW"
```

---

## 5. Capture & Prepare Updated Screenshots

See [Docs/screenshot-data.md](Docs/screenshot-data.md) for fixture details (`--screenshot-data`, `--screenshot-state`, and default cyan accent).

### 5.1 Build the Debug Simulator App

Per [AGENTS.md](AGENTS.md), build the `JumpRec` scheme with the Xcode MCP `BuildProject` tool (not shell `xcodebuild` with custom output paths). Locate `JumpRec.app` in `DerivedData/.../Build/Products/Debug-iphonesimulator/JumpRec.app` (via `GetTargetBuildSettings`).

### 5.2 Target Devices & Display Types

| App Store Display Type | Simulator Device | Native Resolution | Notes |
| --- | --- | --- | --- |
| `IPHONE_61` | `iPhone 18 Pro` | `1206 × 2622` | Standard `simctl io` |
| `IPHONE_65` | `iPhone 14 Plus` | `1284 × 2778` | Create temporarily via `xcrun simctl create` if missing, then delete after |
| `IPHONE_DUO` | `iPhone Duo` | `1398 × 2034` | Outer display; pass `--display=1` to `simctl io screenshot` |
| `WATCH_SERIES_10` | `Apple Watch` (if Watch UI changed) | `416 × 496` | Only needed when Watch views change |

### 5.3 Initialize Output Directory

Create `Screenshots/<YYYY-MM-DD>/` and copy the previous release's screenshot sets (`en-US` and `ja`) as a baseline, then overwrite only the screens that changed:

```sh
mkdir -p Screenshots/<YYYY-MM-DD>/en-US Screenshots/<YYYY-MM-DD>/ja
cp -R Screenshots/<PREV_DATE>/en-US/* Screenshots/<YYYY-MM-DD>/en-US/
cp -R Screenshots/<PREV_DATE>/ja/* Screenshots/<YYYY-MM-DD>/ja/
chmod -R u+w Screenshots/<YYYY-MM-DD>
```

### 5.4 Capture Per Simulator (Serialized)

Boot **one simulator at a time** to avoid resource contention:

1. Boot, wait for ready, set clean `9:41` status bar, and install `JumpRec.app`:
   ```sh
   xcrun simctl boot "<UDID>"
   xcrun simctl bootstatus "<UDID>" -b
   xcrun simctl status_bar "<UDID>" override \
     --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
     --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
   xcrun simctl install "<UDID>" "<PATH_TO_JUMPREC_APP>"
   ```
2. Launch per locale (`-AppleLanguages '(en)' -AppleLocale en_US` and `-AppleLanguages '(ja)' -AppleLocale ja_JP`) and capture native-resolution PNGs with `xcrun simctl io <UDID> screenshot` (adding `--display=1` on `iPhone Duo`):
   - **Home (`01-ready.png`)**: launch with `--screenshot-data`
   - **Workout Complete (`06-complete.png`)**: launch with `--screenshot-data --screenshot-state complete`
   - **Interactive screens (e.g. `05-workout-details.png`)**: launch with `--screenshot-data`, use Xcode MCP `DeviceInteractionStartSession` + `DeviceInteractionSynthesize` (via subagent) to navigate to History → May 2026 → May 26 workout, then capture via `xcrun simctl io <UDID> screenshot` and end the interaction session.
3. Shut down the simulator before booting the next one (`xcrun simctl shutdown "<UDID>"`). Delete any temporary simulator created for `iPhone 14 Plus`.

### 5.5 Strip Opaque Alpha Channel & Validate

`xcrun simctl io screenshot` writes `RGBA` PNGs, which App Store Connect rejects. Strip the unused alpha channel so every updated PNG is `8-bit/color RGB` without altering RGB pixels (e.g. via CoreGraphics `CGImageAlphaInfo.noneSkipLast`), verify with `file`, then validate with `asc`:

```sh
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-18-Pro --device-type IPHONE_61
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-14-Plus --device-type IPHONE_65
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-Duo --device-type IPHONE_DUO
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/ja/iPhone-18-Pro --device-type IPHONE_61
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/ja/iPhone-14-Plus --device-type IPHONE_65
asc --profile kinn screenshots validate --path Screenshots/<YYYY-MM-DD>/ja/iPhone-Duo --device-type IPHONE_DUO
```

Confirm `errorCount: 0` and `warningCount: 0` on all sets.

---

## 6. Upload Screenshots

Replace each updated display type set for both `en-US` and `ja` (preview with `--dry-run` first if needed):

```sh
asc --profile kinn screenshots upload --version-localization "<EN_US_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-18-Pro --device-type IPHONE_61 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<EN_US_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-14-Plus --device-type IPHONE_65 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<EN_US_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/en-US/iPhone-Duo --device-type IPHONE_DUO --replace --confirm --output json

asc --profile kinn screenshots upload --version-localization "<JA_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/ja/iPhone-18-Pro --device-type IPHONE_61 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<JA_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/ja/iPhone-14-Plus --device-type IPHONE_65 --replace --confirm --output json
asc --profile kinn screenshots upload --version-localization "<JA_LOCALIZATION_ID>" --path Screenshots/<YYYY-MM-DD>/ja/iPhone-Duo --device-type IPHONE_DUO --replace --confirm --output json
```

Verify all uploaded items report `"state": "COMPLETE"`.

---

## 7. Final Validation & Cleanup

1. Remove `.asc/` if created by `asc release stage`:
   ```sh
   rm -rf .asc
   ```
2. Run App Store Connect readiness and status checks:
   ```sh
   asc --profile kinn validate --app "6760456262" --version "<NEW_VERSION>" --output json --pretty
   asc --profile kinn status --app "6760456262" --output json --pretty
   ```
   Confirm `errors: 0`, `warnings: 0`, `blocking: 0`, `appstore.state == "PREPARE_FOR_SUBMISSION"`, and check `phasedRelease.configured` (new versions start with phased release unconfigured—enable in App Store Connect if desired before submitting for review).
3. If repository files were changed, run `make lint` and check `git status`.
