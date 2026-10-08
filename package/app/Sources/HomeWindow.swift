// The landing screen, shown when Scrippy is opened from the Applications
// folder rather than from Finder. Scrippy does its work in Finder, so this
// screen exists to answer three questions: is it set up, how do I use it, and
// where do I learn more.

import AppKit

final class HomeWindowController: NSWindowController, NSWindowDelegate {
    // The status list is rebuilt on each refresh, so it lives in its own
    // stack that can be emptied without touching the rest of the card.
    private let statusStack = compactStack(spacing: 6)
    private let statusSummary = makeLabel("", size: 13, weight: .semibold)
    private var exampleButton: NSButton!

    // 30 point margins on a 600 point window leave 540 for the cards, and 18
    // point padding inside a card leaves 504 for its text.
    private static let windowWidth: CGFloat = 600
    private static let margin: CGFloat = 30
    private static let contentWidth: CGFloat = windowWidth - 2 * margin
    private static let cardPadding: CGFloat = 18
    private static let cardText: CGFloat = contentWidth - 2 * cardPadding

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Scrippy"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildLayout(in: window)
        refreshStatus()
        fitWindow()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    // The person may have reinstalled or changed settings in another window,
    // so the status is checked again whenever this window comes forward.
    func windowDidBecomeKey(_ notification: Notification) {
        refreshStatus()
        fitWindow()
    }

    // The window takes the height its content needs, so nothing is clipped
    // when text is larger or the status list changes. The top edge stays put.
    private func fitWindow() {
        guard let window, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
    }

