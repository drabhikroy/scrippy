# Welcome to Scrippy

Scrippy converts images to any format your Mac can write without leaving Finder. It does the work with SIPS, the Scriptable Image Processing System built into macOS, which is where its name comes from.

1. Select an image, several images, or a folder in Finder.
2. Right-click the selection and choose **Quick Actions**, then **Convert with Scrippy**.
3. Choose a format and click **Convert**. The new copy is saved beside the original.

> **Your originals are never changed.** If a name is already taken, Scrippy adds -1, -2, and so on, so an earlier copy is never replaced either.

This help is also available as a page you can open in a browser. Choose **Open Help in Browser** from the Help menu.

# Converting images

Scrippy adds these entries to the **Quick Actions** menu in Finder. The three one-step actions are optional. The installer lets you choose which of them to add.

- **Convert with Scrippy** opens the conversion window, where you can choose any format your Mac can write, pick an image detail setting, and see a size estimate first.
- **Convert to JPEG with Scrippy** converts straight to JPEG with the standard detail setting. No window opens.
- **Convert to PNG with Scrippy** converts straight to PNG.
- **Convert to HEIC with Scrippy** converts straight to HEIC with the standard detail setting.

## Several images or a folder

Select two or more images, or a folder, before choosing an action. Every image is converted to the same format. Scrippy looks only at the files directly inside a selected folder and leaves subfolders alone, so a conversion never reaches further than the files you can see.

## Files Scrippy cannot read

If a file you selected is not an image SIPS can read, Scrippy says so before converting anything, and you can continue with the rest or cancel. Other files inside a selected folder, such as documents, are passed over quietly.

## Showing or hiding the actions

Any action you do not use can be hidden. In Finder, right-click a file, choose **Quick Actions**, then **Customize**, and turn actions on or off. The Scrippy app shows which actions are installed and has a button that opens these settings.

To add a one-step action you left out, run the installer again and select it on the Installation Type page.

# Choosing a format

The format menu is built from what SIPS on your Mac reports it can write, so it can include formats added in a macOS update. The six formats most people want are listed first.

- **JPEG** suits photos, sharing, and broad app support. Compression is lossy, and transparency is not kept.
- **PNG** suits screenshots, text, graphics, and transparency. Photos are often larger as PNG.
- **HEIC** suits photos on Apple devices with small files. Some websites and older apps do not accept it.
- **AVIF** makes very small photo files and can keep transparency. Support in older apps is limited.
- **TIFF** suits editing, print work, and archiving. Files are usually large.
- **PDF** puts the image into a document. Image apps and websites may treat it differently from an image file.
- **JPEG 2000** makes high quality compressed images, but few apps outside of specialized work open it.
- **GIF** suits simple graphics with few colors. It is limited to 256 colors, and Scrippy does not create animation.
- **Texture and icon formats** such as ASTC, KTX, ICNS, and ICO are for specialized graphics work and are rarely right for photos.

The window shows what the selected format is good for and what to keep in mind, and updates as you change your choice. Scrippy remembers the last format and detail setting you converted with.

The preview on the right shows the image you are converting, with its format, size in pixels, and file size. When several images are selected, the caption gives how many there are and their total size, and the preview shows the largest one by name.

# Image detail and file size

JPEG, HEIC, AVIF, and JPEG 2000 can trade a smaller file for some fine detail. When one of them is selected, an **Image detail** menu appears under the format menu.

- **Automatic** uses the standard SIPS setting.
- **Smaller file** compresses most. Fine textures and edges may look softer.
- **Balanced** is a middle choice for everyday photos and sharing.
- **High quality** keeps more detail with a larger file.
- **Very high quality** keeps still more detail. The file usually grows.
- **Highest detail** compresses least. The difference from the step before it may be hard to see.

The one-step actions always use **Automatic**.

# Size estimates

Compression depends on the picture itself, so an estimate cannot come from the file type alone. When you choose an option, Scrippy converts one image to a temporary file and measures it.

- **For one image**, the estimate comes from converting that image with the settings shown.
- **For several images or a folder**, Scrippy converts the largest one and scales the result to the total size of the selection. Different pictures compress differently, so the final total can differ.

Temporary files stay on your Mac. Each one is deleted as soon as it has been measured, and the folder holding them is removed when the conversion ends.

# Progress and stopping

A conversion that finishes quickly shows no progress window. If it is still running after about two seconds, a window appears with the number of images done.

For several images, the window has a **Stop** button. Scrippy finishes the image it is working on, so no half written copy is left, and then stops. The alert afterward says how many images were not started.

When everything converts, a notification confirms it. If anything could not be converted, an alert says how many and offers **Show Log**, which shows the log in Finder. The log gives the reason for each one.

# Menus and shortcuts

While the conversion window, this help, or the Scrippy app is open, Scrippy has a menu bar like any other app.

