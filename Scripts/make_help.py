#!/usr/bin/env python3
"""Builds the external help page from help/Scrippy Help.md.

The help window inside Scrippy reads the same Markdown file directly. This
script turns it into help/Scrippy Help.html, a single page that opens in any
browser, prints cleanly, and follows light and dark appearance. Both readers
understand the same small part of Markdown, described at the top of
package/app/Sources/HelpDocument.swift.

Run it from the repository root after editing the help:

    python3 Scripts/make_help.py

The tests run it in check mode and fail when the committed page is stale:

    python3 Scripts/make_help.py --check
"""

import base64
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "help" / "Scrippy Help.md"
OUTPUT = ROOT / "help" / "Scrippy Help.html"
ICON = ROOT / "Assets" / "png" / "AppIcon-128.png"


def slug(title):
    """The same rule as helpSlug in HelpDocument.swift."""
    text = re.sub(r"[^a-z0-9]+", "-", title.lower())
    return text.strip("-")


def parse(source):
    """Returns a list of (title, blocks). Mirrors parseHelp in Swift."""
    # Blocks are gathered first and classified by their first line, the same
    # two passes the Swift reader makes, so the two stay easy to compare.
    chunks, current = [], []
    for raw in source.split("\n"):
        line = raw.strip()
        if not line:
            if current:
                chunks.append(current)
                current = []
        elif line.startswith("# ") or line.startswith("## "):
            if current:
                chunks.append(current)
                current = []
            chunks.append([line])
        else:
            current.append(line)
    if current:
        chunks.append(current)

    topics, title, blocks = [], None, []
    numbered = re.compile(r"^(\d+)\. ")
    for chunk in chunks:
        first = chunk[0]
        if first.startswith("# "):
            if title is not None:
                topics.append((title, blocks))
            title, blocks = first[2:], []
        elif first.startswith("## "):
            blocks.append(("heading", first[3:]))
        elif first.startswith("- "):
            blocks.append(("bullets", list_items(chunk, lambda line: line[2:] if line.startswith("- ") else None)))
        elif numbered.match(first):
            blocks.append(("numbered", list_items(chunk, lambda line: numbered.sub("", line) if numbered.match(line) else None)))
        elif first.startswith("> "):
            blocks.append(("note", " ".join(line[2:] if line.startswith("> ") else line for line in chunk)))
        elif first.startswith("![") and "](" in first and first.endswith(")"):
            alt, path = first[2:-1].split("](", 1)
            blocks.append(("image", (alt, path)))
        else:
            blocks.append(("paragraph", " ".join(chunk)))
    if title is not None:
        topics.append((title, blocks))
    return topics


def list_items(lines, start):
    items = []
    for line in lines:
        text = start(line)
        if text is not None:
            items.append(text)
        elif items:
            items[-1] += " " + line
    return items


INLINE = re.compile(r"\*\*(.+?)\*\*|`(.+?)`|\[(.+?)\]\((.+?)\)")


def inline(text):
    """Bold, code, and links. Outside links open in a new tab."""
    out, position = [], 0
    for match in INLINE.finditer(text):
        out.append(html.escape(text[position:match.start()]))
        bold, code, label, target = match.groups()
        if bold is not None:
            out.append(f"<strong>{html.escape(bold)}</strong>")
        elif code is not None:
            out.append(f"<code>{html.escape(code)}</code>")
        else:
            # Every value from the source is escaped, so a stray angle bracket
            # or quote in the help can never become markup.
            safe = html.escape(target, quote=True)
            extra = "" if target.startswith("#") else ' rel="noopener noreferrer"'
            out.append(f'<a href="{safe}"{extra}>{html.escape(label)}</a>')
        position = match.end()
    out.append(html.escape(text[position:]))
    return "".join(out)


def render_blocks(blocks):
    parts = []
    for kind, value in blocks:
        if kind == "heading":
            parts.append(f"<h3>{inline(value)}</h3>")
        elif kind == "paragraph":
            parts.append(f"<p>{inline(value)}</p>")
        elif kind == "note":
            parts.append(f'<p class="note">{inline(value)}</p>')
        elif kind == "bullets":
            parts.append("<ul>" + "".join(f"<li>{inline(item)}</li>" for item in value) + "</ul>")
        elif kind == "numbered":
            parts.append("<ol>" + "".join(f"<li>{inline(item)}</li>" for item in value) + "</ol>")
        elif kind == "image":
            alt, path = value
            parts.append(f'<figure><img src="{html.escape(path, quote=True)}" alt="{html.escape(alt, quote=True)}" loading="lazy"></figure>')
    return "\n".join(parts)


