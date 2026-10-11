# Transfer development sessions to production

JumpRec Settings includes **Session Backup → Export Backup / Import Backup** on iPhone. Both the development build and the production build must contain this feature.

1. Open the development build while signed into the iCloud account containing your history. Wait for sync to finish and check the session count and charts.
2. In Settings, choose **Export Backup**. Save the JSON file outside JumpRec's app storage, such as Files → iCloud Drive. Keep another copy on your Mac. The completion message reports the exported session count.
3. In CloudKit Console, select `iCloud.com.kinn.JumpRec` and deploy any pending development schema changes to production. Schema deployment does not copy records.
4. Install a production-signed build containing the import feature, such as TestFlight. Prefer a second iPhone or a clean installation after backing up any local data. JumpRec uses a shared app-group store; installing another build over the development app does not establish a clean production store. Do not copy its SQLite store or CloudKit sync metadata between environments.
5. Sign into the destination iCloud account, open the production build, and wait for existing production history to download.
6. In Settings, choose **Import Backup**, select the JSON file, review the session count, and confirm. The result reports imported and skipped sessions.
7. Allow iCloud upload to finish, then check History on a second production device signed into the destination account. Compare counts, dates, metrics, and charts before removing your development data.

The backup includes downloaded session summaries, original UUIDs, raw chart payloads, and personal records. It does not include settings, purchases, raw motion CSV files, or HealthKit workouts. Import does not write to HealthKit.

Import skips session UUIDs already in the destination store, including edited sessions; it does not overwrite them. Personal records merge by kind and retain the better value. All backup changes are saved together using a separate SwiftData context. Unsupported or invalid backups are rejected before insertion.

An export captures only data already downloaded to the device. An idle sync indicator does not prove that every cloud record has downloaded. Import saves locally to the current build's store; iCloud upload happens asynchronously when available. Verify on another production device to confirm the transfer.
