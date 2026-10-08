// Reads Scrippy Help.md, the one source for both the help window and the
// external help page. Only a small part of Markdown is understood, and
// Scripts/make_help.py understands exactly the same part, so the two outputs
// cannot disagree about what the source means.
//
//   # Title            starts a topic
//   ## Heading         a heading inside a topic
//   - item             a bulleted list
//   1. item            a numbered list
//   > text             a note set apart from the text around it
//   ![text](path)      an image, its path relative to the support folder
//   **bold**, `code`, [text](https://...) or [text](#topic) inside any line
//
// Blocks are separated by blank lines. A line that continues a list item or a
// paragraph is joined to it with a space.

import AppKit

enum HelpBlock {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case note(String)
    case image(alt: String, path: String)
}

struct HelpTopic {
    let id: String
    let title: String
    let blocks: [HelpBlock]

    // Plain text for searching, with the inline markers removed so a search
    // for "bold" does not match every topic that uses bold text.
    var searchText: String {
        var parts = [title]
        for block in blocks {
            switch block {
            case .heading(let text), .paragraph(let text), .note(let text): parts.append(text)
            case .bullets(let items), .numbered(let items): parts.append(contentsOf: items)
            case .image(let alt, _): parts.append(alt)
            }
        }
        return HelpInline.plain(parts.joined(separator: " ")).lowercased()
    }
}

// The same rule as slug() in make_help.py. Topic links in the source use it,
// so changing one without the other would break every cross reference.
func helpSlug(_ title: String) -> String {
    var slug = ""
    var lastWasDash = false
    for scalar in title.lowercased().unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII {
            slug.unicodeScalars.append(scalar)
            lastWasDash = false
        } else if !lastWasDash && !slug.isEmpty {
            slug.append("-")
            lastWasDash = true
        }
    }
    // A title ending in punctuation would otherwise leave a trailing dash.
    while slug.hasSuffix("-") { slug.removeLast() }
    return slug
}

func parseHelp(_ source: String, version: String) -> [HelpTopic] {
    let text = source.replacingOccurrences(of: "__VERSION__", with: version)
    var topics: [HelpTopic] = []
    var title: String?
    var blocks: [HelpBlock] = []

    // Blocks are gathered first, then classified by the marker on their
    // first line, which keeps the rules above easy to check by eye.
    var chunks: [[String]] = []
    var current: [String] = []
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            if !current.isEmpty { chunks.append(current); current = [] }
        } else if line.hasPrefix("# ") || line.hasPrefix("## ") {
            // Headings stand alone even without a blank line around them.
            if !current.isEmpty { chunks.append(current); current = [] }
            chunks.append([line])
        } else {
            current.append(line)
        }
    }
    if !current.isEmpty { chunks.append(current) }

    // Text before the first title has no topic to belong to and is dropped,
    // which keeps a stray line at the top of the file out of the help.
    func finishTopic() {
        if let title { topics.append(HelpTopic(id: helpSlug(title), title: title, blocks: blocks)) }
        blocks = []
    }

    for chunk in chunks {
        let first = chunk[0]
        if first.hasPrefix("# ") {
            finishTopic()
            title = String(first.dropFirst(2))
        } else if first.hasPrefix("## ") {
            blocks.append(.heading(String(first.dropFirst(3))))
        } else if first.hasPrefix("- ") {
            blocks.append(.bullets(listItems(chunk) { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : nil }))
        } else if numberedPrefix(first) != nil {
            blocks.append(.numbered(listItems(chunk) { line in numberedPrefix(line).map { String(line.dropFirst($0)) } }))
        } else if first.hasPrefix("> ") {
            blocks.append(.note(chunk.map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }.joined(separator: " ")))
        } else if first.hasPrefix("!["), let image = parseImage(first) {
            blocks.append(image)
        } else {
            blocks.append(.paragraph(chunk.joined(separator: " ")))
        }
    }
    finishTopic()
    return topics
}

// Returns how many characters "12. " takes up, or nil when the line does not
// start a numbered item.
private func numberedPrefix(_ line: String) -> Int? {
    let digits = line.prefix { $0.isNumber }
    guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
    return digits.count + 2
}

// A line that does not start a new item continues the previous one.
private func listItems(_ lines: [String], start: (String) -> String?) -> [String] {
    var items: [String] = []
    for line in lines {
        if let text = start(line) {
            items.append(text)
        } else if !items.isEmpty {
            items[items.count - 1] += " " + line
        }
    }
    return items
}

private func parseImage(_ line: String) -> HelpBlock? {
    guard let close = line.range(of: "]("), line.hasSuffix(")") else { return nil }
    let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
    let path = String(line[close.upperBound..<line.index(before: line.endIndex)])
    return .image(alt: alt, path: path)
}

// Inline markup: **bold**, `code`, and [text](target). Anything else is text.
enum HelpInline {
    static func plain(_ text: String) -> String {
        render(text, font: .systemFont(ofSize: 13), color: .labelColor).string
    }

    static func render(_ text: String, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let code = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular)
        let chars = Array(text)
        var index = 0
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                output.append(NSAttributedString(string: buffer, attributes: [.font: font, .foregroundColor: color]))
                buffer = ""
            }
        }
        func find(_ pattern: String, from start: Int) -> Int? {
            let needle = Array(pattern)
            var position = start
            while position + needle.count <= chars.count {
                if Array(chars[position..<position + needle.count]) == needle { return position }
                position += 1
            }
            return nil
        }

        while index < chars.count {
            if chars[index] == "*", index + 1 < chars.count, chars[index + 1] == "*",
               let end = find("**", from: index + 2) {
                flush()
                output.append(NSAttributedString(string: String(chars[(index + 2)..<end]),
                                                 attributes: [.font: bold, .foregroundColor: color]))
                index = end + 2
            } else if chars[index] == "`", let end = find("`", from: index + 1) {
                flush()
                output.append(NSAttributedString(string: String(chars[(index + 1)..<end]),
                                                 attributes: [.font: code, .foregroundColor: color]))
                index = end + 1
            } else if chars[index] == "[", let middle = find("](", from: index + 1),
                      let end = find(")", from: middle + 2) {
                flush()
                let label = String(chars[(index + 1)..<middle])
                let target = String(chars[(middle + 2)..<end])
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                // Topic links are kept as plain strings and handled by the
                // window. Outside links become URLs that openExternal checks.
                if target.hasPrefix("#") {
                    attributes[.link] = target
                } else if let url = URL(string: target) {
                    attributes[.link] = url
                }
                output.append(NSAttributedString(string: label, attributes: attributes))
                index = end + 1
            } else {
                buffer.append(chars[index])
                index += 1
            }
        }
        flush()
        return output
    }
}