STYLE = """
:root {
  color-scheme: light dark;
  --bg: #ffffff; --text: #1d1d1f; --muted: #5b5b60; --panel: #f5f5f7;
  --border: #d2d2d7; --accent: #0066cc; --note: #eef4fc;
  font: 17px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #1c1c1e; --text: #f5f5f7; --muted: #b8b8bd; --panel: #2c2c2e;
          --border: #48484a; --accent: #78b7ff; --note: #22324a; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); }
a { color: var(--accent); text-underline-offset: 0.18em; }
a:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; border-radius: 4px; }
.skip { position: absolute; left: 1rem; top: -4rem; padding: 0.6rem 1rem; background: var(--bg);
        border: 1px solid var(--border); border-radius: 8px; z-index: 2; }
.skip:focus { top: 1rem; }
.layout { display: grid; grid-template-columns: 260px minmax(0, 1fr); min-height: 100vh; }
nav { position: sticky; top: 0; align-self: start; height: 100vh; overflow-y: auto;
      padding: 28px 18px; background: var(--panel); border-right: 1px solid var(--border); }
nav .brand { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
nav .brand img { width: 44px; height: 44px; }
nav .brand strong { font-size: 1.1rem; }
nav ol { list-style: none; margin: 0; padding: 0; }
nav li a { display: block; padding: 7px 10px; border-radius: 8px; color: var(--text);
           text-decoration: none; min-height: 32px; }
nav li a:hover, nav li a:focus-visible { background: var(--border); }
main { max-width: 760px; padding: 36px 48px 64px; }
section { padding: 8px 0 28px; border-bottom: 1px solid var(--border); }
section:last-of-type { border-bottom: 0; }
h2 { font-size: 1.7rem; line-height: 1.2; margin: 24px 0 12px; letter-spacing: -0.01em; }
h3 { font-size: 1.12rem; margin: 22px 0 6px; }
p, li { max-width: 68ch; }
li { margin: 6px 0; }
.note { padding: 14px 16px; border-left: 4px solid var(--accent); background: var(--note); border-radius: 8px; }
code { padding: 0.1em 0.35em; border-radius: 5px; background: var(--panel);
       font: 0.9em ui-monospace, SFMono-Regular, Menlo, monospace; }
figure { margin: 18px 0; }
figure img { display: block; width: 100%; height: auto; border-radius: 12px; }
footer { color: var(--muted); font-size: 0.9rem; padding-top: 20px; }
@media (max-width: 760px) {
  .layout { display: block; }
  nav { position: static; height: auto; border-right: 0; border-bottom: 1px solid var(--border); }
  main { padding: 24px 20px 48px; }
}
@media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; transition: none !important; } }
@media print {
  nav, .skip { display: none; }
  .layout { display: block; }
  main { max-width: none; padding: 0; }
  section { break-inside: avoid-page; }
  a { color: inherit; }
}
"""


def build():
    topics = parse(SOURCE.read_text(encoding="utf-8"))
    # The icon is embedded so the page is one self contained file that still
    # shows correctly when copied somewhere on its own.
    icon = base64.b64encode(ICON.read_bytes()).decode("ascii")
    nav = "\n".join(f'<li><a href="#{slug(title)}">{html.escape(title)}</a></li>' for title, _ in topics)
    sections = "\n".join(
        f'<section id="{slug(title)}" aria-labelledby="{slug(title)}-title">\n'
        f'<h2 id="{slug(title)}-title">{html.escape(title)}</h2>\n{render_blocks(blocks)}\n</section>'
        for title, blocks in topics)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scrippy Help</title>
<style>{STYLE}</style>
</head>
<body>
<a class="skip" href="#main">Skip to help</a>
<div class="layout">
<nav aria-label="Help topics">
<div class="brand"><img src="data:image/png;base64,{icon}" alt=""><strong>Scrippy Help</strong></div>
<ol>
{nav}
</ol>
</nav>
<main id="main">
{sections}
<footer><p>Scrippy version __VERSION__. Copyright 2026 Abhik Roy. <a href="https://polyformproject.org/licenses/noncommercial/1.0.0" rel="noopener noreferrer">PolyForm Noncommercial License 1.0.0</a>. <a href="https://github.com/drabhikroy/scrippy/releases/latest" rel="noopener noreferrer">Latest version</a>.</p></footer>
</main>
</div>
</body>
</html>
"""


def main():
    page = build()
    if "--check" in sys.argv:
        # Comparing the whole page catches any change, including one to the
        # styles here that the Markdown alone would not reveal.
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != page:
            print("help/Scrippy Help.html is out of date. Run python3 Scripts/make_help.py.")
            return 1
        print("help/Scrippy Help.html matches the Markdown source.")
        return 0
    OUTPUT.write_text(page, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
