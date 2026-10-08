# Changelog

Notable changes to Scrippy. Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Dates are ISO 8601.

## [1.0.0] - 2026-10-08

The first public release.

### Added

- **Convert with Scrippy** Quick Action for Finder, for one image, several
  images, or the images directly inside a folder.
- **Convert to JPEG**, **Convert to PNG**, and **Convert to HEIC with
  Scrippy**, which convert in one step without opening the window. Each is
  optional on the installer's Installation Type page.
- A conversion window listing every format SIPS can write on the Mac it runs
  on, the six common formats first, with a plain summary of what each format
  is good for, and a preview of the image beside the controls.
- Six image detail settings for JPEG, HEIC, AVIF, and JPEG 2000, with the last
  format and setting remembered.
- A size estimate for the option on screen, made by converting one image to a
  temporary file.
- A progress window for conversions that take longer than two seconds, with a
  Stop button for batches.
- A landing screen when Scrippy is opened from the Applications folder, which
  shows whether the Finder actions are installed and offers an example image.
- Built in help with topics, search, and printing, also installed as a page
  for the browser.
- A menu bar with About Scrippy, Uninstall Scrippy, help, a link to the latest
  release, and the license.
- An uninstaller package, published beside the installer, that removes
  everything the installer added.
- A log of failed conversions, with a **Show Log** button in the alert.
- A signed and notarized installer with light and dark pages that runs
  natively on Apple silicon and Intel, needs no administrator password, and
  installs into the current account only.

[1.0.0]: https://github.com/drabhikroy/scrippy/releases/tag/v1.0.0
