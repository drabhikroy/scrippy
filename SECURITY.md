# Security policy

## What Scrippy can do

Scrippy is a shell script, a small signed app, and up to four Automator
Quick Actions. It has no network code, no updater, no telemetry, no login item, and
no background process. Links in the app and its help, such as the release
page and the license text, open in the browser only when a person clicks
them. Nothing runs until a
person chooses a Scrippy action in Finder or opens the app, and nothing keeps
running afterward.

The installer writes only into the current account:

- `~/Applications/Scrippy.app`
- `~/Library/Services/`, the workflows whose names end in `with Scrippy`
- `~/Library/Application Support/Scrippy`

It asks for no administrator password, refuses to install anywhere else, and
pins the app in place so an upgrade is never redirected to another copy with
the same identifier.

## Programs it starts

The engine runs a fixed set of system tools by absolute path: `/usr/bin/sips`
to read and convert images, `/usr/bin/osascript` to show alerts and
notifications, and standard file tools from `/usr/bin` and `/bin`. The app
starts `/usr/bin/sips` for size estimates and, when uninstalling,
`/usr/sbin/pkgutil` to forget its install record. No file name, format name,
or setting is ever passed through a shell for interpretation. Each one reaches
its program as a separate argument. AppleScript receives values only as
arguments, never as part of the script text.

The engine starts Scrippy.app only from `~/Applications/Scrippy.app` or
`/Applications/Scrippy.app`. It does not search Spotlight for the app, which
would also find any other program claiming the same bundle identifier.

The format the app returns is checked against the list the engine built from
`sips --formats` on the same run, and the detail setting must be a whole
number. A tampered or broken app therefore cannot make the engine pass an
arbitrary option to SIPS.

## Files it touches

- Reads the files a person selected, and the files directly inside a selected
  folder, to ask SIPS what format they are. Every path is made absolute
  first, so no name can reach SIPS looking like an option.
- Skips any file whose name contains a line break, since lists of paths are
  kept one per line and such a name could otherwise be read as two paths.
- Has SIPS write each copy into a new private staging folder beside the
  original, then claims a free final name with a hard link, which fails
  rather than overwriting anything that appears at that name. Names held by a
  symbolic link, including one whose target is missing, are treated as taken,
  so a copy is never written through a link to somewhere else. Volumes without
  hard links fall back to a move that also refuses to overwrite.
- Removes each staging folder after use, and again on exit if the run is
  interrupted.
- Writes temporary estimate files inside a private work folder that is
  deleted when the run ends.
- Appends failed conversions to `~/Library/Logs/Scrippy/scrippy.log`, which is
  cut back to its most recent half when it passes one megabyte. The log
  contains the paths of files that failed.

Uninstall Scrippy in the Scrippy menu moves only the fixed paths listed above,
and the log folder, to the Trash. The uninstaller package deletes the same paths and nothing else.
Neither searches for files to remove, so a copy of Scrippy kept anywhere else
is left alone.

## Links and help

Links can leave the app only by `https` or the System Settings scheme. The
help window resolves links between topics itself and passes every other link
through that check. Help images are read only from inside the Scrippy support
folder.

## Permissions

Scrippy requests no Full Disk Access, no Accessibility, no Automation, no
camera, no microphone, and no location. Showing the log uses `open -R`, which
needs no Automation permission. macOS may ask once whether a Scrippy action
can use a protected folder such as Desktop or Documents, as it does for any
app.

## Signing

The app bundle is signed with a Developer ID Application certificate and the
hardened runtime, which seals its program, icon, and help text together. The
installer and uninstaller packages are each signed with a Developer ID
Installer certificate, notarized by Apple, and stapled. Nothing in the payload is writable by other accounts. Each
release publishes a `SHA256SUMS.txt` so a download can be checked before it
is opened.

## Known limits

The engine script and the support folder live in the person's own Library,
where any program running as that person could change them. That is true of
every per-user installation and needs a compromised account to exploit. SIPS
itself decides how much memory a very large image needs, and Scrippy does not
limit it.

## Reporting a vulnerability

Please report a vulnerability privately through a [GitHub security
advisory](https://github.com/drabhikroy/scrippy/security/advisories/new)
rather than a public issue. Include the macOS version, the Scrippy version,
steps to reproduce, and the relevant part of the log, with personal folder
paths and file names removed.
