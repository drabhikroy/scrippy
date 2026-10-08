# Scrippy

[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey)](#requirements)
![Architecture](https://img.shields.io/badge/architecture-Apple%20silicon%20%7C%20Intel-black?logo=apple&logoColor=white)
[![Release](https://img.shields.io/github/v/release/drabhikroy/scrippy)](https://github.com/drabhikroy/scrippy/releases/latest)

Scrippy converts images to any format your Mac can write without leaving
Finder.

Everything runs on your Mac. No account is required and no server is used.
Your images never leave your computer.

<img src="Assets/screenshots/choose-format.png" width="760" alt="The Convert with Scrippy window. On the left are the format menu set to JPEG, the image detail menu, a size estimate of about 642 KB, and notes on what JPEG is good for and what to consider. On the right is a preview of the galaxy image with its format, pixel size, and file size.">

## What it does

Right-click images or a folder in Finder and choose **Convert with Scrippy**
from the Quick Actions menu. A small window asks for the format. The new
copies are saved next to the originals.

Three optional actions skip the window for the most common formats. They are
**Convert to JPEG with Scrippy**, **Convert to PNG with Scrippy**, and
**Convert to HEIC with Scrippy**.

- **Every format your Mac can write.** The list comes from your own Mac each
  time. The six most popular formats come first. Formats added in a macOS
  update appear on their own.
- **A plain note on each format.** The window says what the format is good
  for and what to keep in mind.
- **A detail setting for compressed formats.** JPEG, HEIC, AVIF, and JPEG 2000
  offer six settings from Automatic to Highest detail. Scrippy remembers your
  last choice.
- **A size estimate first.** Scrippy converts one sample image and tells you
  about how large the result will be.
- **Batches you can stop.** Several images convert in one pass, as do all the
  images in a folder. A long batch shows its progress and can be stopped
  between images.
- **A small app for the rest.** Open Scrippy to check its Finder actions, try
  an example image, and read the help.
- **A clean way out.** An uninstaller removes everything the installer added.

The name comes from SIPS, the Scriptable Image Processing System. It is built
into macOS and does every conversion.

## What it does not do

Scrippy never changes, moves, or replaces an original. When a name is taken
the copy gets `-1`, `-2`, and so on. An earlier copy is never overwritten
either.

It does not look inside subfolders. A conversion never reaches past the files
you can see in the folder you chose.

It does not resize, crop, rotate, or edit images. It does not make animated
GIFs. It installs no image library of its own.

## Requirements

- macOS 11 or later
- An Apple silicon or Intel Mac

Nothing else is needed. SIPS is part of macOS. The installer does not ask for
an administrator password.

## Install

1. Download `Scrippy-1.0.0.pkg` from the
   [latest release](https://github.com/drabhikroy/scrippy/releases/latest).
2. Open it and follow the steps. Everything installs into your own account.
3. On the Installation Type page, choose your Quick Actions. **Convert with
   Scrippy** is always installed. The three one-step actions are optional.

<img src="Assets/screenshots/installer-choices.png" width="560" alt="The Installation Type page of the Scrippy installer. It lists four checked Quick Actions. Convert with Scrippy is always installed. Convert to JPEG, PNG, and HEIC with Scrippy can be cleared.">

Scrippy itself is in the Applications folder inside your home folder. Open it
to see which Finder actions are installed.

### Checking the download

`SHA256SUMS.txt` is published with each release. Put it in the same folder as
the package and run this command.

```bash
shasum -a 256 -c SHA256SUMS.txt
```

### Removing Scrippy

Open `Uninstall-Scrippy-1.0.0.pkg` from the same release. You can also choose
**Uninstall Scrippy** from the Scrippy menu. Your images and the copies
Scrippy made stay where they are.

## Using Scrippy

1. In Finder, select one image, several images, or a folder.
2. Right-click and choose **Quick Actions**, then **Convert with Scrippy**.
3. Choose a format and an image detail setting if one is offered.
4. Click **Convert**.

<img src="Assets/screenshots/finder-quick-actions.png" width="520" alt="The Finder shortcut menu for an image. Quick Actions is open and Convert with Scrippy is listed.">

A notification confirms the result. If a file cannot be converted, an alert
offers **Show Log**. The log gives the reason for each failure.

When the actions are missing from the Quick Actions menu, open Scrippy and
click **Choose Which Actions Appear**.

The help is built into the app. Choose **Scrippy Help** from the Help menu or
click the help button in the conversion window. **Open Help in Browser** shows
the same text as a web page.

## Your data

Every conversion and estimate runs on your Mac through SIPS. Scrippy makes no
network connections. A link in the help or the About panel opens your browser
only when you click it.

| What Scrippy writes | Where | How long it stays |
| --- | --- | --- |
| Converted copies | Next to each original | Until you delete them |
| Size estimates | A private temporary folder | Deleted once measured |
| Failed conversions | `~/Library/Logs/Scrippy/scrippy.log` | Trimmed past one megabyte |
| Your last format and setting | Scrippy's preferences | Until you uninstall |

Each copy is first written to a hidden folder next to the original. It is
then moved into place in one step and the hidden folder is removed.

## Accessibility

- **Standard controls.** Every window uses standard macOS controls. VoiceOver,
  Full Keyboard Access, Increase Contrast, and Reduce Transparency work as they
  do in other apps.
- **Shape as well as color.** Status on the landing screen uses a check for
  installed and a cross for missing.
- **Labels.** Menus, buttons, and help topics carry accessibility labels.
  Decorative symbols are hidden from VoiceOver. The progress window announces
  each change.
- **Keyboard.** Return converts. Escape cancels or stops. Command Question
  Mark opens the help. Command F searches it and Command P prints a topic.
- **Copyable text.** Notes, estimates, and help text can all be selected and
  copied.
- **Light and dark.** The installer pages and the help page follow your
  appearance and meet WCAG 2.2 AA contrast. The help page also has a skip
  link and a visible focus ring, and it honors Reduce Motion.

## How it works

Each Quick Action is an Automator workflow. It passes the Finder selection to
a shell script.

1. The script asks SIPS which files it can read and which formats it can
   write.
2. It opens Scrippy.app to ask which format to use.
3. The app answers with one line holding the format and detail setting.
4. The script runs SIPS once for each image.

The one-step actions pass their format straight to the script and never open
the window.

The app converts nothing itself except the temporary file behind each
estimate. Its answer is checked against the list the script built, so only a
format SIPS reported as writable can be used. The script looks for the app in
two fixed places only. One is the Applications folder in your home folder and
the other is the main Applications folder.

## Help

The help source is [help/Scrippy Help.md](help/Scrippy%20Help.md). The app
reads it directly. `Scripts/make_help.py` turns it into the web page
[help/Scrippy Help.html](help/Scrippy%20Help.html).

## For developers

### Project layout

| Path | Holds |
| --- | --- |
| `src/scrippy.sh` | The conversion engine the Finder actions run |
| `package/app/Sources/` | Scrippy.app with its windows, menus, and uninstall command |
| `package/app/Info.plist` | The app's name, version, and copyright |
| `workflow/` | The main Quick Action. The build makes the one-step actions from it |
| `package/` | The installer layout, pages, backgrounds, and postinstall script |
| `package/uninstall/` | The uninstaller pages and the script that removes Scrippy |
| `help/` | The help source and the web page made from it |
| `Assets/` | Icon sources, rendered PNGs, and screenshots. See [Assets/README.md](Assets/README.md) |
| `Scripts/` | Generators for the icon, help page, and license pane, plus the screenshot cleaner and the writing gate |
| `tests/` | Engine and project tests with stand-ins for SIPS, osascript, and the app |

### Dependencies

| Task | Needs |
| --- | --- |
| Building | Xcode or the Command Line Tools |
| Tests | Python 3 and Bash |
| Rebuilding the icons | The `cairosvg` and `Pillow` Python packages |

### Running from source

```bash
git clone https://github.com/drabhikroy/scrippy.git
cd scrippy
```

Compile the app into the place the engine looks for it. Then run the engine
with your real SIPS.

```bash
mkdir -p ~/Applications/Scrippy.app/Contents/MacOS ~/Applications/Scrippy.app/Contents/Resources
cp "help/Scrippy Help.md" ~/Applications/Scrippy.app/Contents/Resources/
xcrun swiftc -framework AppKit -framework QuickLookThumbnailing package/app/Sources/*.swift -o ~/Applications/Scrippy.app/Contents/MacOS/Scrippy
bash src/scrippy.sh Example/*.png
```

To try a one-step action instead, pass its format.

```bash
bash src/scrippy.sh --to png Example/*.png
```

### Tests and standards gates

```bash
python3 -m unittest discover -s tests
python3 Scripts/standards_gate.py
```

The engine tests run the real script with stand-ins for SIPS, osascript, and
the app. They pass on Linux as well as macOS. A security group covers
symbolic links at the destination, names with line breaks, names that look
like options, and staging cleanup.

The project tests check that the help page matches its source. The gate
enforces the house writing rules in [CONTRIBUTING.md](CONTRIBUTING.md).

### Building distributable packages

Double-click **Make Public Installer.command**. It builds Scrippy.app for
Apple silicon and Intel. It makes the one-step actions from the main
workflow. It then signs, notarizes, and staples two packages and checks them
with Gatekeeper.

| Package | What it does |
| --- | --- |
| `Scrippy-VERSION.pkg` | Installs Scrippy. Each one-step action is its own component, so people can choose them |
| `Uninstall-Scrippy-VERSION.pkg` | Carries no files. Its one script removes what the installer placed |

Both land in `Release/` with `SHA256SUMS.txt`. The version comes from the
`VERSION` file alone.

To check the installer pages without signing or notarizing, run the command
from Terminal with `--preview`. Unsigned copies of both packages go to
`dist/` and the installer opens.

### Code signing and verification

The build uses the first Developer ID Application and Developer ID Installer
certificates in your keychain. It notarizes with the keychain profile named
**Scrippy**. Create that profile once.

```bash
xcrun notarytool store-credentials "Scrippy"
```

To check a finished package, run these commands.

```bash
pkgutil --check-signature Release/Scrippy-1.0.0.pkg
spctl --assess --type install --verbose=2 Release/Scrippy-1.0.0.pkg
spctl --assess --type install --verbose=2 Release/Uninstall-Scrippy-1.0.0.pkg
```

## Contributing

Conventions, tests, and house writing rules are in
[CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see
[SECURITY.md](SECURITY.md).

## Releases

Each release lists its changes in [CHANGELOG.md](CHANGELOG.md). The installer,
the uninstaller, and `SHA256SUMS.txt` are on the
[Releases](https://github.com/drabhikroy/scrippy/releases) page.

## Credits and background

The example image of Messier 88 is credited to ESA/Hubble and NASA, D. Thilker
and the MAUVE-HST Team. It is used under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and comes from the
[ESA/Hubble picture of the month](https://esahubble.org/images/potm2605a/).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE). The full text is also at
<https://polyformproject.org/licenses/noncommercial/1.0.0>.

Personal use, personal study, hobby projects, teaching, academic research, and
use by charitable, educational, nonprofit, public research, public health, and
government organizations are permitted. Commercial use is not permitted without
a separate license.

Required notice: Copyright 2026 Abhik Roy.

The example image keeps its own CC BY 4.0 license, described under Credits and
background.
