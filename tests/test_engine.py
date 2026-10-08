"""Runs the conversion engine end to end against stand-in tools.

The engine accepts replacement paths for SIPS, osascript, and its install
folder through the environment. These tests point all three at the fakes in
tests/fakes, so the real script runs unchanged on any machine with Bash,
including Linux continuous integration where SIPS does not exist.

    python3 -m unittest discover -s tests
"""

import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "src" / "scrippy.sh"
FAKES = ROOT / "tests" / "fakes"


class EngineCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sips-engine-test-"))
        self.home = self.tmp / "home"
        self.support = self.tmp / "support"
        self.ui_dir = self.tmp / "ui"
        self.photos = self.tmp / "photos"
        for folder in (self.home, self.ui_dir, self.photos):
            folder.mkdir(parents=True)
        helper_dir = self.support / "Scrippy.app" / "Contents" / "MacOS"
        helper_dir.mkdir(parents=True)
        helper = helper_dir / "Scrippy"
        shutil.copy(FAKES / "Scrippy", helper)
        helper.chmod(helper.stat().st_mode | stat.S_IEXEC)
        self.sips_log = self.tmp / "sips.log"
        self.osa_log = self.tmp / "osascript.log"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def image(self, name, fmt="png", extra="", folder=None):
        path = (folder or self.photos) / name
        path.write_text(f"IMG:{fmt}\n{extra}\n")
        return path

    def run_engine(self, *paths, choice="jpeg\t75", osa_exit=0, ui_exit=0):
        env = self.engine_env(choice, osa_exit, ui_exit)
        return subprocess.run(["/bin/bash", str(ENGINE), *map(str, paths)], env=env,
                              capture_output=True, text=True, timeout=60)

    def engine_env(self, choice="jpeg\t75", osa_exit=0, ui_exit=0):
        return {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": str(self.home),
            "TMPDIR": str(self.tmp),
            "SIPS_BIN": str(FAKES / "sips"),
            "OSASCRIPT_BIN": str(FAKES / "osascript"),
            "SCRIPPY_APP": str(self.support / "Scrippy.app"),
            "FAKE_LOG": str(self.sips_log),
            "FAKE_OSA_LOG": str(self.osa_log),
            "FAKE_OSA_EXIT": str(osa_exit),
            "FAKE_UI_DIR": str(self.ui_dir),
            "FAKE_CHOICE": choice,
            "FAKE_UI_EXIT": str(ui_exit),
        }

    def osa_text(self):
        return self.osa_log.read_text() if self.osa_log.exists() else ""

    def sips_calls(self):
        return self.sips_log.read_text().splitlines() if self.sips_log.exists() else []

    def log_text(self):
        log = self.home / "Library" / "Logs" / "Scrippy" / "scrippy.log"
        return log.read_text() if log.exists() else ""


