#!/usr/bin/env python3
"""House writing rules, checked across every text file in the repository.

The rules are the ones shared by all of these projects: no em or en dashes,
no contractions, a short list of words that say little, and American
spelling. A hit prints its file and line, and any hit fails the run.

    python3 Scripts/standards_gate.py
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

TEXT_SUFFIXES = {".md", ".sh", ".swift", ".html", ".py", ".xml", ".command", ".yml", ".plist", ".txt"}
EXTRA_NAMES = {"postinstall", "VERSION"}
# LICENSE is the PolyForm text, reproduced word for word, and the fakes play
# the part of Apple tools, so their wording is not ours to change.
SKIP = {"LICENSE"}

DASHES = re.compile("[–—]")
CONTRACTIONS = re.compile(
    r"\b(?:[A-Za-z]+n['’]t|it['’]s|that['’]s|there['’]s|let['’]s|what['’]s|"
    r"(?:I|you|we|they|he|she|it)['’](?:m|re|ve|ll|d))\b", re.IGNORECASE)
BANNED = re.compile(
    r"\b(?:actionable|robust(?:ly|ness)?|leverag(?:e|es|ed|ing)|utiliz(?:e|es|ed|ing|ation)|"
    r"ensur(?:e|es|ed|ing)|enhanc(?:e|es|ed|ing|ement|ements))\b", re.IGNORECASE)
BRITISH = re.compile(
    r"\b(?:colour\w*|behaviour\w*|favour\w*|honour\w*|centre[sd]?|organis(?:e|es|ed|ing|ation)|"
    r"recognis(?:e|es|ed|ing)|analys(?:e|es|ed|ing)|optimis(?:e|es|ed|ing|ation)|catalogue[sd]?|"
    r"grey|travelled|cancelled|modelling|labelled|licence|programme|artefact\w*)\b", re.IGNORECASE)


def tracked_files():
    try:
        listed = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
        paths = [ROOT / name for name in listed]
    except (OSError, subprocess.CalledProcessError):
        paths = [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts]
    for path in paths:
        if path.name in SKIP or "fakes" in path.parts:
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in EXTRA_NAMES:
            yield path


def main():
    failures = 0
    checks = (("dash", DASHES), ("contraction", CONTRACTIONS), ("banned word", BANNED), ("British spelling", BRITISH))
    for path in tracked_files():
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            # The gate names the words it rejects, so its own pattern lines
            # would otherwise fail it.
            if path.name == "standards_gate.py" and re.search(r"re\.compile|\\b|^\s*r\"", line):
                continue
            for name, pattern in checks:
                match = pattern.search(line)
                if match:
                    failures += 1
                    print(f"{path.relative_to(ROOT)}:{number}: {name} '{match.group(0)}'")
    if failures:
        print(f"\n{failures} problem(s) found.")
        return 1
    print("House writing rules: no problems found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
