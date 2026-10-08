# Contributing

Thank you for helping improve Scrippy.

## Before opening a pull request

1. Run the tests and the writing gate. Both must pass.

   ```bash
   python3 -m unittest discover -s tests
   python3 Scripts/standards_gate.py
   ```

2. Keep the engine compatible with Bash 3.2, the version macOS ships as
   `/bin/bash`. That rules out associative arrays, `mapfile`, `${var,,}`, and
   `${var^^}`.
3. Call system tools by absolute path, as the engine already does. A Quick
   Action runs with a minimal `PATH`, and a relative name could pick up a
   different program.
4. Pass every file name and setting to SIPS as its own quoted argument.
   Nothing from a file name or from the window may be evaluated by a shell.
5. Never overwrite a file. A new behavior that writes beside a person's
   images goes through `place_output`, which claims an unused name in one
   step and refuses to replace anything already there.
6. Add an engine test for any change in behavior. The fakes in `tests/fakes`
   can be taught a new case with a keyword in the test image, the way `FAIL`
   and `EMPTY` work.
7. Update the help whenever something a person sees or does changes.

## Changes to the app

Scrippy.app is plain AppKit in `package/app/Sources`, compiled with `swiftc`
for both architectures without an Xcode project. Keep it that way. Test any
change on the oldest supported macOS, which is 11, and check it with
VoiceOver, Full Keyboard Access, light and dark appearance, and Increase
Contrast. New controls need an accessibility label, and symbols that only
decorate need to be hidden from VoiceOver. Status shown in color also needs a
symbol whose shape differs.

Links must go through `openExternal`, which allows only `https` and the System
Settings scheme. Both uninstallers must keep to the fixed list of installed
paths: `InstalledPaths` in the app and the list in
`package/uninstall/scripts/postinstall`. The tests check that they match.

## Changes to the help

Edit `help/Scrippy Help.md`, then regenerate the browser page and commit both:

```bash
python3 Scripts/make_help.py
```

The help uses a small part of Markdown, listed at the top of
`package/app/Sources/HelpDocument.swift`. The project tests reject anything
outside it and fail when the browser page is out of date. Update the help in
the same change as anything a person sees or does.

## Changes to the icon

The icon is generated. Edit `Scripts/make_icons.py` rather than the SVG files,
then run it and commit the SVG and PNG output together. See
[Assets/README.md](Assets/README.md) for how the artwork is constructed.

## Screenshots

Screenshots for the README live in `Assets/screenshots`. A macOS screenshot
carries the display's color profile and other data the project does not ship,
and the tests reject any PNG that holds more than the picture. Run this on a
Mac after adding or replacing one:

```sh
python3 Scripts/clean_screenshots.py Assets/screenshots/*.png
```

## House writing rules

These apply to code comments, documentation, help text, and messages in the
interface, and `Scripts/standards_gate.py` checks them:

- No em or en dashes. Use a comma, a period, or a rewrite.
- No contractions. Write the words out.
- None of the words on the short banned list in `Scripts/standards_gate.py`.
- American spelling.
- Comments explain why the code is the way it is, not what each line does.

## Reporting problems

Bug reports are most useful with the macOS version, the Scrippy version
(shown in About Scrippy and at the foot of the help page), the format chosen, and the matching
lines from `~/Library/Logs/Scrippy/scrippy.log`. Please remove
personal folder paths and file names first.

By contributing, you agree that your contribution is licensed under the
repository's PolyForm Noncommercial License 1.0.0.
