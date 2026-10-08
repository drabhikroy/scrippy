"""Checks the parts of the project that only a Mac can run.

Packaging, signing, the app, and the Finder workflow cannot execute in
continuous integration on Linux, so these tests confirm the files that drive
them are well formed and agree with each other.
"""

import plistlib
import re
import struct
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / "workflow" / "Convert with Scrippy.workflow" / "Contents"
BUILD = ROOT / "Make Public Installer.command"
SOURCES = ROOT / "package" / "app" / "Sources"
HELP_MD = ROOT / "help" / "Scrippy Help.md"

sys.path.insert(0, str(ROOT / "Scripts"))
import clean_screenshots  # noqa: E402
import make_license  # noqa: E402
import make_help  # noqa: E402


def read(path):
    return path.read_text(encoding="utf-8")


def swift():
    return "\n".join(read(path) for path in sorted(SOURCES.glob("*.swift")))


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.version = read(ROOT / "VERSION").strip()

    def test_version_is_semantic(self):
        self.assertRegex(self.version, r"^\d+\.\d+\.\d+$")

    def test_workflow_matches_version(self):
        info = plistlib.loads((WORKFLOW / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], self.version)

    def test_every_other_version_comes_from_the_build(self):
        # A typed number in any of these would drift from VERSION the first
        # time someone forgets to update it.
        self.assertIn("__VERSION__", read(HELP_MD))
        self.assertIn("__VERSION__", read(ROOT / "help" / "Scrippy Help.html"))
        self.assertIn('version="__VERSION__"', read(ROOT / "package" / "PublicDistribution.xml"))
        info = plistlib.loads((ROOT / "package" / "app" / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "__VERSION__")

    def test_changelog_has_an_entry_for_this_version(self):
        self.assertIn(f"## [{self.version}]", read(ROOT / "CHANGELOG.md"))


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.build = read(BUILD)
        self.distribution = ET.parse(ROOT / "package" / "PublicDistribution.xml").getroot()

    def test_workflow_runs_the_engine(self):
        document = plistlib.loads((WORKFLOW / "document.wflow").read_bytes())
        command = document["actions"][0]["action"]["ActionParameters"]["COMMAND_STRING"]
        self.assertEqual(command, '/usr/bin/env -i HOME="$HOME" TMPDIR="$TMPDIR" /bin/bash '
                                  '"$HOME/Library/Application Support/Scrippy/bin/scrippy.sh" "$@"')

    def test_one_step_actions_start_with_the_same_cleared_environment(self):
        self.assertIn('/usr/bin/env -i HOME=\\"\\$HOME\\" TMPDIR=\\"\\$TMPDIR\\" /bin/bash', read(BUILD))

    def test_installer_stays_in_the_user_home(self):
        domains = self.distribution.find("domains").attrib
        self.assertEqual(domains["enable_localSystem"], "false")
        self.assertEqual(domains["enable_currentUserHome"], "true")
        self.assertEqual(domains["enable_anywhere"], "false")

    def test_installer_runs_natively_and_states_its_minimum(self):
        # Without hostArchitectures listing arm64, Installer asks Apple
        # silicon Macs to install Rosetta before it will continue.
        self.assertIn("arm64", self.distribution.find("options").attrib["hostArchitectures"])
        minimum = self.distribution.find("allowed-os-versions/os-version").attrib["min"]
        self.assertIn(f'MIN_MACOS="{minimum}"', self.build)
        self.assertEqual(plistlib.loads((ROOT / "package" / "app" / "Info.plist").read_bytes())["LSMinimumSystemVersion"], minimum)

    def test_installer_panes(self):
        for tag, name in (("welcome", "welcome.html"), ("license", "License.rtf"), ("conclusion", "conclusion.html")):
            self.assertEqual(self.distribution.find(tag).attrib["file"], name)
        self.assertIsNone(self.distribution.find("readme"), "the welcome page covers what a Read Me pane would")
        self.assertEqual(self.distribution.find("background").attrib["file"], "background.png")
        self.assertEqual(self.distribution.find("background-darkAqua").attrib["file"], "background-dark.png")
        self.assertIn('"$ROOT"/package/resources/background*.png', self.build)
        self.assertIn('make_license.py" "$ROOT/LICENSE" "$RESOURCES/License.rtf"', self.build)

    def test_installer_pages_follow_dark_appearance(self):
        for page in ("welcome.html", "conclusion.html"):
            self.assertIn("prefers-color-scheme: dark", read(ROOT / "package" / "resources" / page))
        # The license is rich text with no colors, so Installer chooses them.
        self.assertNotIn("\\cf", make_license.convert(read(ROOT / "LICENSE")))
        self.assertNotIn("\\colortbl", make_license.convert(read(ROOT / "LICENSE")))

    def test_installer_pages_use_only_styles_installer_keeps(self):
        # Installer turns each page into styled text. A background is painted
        # behind every line, and borders and generated content are dropped.
        pages = [read(ROOT / "package" / "resources" / name) for name in ("welcome.html", "conclusion.html")]
        pages += [read(page) for page in (ROOT / "package" / "uninstall" / "resources").glob("*.html")]
        for css in [page.split("</style>")[0].split("*/")[-1] for page in pages]:
            for banned in ("background", "border", "::before", "::after", "position:", "list-style"):
                self.assertNotIn(banned, css)

    def test_installer_pages_have_no_pictures(self):
        # Installer leaves a blank bar where a page asks for a picture.
        for page in ("welcome.html", "conclusion.html"):
            self.assertNotIn("<img", read(ROOT / "package" / "resources" / page))

    def test_license_page_shows_no_markdown(self):
        page = make_license.convert(read(ROOT / "LICENSE"))
        self.assertTrue(page.startswith("{\\rtf1"))
        self.assertEqual(page.count("{") - page.count("\\{"), page.count("}") - page.count("\\}"))
        for marker in ("# ", "](", "**", "`", "<https"):
            self.assertNotIn(marker, page)
        self.assertIn("{\\b PolyForm Noncommercial License 1.0.0}", page)
        self.assertIn("{\\b Definitions}", page)
        self.assertIn('HYPERLINK "https://polyformproject.org/licenses/noncommercial/1.0.0"', page)
        self.assertIn("Required Notice: Copyright 2026 Abhik Roy", page)
        page.encode("ascii")

    def test_installer_offers_the_one_step_actions_as_choices(self):
        self.assertEqual(self.distribution.find("options").attrib["customize"], "always")
        keys = re.findall(r'^    "(\w+)\|\w+\|Convert to \w+ with Scrippy"$', self.build, re.M)
        self.assertEqual(keys, ["jpeg", "png", "heic"])
        outline = [line.attrib["choice"] for line in self.distribution.find("choices-outline")]
        self.assertEqual(outline, ["scrippy"] + keys)
        choices = {choice.attrib["id"]: choice for choice in self.distribution.findall("choice")}
        # The main choice looks like the others but always stays selected,
        # since a click cannot change a choice whose selection is fixed.
        main = choices["scrippy"].attrib
        self.assertEqual((main["start_selected"], main["selected"]), ("true", "true"))
        self.assertNotIn("enabled", main)
        self.assertNotIn("start_enabled", main)
        self.assertEqual(choices["scrippy"].find("pkg-ref").attrib["id"], "com.scrippy.pkg")
        refs = {ref.attrib["id"]: ref.text for ref in self.distribution.findall("pkg-ref") if ref.text}
        self.assertEqual(refs["com.scrippy.pkg"], "Scrippy.pkg")
        common = read(SOURCES / "Common.swift")
        for key in keys:
            choice = choices[key]
            self.assertEqual(choice.attrib["start_selected"], "true")
            self.assertNotIn("enabled", choice.attrib)
            identifier = f"com.scrippy.quickaction.{key}.pkg"
            self.assertEqual(choice.find("pkg-ref").attrib["id"], identifier)
            self.assertEqual(refs[identifier], f"Scrippy-{key}.pkg")
            self.assertIn(f'"{key}"', common.split("packageIdentifiers")[1])
        self.assertIn('"com.scrippy.quickaction.$format_key.pkg" "Scrippy-$format_key.pkg"', self.build)

    def test_app_is_built_universal_from_every_source(self):
        self.assertIn("for arch in arm64 x86_64", self.build)
        self.assertIn('-target "$arch-apple-macos$MIN_MACOS"', self.build)
        self.assertIn('"$ROOT"/package/app/Sources/*.swift', self.build)
        self.assertIn("-framework QuickLookThumbnailing", self.build)
        self.assertIn("lipo -create", self.build)

    def test_app_installs_to_applications_and_cannot_be_relocated(self):
        self.assertIn('APP="$PAYLOAD/Applications/Scrippy.app"', self.build)
        self.assertIn("BundleIsRelocatable\" -bool NO", self.build)
        self.assertIn('--component-plist "$plist"', self.build)

    def test_uninstall_package_is_built_and_signed(self):
        self.assertNotIn("Uninstall Scrippy.app", self.build)
        self.assertIn("--nopayload", self.build)
        self.assertIn('UNINSTALL_NAME="Uninstall-Scrippy-$VERSION.pkg"', self.build)
        self.assertIn('product "$UNINSTALL_DISTRIBUTION" "$UNINSTALL_RESOURCES" "$UNINSTALL_COMPONENTS" "$UNINSTALL_NAME"', self.build)
        self.assertIn('shasum -a 256 "$PACKAGE_NAME" "$UNINSTALL_NAME"', self.build)
        distribution = ET.parse(ROOT / "package" / "uninstall" / "UninstallDistribution.xml").getroot()
        self.assertEqual(distribution.find("domains").attrib["enable_currentUserHome"], "true")
        self.assertEqual(distribution.find("domains").attrib["enable_localSystem"], "false")
        self.assertIn('version="__VERSION__"', read(ROOT / "package" / "uninstall" / "UninstallDistribution.xml"))
        self.assertIsNone(distribution.find("license"))

    def test_both_uninstallers_remove_the_same_fixed_paths(self):
        script = read(ROOT / "package" / "uninstall" / "scripts" / "postinstall")
        removed = set(re.findall(r'^    "((?:Applications|Library)/[^"]+)"', script, re.M))
        common = read(SOURCES / "Common.swift")
        expected = {"Applications/Scrippy.app", "Library/Application Support/Scrippy", "Library/Logs/Scrippy"}
        expected |= {f"Library/Services/{name}.workflow" for name in re.findall(r'"(Convert (?:[^"]* )?with Scrippy)"', common)}
        self.assertEqual(removed, expected)
        for identifier in ("com.scrippy.pkg", "com.scrippy.quickaction.jpeg.pkg",
                           "com.scrippy.quickaction.png.pkg", "com.scrippy.quickaction.heic.pkg"):
            self.assertIn(identifier, script)
        for searching in ("find ", "mdfind", "*"):
            self.assertNotIn(searching, script.split("for item in")[1].split("done")[0])
        self.assertIn('"$USER_HOME" == "/"', script)

    def test_preview_build_leaves_the_release_alone(self):
        self.assertIn('if [[ "$PREVIEW" == false ]]; then\n    /bin/rm -rf "$RELEASE"', self.build)
        # Inside product(), a preview returns before anything is signed or
        # copied to Release.
        preview = self.build.split('    if [[ "$PREVIEW" == true ]]; then\n        /usr/bin/productbuild')[1].split("return")[0]
        self.assertNotIn("--sign", preview)
        self.assertNotIn("$RELEASE", preview)
        self.assertIn('    /bin/mkdir -p "$RELEASE"\nfi', self.build)

    def test_release_build_signs_notarizes_and_staples(self):
        for step in ("--options runtime", "notarytool submit", "stapler staple", "spctl --assess --type install",
                     "SHA256SUMS.txt", "chmod -R go-w", "make_help.py\" --check"):
            self.assertIn(step, self.build)

    def test_one_step_actions_are_built(self):
        for name in ("Convert to JPEG with Scrippy", "Convert to PNG with Scrippy", "Convert to HEIC with Scrippy"):
            self.assertIn(name, self.build)
        self.assertIn("--to $format_key", self.build)

    def test_postinstall_only_refreshes_services(self):
        script = read(ROOT / "package" / "public-scripts" / "postinstall")
        self.assertNotIn("sudo", script)
        self.assertIn("Scrippy.app/Contents/MacOS/Scrippy\" refresh-services", script)

    def test_files_the_build_copies_exist(self):
        # The screenshots are taken from the finished app, so they may not
        # exist yet. The build stops with a clear message until they do.
        outputs = {"dist", "Release"}
        for relative in re.findall(r'"\$ROOT/([^"$]+)"', self.build):
            if relative in outputs:
                continue
            self.assertTrue((ROOT / relative).exists(), relative)

    def test_shell_scripts_parse(self):
        for script in (ROOT / "src" / "scrippy.sh", BUILD, ROOT / "package" / "public-scripts" / "postinstall",
                       ROOT / "package" / "uninstall" / "scripts" / "postinstall"):
            result = subprocess.run(["bash", "-n", str(script)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, f"{script.name}: {result.stderr}")


class AppTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / "package" / "app" / "Info.plist").read_bytes())
        self.swift = swift()
        self.engine = read(ROOT / "src" / "scrippy.sh")

    def test_app_names_itself_scrippy(self):
        # The menu bar takes its bold app name from CFBundleName.
        self.assertEqual(self.info["CFBundleName"], "Scrippy")
        self.assertEqual(self.info["CFBundleExecutable"], "Scrippy")
        self.assertIn("2026 Abhik Roy", self.info["NSHumanReadableCopyright"])

    def test_engine_looks_for_the_app_in_fixed_places_only(self):
        self.assertIn('"${HOME}/Applications/Scrippy.app"', self.engine)
        self.assertIn('"/Applications/Scrippy.app"', self.engine)
        code = [line for line in self.engine.splitlines() if not line.lstrip().startswith("#")]
        self.assertFalse(any("mdfind" in line for line in code), "a Spotlight search could find an impostor app")

    def test_menu_bar_has_the_usual_items(self):
        for title in ("About Scrippy", "Uninstall Scrippy…", "Hide Scrippy", "Quit Scrippy", "Copy", "Find…",
                      "Minimize", "Close", "Scrippy Help", "Open Help in Browser", "Latest Version on GitHub", "View License"):
            self.assertIn(f'"{title}"', self.swift)

    def test_windows_never_run_modally(self):
        # A modal session disables menu items aimed anywhere but the window.
        self.assertNotIn("runModal(for:", self.swift)
        self.assertIn("applicationShouldTerminate", self.swift)

    def test_links_only_leave_by_allowed_schemes(self):
        self.assertIn('["https", "x-apple.systempreferences"]', self.swift)
        self.assertEqual(self.swift.count("NSWorkspace.shared.open("), 2,
                         "only openExternal, the external help file, and nothing else may open URLs")

    def test_windows_are_laid_out_by_constraints(self):
        # NSBox does not take its height from content laid out with
        # constraints, and a stack set directly as a window's content view
        # fights the frame the window gives it. Either one collapses a window.
        for source in SOURCES.glob("*.swift"):
            text = read(source)
            self.assertNotIn("NSBox()", text, source.name)
            self.assertNotRegex(text, r"contentView = (root|rootStack)\b", source.name)
        for name in ("HomeWindow.swift", "ChoiceWindow.swift", "ProgressWindow.swift"):
            self.assertIn("setContent(", read(SOURCES / name), name)

    def test_uninstaller_removes_fixed_paths_only(self):
        uninstaller = read(SOURCES / "Uninstaller.swift")
        self.assertIn("trashItem", uninstaller)
        for searching in ("enumerator", "contentsOfDirectory", "removeItem"):
            self.assertNotIn(searching, uninstaller)
        self.assertNotIn("Bundle.main", uninstaller, "the app is removed from its installed path, not wherever this copy runs")
        self.assertIn('home.appendingPathComponent("Applications/Scrippy.app"', read(SOURCES / "Common.swift"))

    def test_quick_action_names_match_the_build(self):
        common = read(SOURCES / "Common.swift")
        for name in re.findall(r'"([^"]+ with Scrippy)"', common):
            self.assertTrue(name == "Convert with Scrippy" or name in read(BUILD), name)

    def test_help_topic_opened_by_the_window_exists(self):
        ids = {make_help.slug(title) for title, _ in make_help.parse(read(HELP_MD))}
        for topic in re.findall(r'showHelp\(topic: "([^"]+)"\)', self.swift):
            self.assertIn(topic, ids)


