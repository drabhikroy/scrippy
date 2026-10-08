#!/usr/bin/env python3
"""Sets the LICENSE file as a formatted page for the installer's License pane.

LICENSE is Markdown, which Installer would show with its # marks and link
syntax in plain sight. This turns it into rich text with real headings and
bold terms. The build writes it fresh each time, so it always matches LICENSE.

Rich text is used rather than HTML because an HTML license kept Installer
from going back to the previous page. The text carries no colors, so
Installer draws it in its own text color in light and dark appearance.

    python3 Scripts/make_license.py LICENSE License.rtf
"""

import re
import sys
from pathlib import Path

# The system font, as on the other installer pages.
HEADER = r"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil\fcharset0 .AppleSystemUIFont;}}" + "\n"


def escape(text):
    out = []
    for char in text:
        if char in "\\{}":
            out.append("\\" + char)
        elif ord(char) > 127:
            code = ord(char)
            out.append(f"\\u{code if code < 32768 else code - 65536}?")
        else:
            out.append(char)
    return "".join(out)


def inline(text):
    # Links inside the license point at its own headings, which the pane
    # cannot jump to, so only their words are kept.
    text = re.sub(r"\[([^\]]+)\]\(#[^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    parts = re.split(r"(\*\*\*.+?\*\*\*|\*\*.+?\*\*)", text)
    out = []
    for part in parts:
        if part.startswith("***"):
            out.append(r"{\b\i " + escape(part[3:-3]) + "}")
        elif part.startswith("**"):
            out.append(r"{\b " + escape(part[2:-2]) + "}")
        else:
            out.append(escape(part))
    return "".join(out)


def paragraph(body, size=26, before=0, after=140):
    return f"\\pard\\sb{before}\\sa{after}\\f0\\fs{size} {body}\\par\n"


def convert(markdown):
    out = [HEADER]
    for block in re.split(r"\n\s*\n", markdown.strip()):
        line = " ".join(part.strip() for part in block.splitlines())
        if line.startswith("## "):
            out.append(paragraph(r"{\b " + escape(line[3:]) + "}", size=28, before=180, after=80))
        elif line.startswith("# "):
            out.append(paragraph(r"{\b " + escape(line[2:]) + "}", size=34, after=60))
        elif re.fullmatch(r"<https://[^>\s]+>", line):
            url = line[1:-1]
            link = r'{\field{\*\fldinst{HYPERLINK "' + url + r'"}}{\fldrslt ' + escape(url) + "}}"
            out.append(paragraph(link))
        elif line.startswith("> "):
            out.append(paragraph(inline(line[2:])))
        elif line == "---":
            continue
        else:
            out.append(paragraph(inline(line)))
    out.append("}\n")
    return "".join(out)


def main(arguments):
    if len(arguments) != 2:
        print(__doc__.strip())
        return 1
    source, target = map(Path, arguments)
    target.write_text(convert(source.read_text(encoding="utf-8")), encoding="ascii")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
