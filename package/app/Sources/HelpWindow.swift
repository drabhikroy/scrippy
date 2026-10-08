// The help window: topics on the left with a search field above them, the
// chosen topic on the right. It reads Scrippy Help.md from the app bundle, so
// help works even if the support folder with the external copy is missing.

import AppKit

final class HelpWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
                                  NSTextViewDelegate, NSSearchFieldDelegate {
    // Every topic in the source, and the ones matching the current search.
    // Rows in the table always index into shown, never into topics.
    private let topics: [HelpTopic]
    private var shown: [HelpTopic]
    private let table = NSTableView()
    private let search = NSSearchField()
    // A text view built by scrollableTextView() arrives already sized and
    // wired to its scroll view, which a hand made one has to be taught.
    private let textScroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { textScroll.documentView as! NSTextView }
    private let emptyLabel = makeLabel("No topics match.", size: 13, color: .secondaryLabelColor)

    init() {
        // A copy missing its help text still opens a window that says what
        // went wrong, rather than an empty one.
        let url = Bundle.main.url(forResource: "Scrippy Help", withExtension: "md")
        let source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "# Help\n\nThe help text is missing from this copy of Scrippy. Please reinstall it."
        topics = parseHelp(source, version: appVersion)
        shown = topics

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Scrippy Help"
        window.minSize = NSSize(width: 640, height: 420)
        // Remembers where the person last put the window and how large it was.
        window.setFrameAutosaveName("ScrippyHelp")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildLayout(in: window)
        if window.frame.origin == .zero { window.center() }
    }

    required init?(coder: NSCoder) { nil }

    // Opening help again brings the existing window forward, keeping the
    // topic and search the person left it on unless a topic is asked for.
    func show(topic id: String?) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let id, let index = shown.firstIndex(where: { $0.id == id }) {
            select(index)
        } else if table.selectedRow < 0, !shown.isEmpty {
            select(0)
        }
    }

    @objc func focusSearch(_ sender: Any?) {
        window?.makeFirstResponder(search)
    }

    @objc func printTopic(_ sender: Any?) {
        // Swift names NSView's print(_:) printView(_:), so it does not clash
        // with the global print function.
        textView.printView(sender)
    }

    @objc func openInBrowser(_ sender: Any?) {
        (NSApp.delegate as? AppController)?.openExternalHelp(sender)
    }

    private func buildLayout(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        search.placeholderString = "Search Help"
        search.delegate = self
        // Results update with each keystroke, since the whole help is small
        // enough to search instantly.
        search.sendsSearchStringImmediately = true
        search.translatesAutoresizingMaskIntoConstraints = false
        search.setAccessibilityLabel("Search help topics")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("topic"))
        table.addTableColumn(column)
        // A source list matches the sidebars in Finder and Mail, which is the
        // look people expect for a list of places to go.
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Help topics")
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false

        let browserButton = NSButton(title: "Open in Browser", target: self, action: #selector(openInBrowser(_:)))
        let printButton = NSButton(title: "Print…", target: self, action: #selector(printTopic(_:)))
        // Command P prints the topic on screen, as it would in a document.
        printButton.keyEquivalent = "p"
        printButton.keyEquivalentModifierMask = .command
        for button in [browserButton, printButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }
        let buttons = compactStack(axis: .horizontal, spacing: 8)
        buttons.addArrangedSubview(browserButton)
        buttons.addArrangedSubview(printButton)

        // The sidebar material lets the desktop tint through, as other Mac
        // sidebars do, and adjusts itself for Reduce Transparency.
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(search)
        sidebar.addSubview(tableScroll)
        sidebar.addSubview(buttons)

        // Selectable but not editable, so passages can be copied into a note
        // or a message without risk of changing the help.
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.setAccessibilityLabel("Help topic")
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        // Shown in place of the list when a search finds nothing, so an empty
        // sidebar is never mistaken for missing help.
        emptyLabel.isHidden = true
        content.addSubview(sidebar)
        content.addSubview(textScroll)
        sidebar.addSubview(emptyLabel)

        // The sidebar keeps a fixed width and the topic takes the rest, so
        // widening the window gives the reading column more room.
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 240),
            search.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 14),
            search.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            tableScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            tableScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            emptyLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            buttons.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),
            textScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            textScroll.topAnchor.constraint(equalTo: content.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // Selecting a row and showing its topic always happen together, whether
    // the change comes from a click, a search, or a link.
    private func select(_ index: Int) {
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        display(shown[index])
    }

    private func display(_ topic: HelpTopic) {
        textView.textStorage?.setAttributedString(HelpRenderer.render(topic))
        textView.scrollToBeginningOfDocument(nil)
        // VoiceOver announces the new topic, since the text changes without
        // focus moving there.
        NSAccessibility.post(element: textView, notification: .valueChanged)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Cells are plain labels made on demand. With a dozen topics, reusing
        // them would add code without any noticeable gain.
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: shown[row].title)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard shown.indices.contains(table.selectedRow) else { return }
        display(shown[table.selectedRow])
    }

    // MARK: Search

    func controlTextDidChange(_ notification: Notification) {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        // Every word must appear somewhere in the topic, in any order, which
        // matches how people type a few words they remember.
        let words = query.split(separator: " ").map(String.init)
        shown = words.isEmpty ? topics : topics.filter { topic in
            words.allSatisfy { topic.searchText.contains($0) }
        }
        table.reloadData()
        emptyLabel.isHidden = !shown.isEmpty
        if !shown.isEmpty { select(0) } else { textView.string = "" }
    }

    // MARK: Links

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let target = link as? String, target.hasPrefix("#") {
            let id = String(target.dropFirst())
            // A link can point at a topic the current search has hidden, so the
            // search is cleared first rather than leaving the click with no effect.
            if !shown.contains(where: { $0.id == id }) {
                search.stringValue = ""
                shown = topics
                table.reloadData()
                emptyLabel.isHidden = true
            }
            if let index = shown.firstIndex(where: { $0.id == id }) { select(index) }
        } else if let url = link as? URL {
            openExternal(url)
        }
        // Handled here in every case, so AppKit never opens a link on its own.
        return true
    }
}