class HelpTests(unittest.TestCase):
    def setUp(self):
        self.source = read(HELP_MD)
        self.topics = make_help.parse(self.source)

    def test_external_page_matches_the_source(self):
        result = subprocess.run([sys.executable, str(ROOT / "Scripts" / "make_help.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_source_uses_only_the_supported_markdown(self):
        # Anything outside the subset would show as raw symbols in the app.
        for line in self.source.splitlines():
            stripped = line.strip()
            self.assertFalse(stripped.startswith(("|", "###", "* ", "+ ", "<")), stripped)
            self.assertNotIn("__", stripped.replace("__VERSION__", ""), stripped)

    def test_help_states_license_copyright_version_and_latest_release(self):
        for text in ("PolyForm Noncommercial License 1.0.0", "https://polyformproject.org/licenses/noncommercial/1.0.0",
                     "Copyright 2026 Abhik Roy", "version __VERSION__", "https://github.com/drabhikroy/scrippy/releases/latest"):
            self.assertIn(text, self.source)

    def test_help_covers_every_finder_action_and_menu(self):
        for text in ("Convert with Scrippy", "Convert to JPEG with Scrippy", "Convert to PNG with Scrippy",
                     "Convert to HEIC with Scrippy", "Uninstall Scrippy", "Stop"):
            self.assertIn(text, self.source)

    def test_internal_links_resolve(self):
        ids = {make_help.slug(title) for title, _ in self.topics}
        for target in re.findall(r"\]\(#([^)]+)\)", self.source):
            self.assertIn(target, ids)

    def test_topics_have_unique_ids(self):
        ids = [make_help.slug(title) for title, _ in self.topics]
        self.assertEqual(len(ids), len(set(ids)))

    def test_images_point_inside_the_support_folder(self):
        for _, blocks in self.topics:
            for kind, value in blocks:
                if kind == "image":
                    self.assertFalse(value[1].startswith("/") or ".." in value[1])
                    self.assertTrue((ROOT / value[1]).exists(), value[1])


class AssetTests(unittest.TestCase):
    ALLOWED = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"}

    def chunks(self, png):
        data, position, kinds = png.read_bytes(), 8, []
        while position < len(data):
            length = struct.unpack(">I", data[position:position + 4])[0]
            kinds.append(data[position + 4:position + 8])
            position += 12 + length
        return kinds

    def test_every_icon_is_the_chosen_design(self):
        # One arrangement, nine copies, in every file, so no size or variant
        # can drift into a different picture.
        self.assertEqual(sorted(p.name for p in (ROOT / "Assets").glob("*.svg")),
                         ["AppIcon.svg", "Icon-Mono.svg", "Icon-Tile.svg", "Icon-Transparent.svg"])
        for name in ("AppIcon.svg", "Icon-Tile.svg", "Icon-Transparent.svg"):
            self.assertEqual(read(ROOT / "Assets" / name).count('<path d="M512 512L'), 9, name)
        mono = read(ROOT / "Assets" / "Icon-Mono.svg")
        self.assertEqual(mono.split('stroke="currentColor"')[0].count("M"), 9)
        self.assertNotIn("SMALL", read(ROOT / "Scripts" / "make_icons.py"))

    def test_svg_icons_carry_no_metadata(self):
        for svg in (ROOT / "Assets").glob("*.svg"):
            text = read(svg)
            for marker in ("<title", "<desc", "<metadata", "<!--", "inkscape", "sodipodi", "xmlns:dc", "xmlns:rdf"):
                self.assertNotIn(marker, text, f"{svg.name} contains {marker}")

    def test_png_icons_hold_only_image_chunks(self):
        pngs = list((ROOT / "Assets" / "png").glob("*.png"))
        self.assertTrue(pngs)
        for png in pngs:
            self.assertTrue(set(self.chunks(png)) <= self.ALLOWED, png.name)

    def test_installer_backgrounds_add_only_their_resolution(self):
        for name in ("background.png", "background-dark.png"):
            kinds = set(self.chunks(ROOT / "package" / "resources" / name))
            self.assertEqual(kinds - self.ALLOWED, {b"pHYs"}, name)

    def test_no_png_carries_extra_metadata(self):
        # Covers every PNG in the project, including the example image, so a
        # provenance label or other chunk added on the way to a Mac is caught
        # before it can ship. Only the installer backgrounds may also carry their
        # resolution mark.
        for png in ROOT.rglob("*.png"):
            if ".git" in png.parts or "dist" in png.parts:
                continue
            extra = set(self.chunks(png)) - self.ALLOWED
            if png.name in ("background.png", "background-dark.png"):
                extra -= {b"pHYs"}
            self.assertEqual(extra, set(), f"{png.relative_to(ROOT)} carries {sorted(k.decode() for k in extra)}")

    def test_readme_pictures_exist(self):
        for source in re.findall(r'<img src="([^"]+)"', read(ROOT / "README.md")):
            self.assertTrue((ROOT / source).exists(), source)

    def test_screenshot_cleaner_keeps_only_image_chunks(self):
        import tempfile
        import zlib
        source = (ROOT / "Assets" / "png" / "AppIcon-16.png").read_bytes()
        body = b"XML:com.adobe.xmp\x00\x00\x00\x00\x00<x:xmpmeta/>"
        extra = struct.pack(">I", len(body)) + b"iTXt" + body + struct.pack(">I", zlib.crc32(b"iTXt" + body))
        with tempfile.TemporaryDirectory() as folder:
            shot = Path(folder) / "shot.png"
            shot.write_bytes(source[:33] + extra + source[33:])
            self.assertIn(b"iTXt", self.chunks(shot))
            clean_screenshots.strip(shot)
            self.assertEqual(shot.read_bytes(), source)

    def test_example_image_is_shipped_once(self):
        self.assertEqual(len(list(ROOT.rglob("Example Image - Messier 88.png"))), 1)


if __name__ == "__main__":
    unittest.main()