class ConversionTests(EngineCase):
    def test_single_image_is_converted_beside_the_original(self):
        source = self.image("galaxy.png")
        result = self.run_engine(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        copy = self.photos / "galaxy.jpg"
        self.assertTrue(copy.exists())
        self.assertIn("format=jpeg quality=75", copy.read_text())
        self.assertEqual(source.read_text(), "IMG:png\n\n", "the original must not change")
        self.assertIn("display notification", self.osa_text())

    def test_existing_names_are_never_overwritten(self):
        source = self.image("galaxy.png")
        (self.photos / "galaxy.jpg").write_text("earlier copy")
        (self.photos / "galaxy-1.jpg").write_text("another earlier copy")
        self.run_engine(source)
        self.assertEqual((self.photos / "galaxy.jpg").read_text(), "earlier copy")
        self.assertEqual((self.photos / "galaxy-1.jpg").read_text(), "another earlier copy")
        self.assertTrue((self.photos / "galaxy-2.jpg").exists())

    def test_converting_to_the_same_type_keeps_the_original(self):
        source = self.image("photo.jpg", fmt="jpeg")
        self.run_engine(source)
        self.assertEqual(source.read_text(), "IMG:jpeg\n\n")
        self.assertTrue((self.photos / "photo-1.jpg").exists())

    def test_automatic_quality_passes_no_format_options(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="jpeg\tauto")
        self.assertIn("quality=none", (self.photos / "galaxy.jpg").read_text())

    def test_format_without_detail_menu_passes_no_format_options(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="tiff\t__NONE__")
        self.assertIn("format=tiff quality=none", (self.photos / "galaxy.tif").read_text())

    def test_format_known_only_by_identifier_gets_a_clean_extension(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="org.khronos.ktx2\t__NONE__")
        self.assertTrue((self.photos / "galaxy.ktx2").exists())

    def test_hidden_name_keeps_its_whole_stem(self):
        source = self.image(".galaxy")
        self.run_engine(source)
        self.assertTrue((self.photos / ".galaxy.jpg").exists())


class SelectionTests(EngineCase):
    def test_folder_is_read_one_level_deep(self):
        album = self.photos / "album"
        nested = album / "nested"
        nested.mkdir(parents=True)
        self.image("a.png", folder=album)
        self.image("b.heic", fmt="heic", folder=album)
        (album / "notes.txt").write_text("not an image")
        self.image("deep.png", folder=nested)
        result = self.run_engine(album)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((album / "a.jpg").exists())
        self.assertTrue((album / "b.jpg").exists())
        self.assertFalse((nested / "deep.jpg").exists())
        self.assertNotIn("skipped", self.osa_text(), "non-images inside a folder are skipped quietly")

    def test_folder_and_file_inside_it_convert_once(self):
        album = self.photos / "album"
        album.mkdir()
        inside = self.image("a.png", folder=album)
        self.run_engine(album, inside)
        self.assertTrue((album / "a.jpg").exists())
        self.assertFalse((album / "a-1.jpg").exists())

    def test_unreadable_file_picked_directly_is_reported(self):
        good = self.image("good.png")
        bad = self.photos / "notes.txt"
        bad.write_text("plain text")
        self.run_engine(good, bad)
        self.assertIn("Some selected files will be skipped", self.osa_text())
        self.assertTrue((self.photos / "good.jpg").exists())

    def test_cancel_on_skip_warning_converts_nothing(self):
        good = self.image("good.png")
        bad = self.photos / "notes.txt"
        bad.write_text("plain text")
        self.run_engine(good, bad, osa_exit=1)
        self.assertFalse((self.photos / "good.jpg").exists())

    def test_clean_exit_without_a_format_line_counts_as_unreadable(self):
        quiet = self.image("odd.png", extra="SILENT")
        self.run_engine(quiet)
        self.assertIn("This file cannot be converted", self.osa_text())
        self.assertEqual(list(self.ui_dir.iterdir()), [], "the window must not open")

    def test_empty_folder_says_no_images_were_found(self):
        empty = self.photos / "empty"
        empty.mkdir()
        self.run_engine(empty)
        self.assertIn("No images found", self.osa_text())

    def test_no_selection_does_nothing(self):
        result = self.run_engine()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.osa_text(), "")


class WindowTests(EngineCase):
    def test_menu_lists_only_writable_formats_once_each(self):
        self.run_engine(self.image("galaxy.png"))
        rows = [line.split("\t") for line in (self.ui_dir / "choices.tsv").read_text().splitlines()]
        titles = [row[1] for row in rows]
        self.assertEqual(len(titles), len(set(titles)), "a label appears twice")
        self.assertNotIn("DNG", titles, "a read-only format reached the menu")
        self.assertIn("JPEG 2000", titles)
        self.assertIn("ATX", titles)
        self.assertTrue(all(len(row) == 6 for row in rows))

    def test_detail_menu_is_offered_only_for_lossy_formats(self):
        self.run_engine(self.image("galaxy.png"))
        keys = {line.split("\t")[0] for line in (self.ui_dir / "quality.tsv").read_text().splitlines()}
        self.assertEqual(keys, {"jpeg", "heic", "jp2"})

    def test_largest_image_is_used_for_the_estimate(self):
        small = self.image("small.png")
        large = self.image("large.png", extra="x" * 5000)
        self.run_engine(small, large)
        args = (self.ui_dir / "args.txt").read_text().splitlines()
        self.assertEqual(args[5], str(large))
        self.assertEqual(args[8], "2")

    def test_caption_gives_format_pixels_and_size(self):
        self.run_engine(self.image("galaxy.png"))
        caption = (self.ui_dir / "args.txt").read_text().splitlines()[3]
        self.assertRegex(caption, r"^PNG • 1200 × 800 pixels • \d+ B$")

    def test_caption_leaves_out_pixels_sips_cannot_read(self):
        self.run_engine(self.image("galaxy.png", extra="NOSIZE"))
        caption = (self.ui_dir / "args.txt").read_text().splitlines()[3]
        self.assertRegex(caption, r"^PNG • \d+ B$")

    def test_caption_for_several_names_the_image_shown(self):
        self.run_engine(self.image("small.png"), self.image("large.png", extra="x" * 5000))
        caption = (self.ui_dir / "args.txt").read_text().splitlines()[3]
        self.assertTrue(caption.startswith("2 images • "), caption)
        self.assertTrue(caption.endswith("The preview shows the largest, large.png."), caption)

    def test_cancel_in_window_converts_nothing(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="__CANCEL__")
        self.assertFalse((self.photos / "galaxy.jpg").exists())
        self.assertFalse(any("--out" in call for call in self.sips_calls()))

    def test_unlisted_format_from_window_is_refused(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="dng\t__NONE__")
        self.assertIn("Format unavailable", self.osa_text())
        self.assertFalse(any("--out" in call for call in self.sips_calls()))

    def test_quality_that_is_not_a_number_is_ignored(self):
        source = self.image("galaxy.png")
        self.run_engine(source, choice="jpeg\t75;rm")
        self.assertIn("quality=none", (self.photos / "galaxy.jpg").read_text())

    def test_window_failure_is_logged_and_reported(self):
        self.run_engine(self.image("galaxy.png"), ui_exit=2)
        self.assertIn("could not open", self.osa_text())
        self.assertIn("exited with status 2", self.log_text())

    def test_missing_window_helper_asks_for_reinstall(self):
        (self.support / "Scrippy.app" / "Contents" / "MacOS" / "Scrippy").unlink()
        self.run_engine(self.image("galaxy.png"))
        self.assertIn("could not be found", self.osa_text())


