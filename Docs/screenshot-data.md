# Simulator screenshot data

Debug simulator builds accept these launch arguments. They have no effect in release builds or on physical devices.

| Arguments | Behavior |
| --- | --- |
| `--screenshot-data` | Enable a separate local history store with seven May 2026 workouts. |
| `--screenshot-data --screenshot-state active` | Show a workout with 182 jumps, 7 calories, and 111 bpm on iPhone or Watch. |
| `--screenshot-data --screenshot-state complete` | Show the 182-jump, 01:27, 7-calorie completion screen on iPhone or Watch. |
| `--disable-screenshot-data` | Return to the normal history store on the next launch. |

The history mode stays enabled after relaunching from the Home Screen. Active and complete states require their launch arguments each time. The Watch uses the workout states; its app does not have a history screen.

The sample history uses its own persistent SwiftData configuration with CloudKit disabled. The normal history store is preserved. Repeated launches do not insert duplicate sessions. Screenshot mode hides the development-only Delete All and Share CSV controls and disables debug-only AI recaps. Active iPhone screenshots use the headphone tracking badge.

May history totals: **7 workouts, 7,380 jumps, 54 minutes**. May 26 contains the **1,000-jump, 07:15, 61-calorie** workout with a 180/min peak rate and a 492-jump longest streak. Personal records include **1,208 jumps**, **157/min average**, **1,000 consecutive jumps**, **83 calories**, and the **204/min June 19** peak-rate record shown in the reference.

The reference image supplies summary values, not raw sensor data. Chart samples and obscured workout details are representative reconstructions. Navigate to May 2026 in History to view the reference month.

For English captures, also pass `-AppleLanguages (en) -AppleLocale en_US`. Existing app localization handles the displayed controls and metrics.