    // Selecting the example in Finder, rather than opening it, puts the
    // person exactly where the Quick Actions menu is one right-click away.
    @objc func showExample(_ sender: Any?) {
        let url = InstalledPaths.example
        guard FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func openSettings(_ sender: Any?) {
        openExternal(quickActionSettingsURL)
    }

    @objc func openHelp(_ sender: Any?) {
        (NSApp.delegate as? AppController)?.showHelp(topic: nil)
    }

    private func refreshStatus() {
        statusStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let manager = FileManager.default
        let mainPresent = manager.fileExists(atPath: InstalledPaths.workflow(InstalledPaths.mainAction).path)
        let leftOut = InstalledPaths.oneStepActions.filter { !manager.fileExists(atPath: InstalledPaths.workflow($0).path) }
        statusSummary.stringValue = mainPresent
            ? "Scrippy is set up in Finder."
            : "Convert with Scrippy is missing. Install Scrippy again to restore it."
        for name in InstalledPaths.quickActions {
            let present = manager.fileExists(atPath: InstalledPaths.workflow(name).path)
            let required = name == InstalledPaths.mainAction
            let row = compactStack(axis: .horizontal, spacing: 8)
            // Each state differs in shape as well as color. A one-step action
            // left out at install is a choice, not a fault, so it is shown
            // in gray rather than red.
            let symbol: NSImageView
            if present {
                symbol = symbolView("checkmark.circle.fill", size: 14, color: .systemGreen, description: "Installed")
            } else if required {
                symbol = symbolView("xmark.circle.fill", size: 14, color: .systemRed, description: "Missing")
            } else {
                symbol = symbolView("minus.circle", size: 14, color: .secondaryLabelColor, description: "Not installed")
            }
            row.addArrangedSubview(symbol)
            row.addArrangedSubview(makeLabel(present || required ? name : "\(name) (not installed)", size: 13,
                                             color: present || required ? .labelColor : .secondaryLabelColor))
            statusStack.addArrangedSubview(row)
        }
        if !leftOut.isEmpty {
            let hint = makeLabel("To add a one-step action later, run the installer again and select it on the Installation Type page.",
                                 size: 12, color: .secondaryLabelColor)
            statusStack.addArrangedSubview(wrapping(hint, width: Self.cardText))
        }
        exampleButton?.isEnabled = FileManager.default.fileExists(atPath: InstalledPaths.example.path)
    }

    // Each card is one task with a heading, the same grouping the conversion
    // window uses for its summary, so the two screens feel related.
    private func card(_ title: String, symbol: String, _ views: [NSView]) -> NSView {
        let stack = compactStack(spacing: 10)
        let heading = compactStack(axis: .horizontal, spacing: 8)
        heading.addArrangedSubview(symbolView(symbol, size: 15, color: .controlAccentColor))
        let headingLabel = makeLabel(title, size: 15, weight: .semibold)
        // Marking the card titles as headings lets VoiceOver users jump
        // between the three parts of the screen.
        headingLabel.setAccessibilityElement(true)
        headingLabel.setAccessibilitySubrole(NSAccessibility.Subrole(rawValue: "AXHeading"))
        heading.addArrangedSubview(headingLabel)
        stack.addArrangedSubview(heading)
        views.forEach { stack.addArrangedSubview($0) }
        return CardView(stack, horizontal: Self.cardPadding, vertical: 16)
    }

    private func buildLayout(in window: NSWindow) {
        let root = compactStack(spacing: 18)
        root.edgeInsets = NSEdgeInsets(top: 26, left: Self.margin, bottom: 22, right: Self.margin)
        setContent(root, of: window)

        let iconSize: CGFloat = 84
        let header = compactStack(axis: .horizontal, spacing: 18)
        let titles = compactStack(spacing: 4)
        titles.addArrangedSubview(makeLabel("Scrippy", size: 26, weight: .bold))
        titles.addArrangedSubview(makeLabel("Version \(appVersion)", size: 12, color: .secondaryLabelColor))
        titles.addArrangedSubview(wrapping(makeLabel("Converts images to any format your Mac can write, right from Finder.", size: 13),
                                           width: Self.contentWidth - iconSize - 18))
        header.addArrangedSubview(appIconView(size: iconSize))
        header.addArrangedSubview(titles)

        _ = wrapping(statusSummary, width: Self.cardText)
        let howTo = wrapping(makeLabel("Select images or a folder in Finder, right-click, and choose Quick Actions. Pick Convert with Scrippy to choose from every format. A Convert to action, if you installed it, converts in one step.",
                                       size: 13, color: .secondaryLabelColor), width: Self.cardText)
        let settingsButton = NSButton(title: "Choose Which Actions Appear…", target: self, action: #selector(openSettings(_:)))
        settingsButton.bezelStyle = .rounded
        let finderCard = card("In Finder", symbol: "folder", [statusSummary, statusStack, howTo, settingsButton])

        exampleButton = pushButton("Show Example Image in Finder", target: self, action: #selector(showExample(_:)), primary: true)
        let tryText = wrapping(makeLabel("A photo of the galaxy Messier 88 is included for practice. Show it in Finder, right-click it, and choose Convert with Scrippy. The original is never changed.",
                                         size: 13, color: .secondaryLabelColor), width: Self.cardText)
        let tryCard = card("Try it", symbol: "photo", [tryText, exampleButton])

        // Help is the secondary action here. The example button is the default,
        // since trying a conversion teaches more than reading about one.
        let helpButton = pushButton("Open Help", target: self, action: #selector(openHelp(_:)))

        // The footer carries the same version, copyright, and license details
        // as the help and the About panel.
        let small = NSFont.systemFont(ofSize: 11)
        let footer = NSMutableAttributedString(string: "\(copyrightLine). ", attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor])
        footer.append(NSAttributedString(string: licenseName, attributes: [.font: small, .link: licenseURL]))
        footer.append(NSAttributedString(string: ". ", attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        footer.append(NSAttributedString(string: "Latest version", attributes: [.font: small, .link: latestReleaseURL]))
        footer.append(NSAttributedString(string: ".", attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        let footerLabel = makeLinkLabel(footer)

        [header, finderCard, tryCard, helpButton, footerLabel].forEach { root.addArrangedSubview($0) }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.windowWidth),
            finderCard.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            tryCard.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])
    }
}