class SecurityTests(EngineCase):
    """Each test covers one way a file name or a planted link could steer a copy somewhere else."""

    def test_dangling_symlink_at_the_chosen_name_is_not_written_through(self):
        outside = self.tmp / "outside"
        outside.mkdir()
        (self.photos / "galaxy.jpg").symlink_to(outside / "planted.jpg")
        self.run_engine(self.image("galaxy.png"))
        self.assertFalse((outside / "planted.jpg").exists(), "the copy was written through a symbolic link")
        self.assertTrue((self.photos / "galaxy-1.jpg").is_file())

    def test_symlink_to_an_existing_file_is_left_alone(self):
        victim = self.tmp / "important.txt"
        victim.write_text("keep me")
        (self.photos / "galaxy.jpg").symlink_to(victim)
        self.run_engine(self.image("galaxy.png"))
        self.assertEqual(victim.read_text(), "keep me")
        self.assertTrue((self.photos / "galaxy-1.jpg").is_file())

    def test_name_with_a_line_break_is_never_split_into_two_paths(self):
        album = self.photos / "album"
        album.mkdir()
        self.image("trap\nbait.png", folder=album)
        # If the name were split, the second half would be read relative to
        # the working folder, where this decoy waits to be converted.
        self.image("bait.png", folder=self.tmp)
        result = subprocess.run(["/bin/bash", str(ENGINE), str(album)], cwd=self.tmp,
                                env=self.engine_env(), capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.tmp / "bait.jpg").exists())
        self.assertEqual([p.name for p in album.iterdir() if p.suffix == ".jpg"], [])

    def test_selected_name_with_a_line_break_is_reported(self):
        odd = self.image("odd\nname.png")
        self.run_engine(odd, self.image("fine.png"))
        self.assertIn("Some selected files will be skipped", self.osa_text())
        self.assertTrue((self.photos / "fine.jpg").exists())

    def test_relative_name_starting_with_a_dash_reaches_sips_as_a_path(self):
        self.image("-weird.png")
        result = subprocess.run(["/bin/bash", str(ENGINE), "-weird.png"], cwd=self.photos,
                                env=self.engine_env(), capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.photos / "-weird.jpg").exists())
        self.assertTrue(all(" -weird.png" not in call for call in self.sips_calls()))

    def test_staging_folders_are_always_removed(self):
        self.run_engine(self.image("good.png"), self.image("bad.png", extra="FAIL"), self.image("hollow.png", extra="EMPTY"))
        self.assertEqual([p.name for p in self.photos.iterdir() if p.name.startswith(".scrippy-")], [])

    def test_sips_never_writes_to_the_final_name(self):
        self.run_engine(self.image("galaxy.png"))
        writes = [call for call in self.sips_calls() if "--out" in call]
        self.assertEqual(len(writes), 1)
        self.assertIn("/.scrippy-", writes[0])

    @unittest.skipIf(os.geteuid() == 0, "folder permissions do not apply to root")
    def test_read_only_folder_is_reported_not_crashed(self):
        locked = self.photos / "locked"
        locked.mkdir()
        source = self.image("galaxy.png", folder=locked)
        locked.chmod(0o555)
        try:
            self.run_engine(source)
        finally:
            locked.chmod(0o755)
        self.assertIn("cannot be written to", self.log_text())