- **Scrippy** includes About Scrippy, Uninstall Scrippy, and Quit. Quitting from the conversion window cancels the conversion.
- **Edit** has Copy, for taking any note, estimate, or passage of help, and Find, which moves to the search field in this window.
- **Window** has Minimize and Close. Closing the conversion window cancels it.
- **Help** has Scrippy Help, Open Help in Browser, Latest Version on GitHub, and View License.

In the conversion window, Return converts and Escape cancels. Command Question Mark opens this help from anywhere in Scrippy, and Command P prints the topic you are reading.

# About SIPS

SIPS is the Scriptable Image Processing System, an image tool Apple includes with macOS at `/usr/bin/sips`. Scrippy does not install an image library of its own. Every conversion is done by SIPS, so the formats on offer and the results match what your version of macOS supports.

For the full SIPS reference, open Terminal and run `man sips`. To see the formats your Mac can read and write, run `sips --formats`. Apple also describes SIPS in its [Shell Scripting Primer](https://developer.apple.com/library/archive/documentation/OpenSource/Conceptual/ShellScripting/StartingPoints/StartingPoints.html).

# Example image

A photograph of Messier 88, a spiral galaxy, is installed for practice. It has plenty of fine detail, which makes differences between formats and detail settings easy to see. Open the Scrippy app and click **Show Example Image in Finder** to find it.

![Messier 88, a tilted spiral galaxy with a bright center, blue spiral arms, dark dust lanes, and pink star forming regions against a dark background.](Example/Example Image - Messier 88.png)

Image credit ESA/Hubble and NASA, D. Thilker and the MAUVE-HST Team, from the [ESA/Hubble picture of the month](https://esahubble.org/images/potm2605a/), used under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

# Troubleshooting

## The actions are not in the Quick Actions menu

Open the Scrippy app from the Applications folder in your home folder. It lists each action and shows whether it is installed. If an action is installed but missing from Finder, click **Choose Which Actions Appear** and turn it on. If **Convert with Scrippy** is missing, install Scrippy again.

## A file cannot be converted

SIPS can read some formats it cannot write, and some files are damaged or are not images at all. The menu only lists formats your Mac can write. When a conversion fails, **Show Log** in the alert shows the log in Finder, and the log gives the reason SIPS reported.

## The copy could not be saved

Scrippy saves each copy beside its original, so the folder must allow changes. Images on a disk image, a locked folder, or a read-only network share cannot be converted where they are. Copy them somewhere you can write to first.

## The estimate did not match the result

Estimates come from one sample image, and compression depends on what each picture contains. A group of very different images can come out larger or smaller than estimated.

## Scrippy.app could not be found

The Finder actions look for the app in the Applications folder inside your home folder, or in the main Applications folder. If you moved it elsewhere, move it back to one of those, or install Scrippy again.

# Privacy and security

Everything happens on your Mac. Scrippy makes no network connections, collects nothing, and has no updater. Links in the app and in this help, such as the release page and the license, open in your browser only when you click them.

- Copies are written to a private folder first and moved into place in one step, so a half written file is never left behind and an existing file is never replaced.
- Scrippy asks for no special permissions. macOS may ask once whether Scrippy can use a protected folder such as Desktop or Documents.
- The log at `~/Library/Logs/Scrippy/scrippy.log` records failed conversions, including the names of the files involved, and trims itself back once it passes one megabyte.

# Uninstalling Scrippy

Choose **Uninstall Scrippy** from the Scrippy menu while Scrippy is open. After you confirm, Scrippy moves its Finder actions, the app, its support folder with the conversion script, help, and example image, and its log to the Trash. Your own images and every converted copy stay where they are.

You can also download the uninstaller package, `Uninstall-Scrippy-__VERSION__.pkg`, from the [Scrippy releases page](https://github.com/drabhikroy/scrippy/releases/latest) and open it. It removes the same items. Installer names its last button **Install**, which runs the removal.

To remove it by hand instead, move these to the Trash.

- The workflows ending in **with Scrippy** in `~/Library/Services`
- The **Scrippy** folder in `~/Library/Application Support`
- The **Scrippy** folder in `~/Library/Logs`
- **Scrippy** in the Applications folder in your home folder

# Version and license

This is Scrippy version __VERSION__. The newest version is always on the [Scrippy releases page](https://github.com/drabhikroy/scrippy/releases/latest).

Copyright 2026 Abhik Roy. Scrippy is released under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0). Personal use, personal study, hobby projects, teaching, academic research, and use by charitable, educational, nonprofit, public research, public health, and government organizations are permitted. Commercial use is not permitted without a separate license.

Scrippy is provided as is, without warranty of any kind. Keep your originals until you have checked the converted copies.

Scrippy is an independent project with no affiliation with Apple. Apple, macOS, and Finder are trademarks of Apple Inc. The source is at [github.com/drabhikroy/scrippy](https://github.com/drabhikroy/scrippy).
