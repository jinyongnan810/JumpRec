# JumpRec 1.0.25 screenshots

Current UI captured from simulator Debug builds of commit `8130dc3` on October 31, 2026, with cyan accent and the isolated screenshot history. English and Japanese captures use the app's existing localization. PNGs retain native resolution; unused opaque alpha channels are removed without changing RGB pixels.

| Folder in each locale | Native pixels | Screens |
| --- | --- | --- |
| `iPhone-18-Pro` | 1206 × 2622 | Ready, active, history, records, workout details, complete, settings |
| `iPhone-Duo` | 1398 × 2034 | Ready, active, history, records, workout details, complete, settings |
| `iPhone-14-Plus` | 1284 × 2778 | Ready, active, history, records, workout details, complete, settings |
| `Apple-Watch` | 416 × 496 | Ready, active, complete, settings |
| `Apple-Watch-45mm` | 396 × 484 | Ready, active, complete, settings |

## Capture details

- Workout data comes from [the screenshot fixtures](../../Docs/screenshot-data.md). May 2026 has seven workouts, 7,380 jumps, and 54 minutes. Chart samples are representative reconstructions.
- Screenshots are captured with `simctl io screenshot`, rather than the lower-resolution images returned by device interaction tools.
- Review contact sheets are in `review/`. Original draft assets and their ordered API inventories are preserved in `backup/`.
- Device interaction is serialized to avoid simulator resource contention.

## UI observations

These captures show the actual app UI. On the Duo outer display, the active Stop control reaches beyond the bottom edge; the records list has additional entries below the visible area, and its English calorie-rate unit wraps. Fixed bottom controls cover some lower rows in scrolling workout detail and completion content. Settings has additional controls below the visible area.

The English Watch settings count-goal detail truncates at the current default text size. Full goal values remain visible on the ready and active screens.

## Validation

Both iPhone and Watch targets built successfully with Xcode MCP `BuildProject`. `make lint` passed without source changes. No unit tests were run.