class EnvironmentTests(EngineCase):
    def test_engine_needs_no_path(self):
        # The Finder actions start the engine through env -i, which leaves no
        # PATH, so every program the engine runs must be named in full.
        env = self.engine_env()
        del env["PATH"]
        result = subprocess.run(["/bin/bash", str(ENGINE), str(self.image("galaxy.png"))], env=env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("command not found", result.stderr)
        self.assertTrue((self.photos / "galaxy.jpg").exists())


class StopTests(EngineCase):
    def test_stop_finishes_the_current_image_and_skips_the_rest(self):
        first = self.image("a.png", extra="STOP")
        self.run_engine(first, self.image("b.png"), self.image("c.png"))
        self.assertTrue((self.photos / "a.jpg").exists())
        self.assertFalse((self.photos / "b.jpg").exists())
        self.assertFalse((self.photos / "c.jpg").exists())
        self.assertIn("Conversion stopped", self.osa_text())
        self.assertIn("stopped by the person with 2 of 3 not started", self.log_text())


class OrderingTests(EngineCase):
    def test_common_formats_come_first_in_a_fixed_order(self):
        self.run_engine(self.image("galaxy.png"))
        rows = [line.split("\t") for line in (self.ui_dir / "choices.tsv").read_text().splitlines()]
        common = [row[1] for row in rows if row[5] == "common"]
        other = [row[1] for row in rows if row[5] == "other"]
        self.assertEqual(common, ["JPEG", "PNG", "HEIC", "TIFF"])
        self.assertEqual(other, sorted(other, key=str.lower))
        self.assertEqual([row[1] for row in rows], common + other)


class DirectActionTests(EngineCase):
    """The one-step Finder actions, which pass --to and skip the window."""

    def test_direct_action_converts_without_opening_the_window(self):
        source = self.image("galaxy.png")
        result = self.run_engine("--to", "jpeg", source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("format=jpeg quality=none", (self.photos / "galaxy.jpg").read_text())
        self.assertEqual(list(self.ui_dir.iterdir()), [], "the window must not open")

    def test_direct_action_works_for_png_and_heic(self):
        source = self.image("photo.jpg", fmt="jpeg")
        self.run_engine("--to", "png", source)
        self.run_engine("--to", "heic", source)
        self.assertTrue((self.photos / "photo.png").exists())
        self.assertTrue((self.photos / "photo.heic").exists())

    def test_direct_action_refuses_a_format_this_mac_cannot_write(self):
        source = self.image("galaxy.png")
        self.run_engine("--to", "dng", source)
        self.assertIn("This Mac cannot write", self.osa_text())
        self.assertFalse(any("--out" in call for call in self.sips_calls()))

    def test_direct_action_runs_without_the_app(self):
        (self.support / "Scrippy.app" / "Contents" / "MacOS" / "Scrippy").unlink()
        source = self.image("galaxy.png")
        self.run_engine("--to", "png", source)
        self.assertTrue((self.photos / "galaxy-1.png").exists())
        self.assertNotIn("reinstall", self.osa_text())

    def test_direct_action_with_nothing_selected_does_nothing(self):
        result = self.run_engine("--to", "jpeg")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.osa_text(), "")


class FailureTests(EngineCase):
    def test_failures_are_logged_with_the_reason(self):
        good = self.image("good.png")
        bad = self.image("bad.png", extra="FAIL")
        self.run_engine(good, bad)
        log = self.log_text()
        self.assertIn("1 of 2 could not be converted", log)
        self.assertIn(str(bad), log)
        self.assertIn("could not write", log)
        self.assertIn("Show Log", self.osa_text())

    def test_empty_output_is_removed_and_counted_as_failure(self):
        hollow = self.image("hollow.png", extra="EMPTY")
        self.run_engine(hollow)
        self.assertFalse((self.photos / "hollow.jpg").exists())
        self.assertIn("could not be converted", self.log_text())

    def test_oversized_log_is_trimmed(self):
        log_dir = self.home / "Library" / "Logs" / "Scrippy"
        log_dir.mkdir(parents=True)
        (log_dir / "scrippy.log").write_text("old line\n" * 300000)
        self.run_engine(self.image("galaxy.png"))
        self.assertLessEqual((log_dir / "scrippy.log").stat().st_size, 1048576)

    def test_work_folder_is_removed(self):
        self.run_engine(self.image("galaxy.png"))
        leftovers = [p for p in self.tmp.iterdir() if p.name.startswith("scrippy.")]
        self.assertEqual(leftovers, [])


if __name__ == "__main__":
    unittest.main()