// Turns a topic into styled text. Colors are the system's semantic colors, so
// the text follows light and dark appearance and Increase Contrast.
enum HelpRenderer {
    // A slightly larger body size than controls use, since help is read in
    // paragraphs rather than glanced at.
    static let body = NSFont.systemFont(ofSize: 14)

    static func render(_ topic: HelpTopic) -> NSAttributedString {
        let output = NSMutableAttributedString()
        append(output, topic.title, font: .systemFont(ofSize: 24, weight: .bold), before: 0, after: 14)
        for block in topic.blocks {
            switch block {
            case .heading(let text):
                append(output, text, font: .systemFont(ofSize: 16, weight: .semibold), before: 12, after: 6)
            case .paragraph(let text):
                output.append(paragraph(HelpInline.render(text, font: body, color: .labelColor)))
            case .note(let text):
                output.append(note(HelpInline.render(text, font: body, color: .labelColor)))
            case .bullets(let items):
                for item in items { output.append(listItem("•", item)) }
                output.append(spacer())
            case .numbered(let items):
                for (index, item) in items.enumerated() { output.append(listItem("\(index + 1).", item)) }
                output.append(spacer())
            case .image(let alt, let path):
                output.append(image(alt: alt, path: path))
            }
        }
        return output
    }

    private static func style(before: CGFloat = 0, after: CGFloat = 10, indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = 3
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    private static func append(_ output: NSMutableAttributedString, _ text: String, font: NSFont, before: CGFloat, after: CGFloat) {
        output.append(NSAttributedString(string: text + "\n", attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style(before: before, after: after),
        ]))
    }

    private static func paragraph(_ text: NSMutableAttributedString) -> NSAttributedString {
        text.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        text.addAttribute(.paragraphStyle, value: style(), range: NSRange(location: 0, length: text.length))
        return text
    }

    // A note sits in one tinted box with an accent bar on its left. A text
    // block draws the box around the whole paragraph, where a background
    // color on the text would be painted line by line, with gaps between.
    private static func note(_ text: NSMutableAttributedString) -> NSAttributedString {
        let block = NSTextBlock()
        block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        block.setWidth(12, type: .absoluteValueType, for: .padding)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(.controlAccentColor, for: .minX)
        block.setWidth(12, type: .absoluteValueType, for: .margin, edge: .maxY)
        let noteStyle = style(after: 0)
        noteStyle.textBlocks = [block]
        text.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        text.addAttribute(.paragraphStyle, value: noteStyle, range: NSRange(location: 0, length: text.length))
        return text
    }

    // A hanging indent keeps wrapped lines aligned with the text, not the
    // bullet, which is how lists read everywhere else on the Mac.
    private static func listItem(_ marker: String, _ text: String) -> NSAttributedString {
        let line = NSMutableAttributedString(string: "\(marker)\t", attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor])
        line.append(HelpInline.render(text, font: body, color: .labelColor))
        line.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        let list = style(after: 4, indent: 22)
        list.firstLineHeadIndent = 4
        list.tabStops = [NSTextTab(textAlignment: .left, location: 22, options: [:])]
        line.addAttribute(.paragraphStyle, value: list, range: NSRange(location: 0, length: line.length))
        return line
    }

    private static func spacer() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)])
    }

    // Images are read from the support folder, never from an outside path,
    // and a missing image leaves its description in its place.
    private static func image(alt: String, path: String) -> NSAttributedString {
        let url = InstalledPaths.support.appendingPathComponent(path).standardizedFileURL
        // Compared by path component, so a sibling folder whose name merely
        // starts with "Scrippy" does not count as inside the support folder.
        let base = InstalledPaths.support.standardizedFileURL.pathComponents
        guard Array(url.pathComponents.prefix(base.count)) == base,
              let image = NSImage(contentsOf: url), image.size.width > 0 else {
            return paragraph(NSMutableAttributedString(string: alt, attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        // A fixed width that fits the reading column at the window's minimum
        // size: 640 points, less the 240 point sidebar, the 28 point insets on
        // each side, and room for a scroller. An image never forces sideways
        // scrolling.
        let width: CGFloat = 320
        let height = width * image.size.height / image.size.width
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 0, width: width, height: height)
        // The attachment initializer exists only on NSAttributedString, so the
        // mutable copy is made from it rather than directly.
        let text = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        text.addAttribute(.toolTip, value: alt, range: NSRange(location: 0, length: text.length))
        return paragraph(text)
    }
}
