# App Store screen captures

English simulator captures with cyan accent and reconstructed May 2026 workout data. All PNGs use native pixel dimensions and RGB color with no alpha channel. Removing the unused, fully opaque alpha channel preserved every color pixel; no images were resized.

The matching [Japanese captures](ja/README.md) are stored separately in `ja/`.

## App Store Connect upload

Uploaded all 36 English and Japanese screenshots to JumpRec version **1.0.21** on October 24, 2026, using ASC CLI 5.16.1. Each locale has seven iPhone 18 Pro, seven iPhone Duo, and four Apple Watch screenshots. All uploaded assets report `COMPLETE`; remote checksums and display order match the local files.

The existing iPhone 6.1-inch sets were replaced after backup. The Duo and Watch Series 10-size sets were added. Other existing device-size sets were retained. No app review submission was started.

- [Review in App Store Connect](https://appstoreconnect.apple.com/apps/6760456262)
- [Verified upload report](upload-report.json)

| Device | Size | Captures |
| --- | --- | --- |
| [iPhone 18 Pro](iPhone-18-Pro) | 1206 × 2622 | 7 |
| [iPhone Duo outer display](iPhone-Duo) | 1398 × 2034 | 7 |
| [Apple Watch Series 12, 46 mm](Apple-Watch) | 416 × 496 | 4 |

Phone captures: `01-ready`, `02-active`, `03-history`, `04-records`, `05-workout-details`, `06-complete`, `07-settings`. Watch captures: `01-ready`, `02-active`, `03-complete`, `04-settings`.

The ready screens omit the hands-free instruction. Active phone screens show headphone tracking. Watch toolbar buttons use plain styling. Development-only Delete All, Share CSV, and AI recap features are hidden.

## Review notes

- Duo captures cover the outer display. The right-side system status area is part of the actual simulator interface.
- Duo's active Stop control reaches beyond the bottom edge. Fixed Done and Confirm controls overlap some scrolling content. Review these layouts before selecting the final App Store sequence.
- The Watch settings capture truncates the count-goal detail. Prefer its ready, active, and complete captures for the product page.
- Chart samples and obscured workout details are reconstructed, rather than recovered sensor measurements.

## References

Apple recommends showing the core experience, leading with strong features, using readable content, and keeping assets consistent. Suggested phone sequence: active workout, history, workout details, records, completion, ready, settings.

- [Apple's asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Simulator data and launch arguments](../../Docs/screenshot-data.md)
