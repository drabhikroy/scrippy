// The conversion window. The engine describes the formats in tab separated
// files, this window lets the person choose, and the choice goes back to the
// engine as one line on standard output.

import AppKit
import QuickLookThumbnailing

// One output format as the engine described it. The key is what SIPS expects
// after "-s format", the title is what the menu shows, and common formats are
// grouped above a separator.
struct ChoiceRow {
    let key: String
    let title: String
    let suffix: String
    let benefit: String
    let tradeoff: String
    let common: Bool
}

// One image detail setting for one format. The key is a quality percentage,
// or "auto" to leave the SIPS default alone.
struct DetailRow {
    let formatKey: String
    let key: String
    let title: String
    let benefit: String
    let tradeoff: String
}

// Rows with too few columns are dropped rather than treated as fatal. A
// malformed row costs one menu entry instead of the whole window.
func readRows(_ path: String) throws -> [ChoiceRow] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        return ChoiceRow(key: parts[0], title: parts[1], suffix: parts[2], benefit: parts[3], tradeoff: parts[4],
                         common: parts.count > 5 && parts[5] == "common")
    }
}

func readDetails(_ path: String) throws -> [DetailRow] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        return DetailRow(formatKey: parts[0], key: parts[1], title: parts[2], benefit: parts[3], tradeoff: parts[4])
    }
}

// Differences under three percent are reported as the same size, since a
// one image sample cannot support a finer claim than that.
func estimateText(_ estimated: Int64, baseline: Int64, multiple: Bool) -> String {
    guard estimated > 0, baseline > 0 else { return "Estimate unavailable" }
    let percent = Int((((Double(estimated) - Double(baseline)) / Double(baseline)) * 100).rounded())
    let size = humanSize(estimated)
    let prefix = multiple ? "About \(size) total" : "About \(size)"
    if percent <= -3 { return "\(prefix)  •  about \(-percent)% smaller" }
    if percent >= 3 { return "\(prefix)  •  about \(percent)% larger" }
    return "\(prefix)  •  about the same size"
}

// What the engine passes, in order: choices file, detail file, window title,
// prompt, confirm button title, representative image, its size in bytes,
// total size in bytes, image count, and the work folder for estimates.
struct ChoiceRequest {
    let rows: [ChoiceRow]
    let detailsByFormat: [String: [DetailRow]]
    let title: String
    let prompt: String
    let confirmTitle: String
    let representativePath: String
    let representativeBytes: Int64
    let sourceTotalBytes: Int64
    let imageCount: Int
    let workDir: String

    init?(_ args: [String]) throws {
        guard args.count >= 10,
              let representativeBytes = Int64(args[6]),
              let sourceTotalBytes = Int64(args[7]),
              let imageCount = Int(args[8]) else { return nil }
        rows = try readRows(args[0])
        // Grouped once here so each format change is a dictionary lookup.
        var grouped: [String: [DetailRow]] = [:]
        for row in try readDetails(args[1]) { grouped[row.formatKey, default: []].append(row) }
        detailsByFormat = grouped
        title = args[2]
        prompt = args[3]
        confirmTitle = args[4]
        representativePath = args[5]
        self.representativeBytes = representativeBytes
        self.sourceTotalBytes = sourceTotalBytes
        self.imageCount = imageCount
        workDir = args[9]
    }
}

final class ChoiceController: NSObject, NSWindowDelegate {
    private let request: ChoiceRequest
    let window: NSWindow
    private let rootStack = compactStack(spacing: 0)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detailRow = compactStack(spacing: 6)
    private let detailPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let estimateField = makeLabel("Calculating…", size: 13, weight: .medium)
    private let estimateSpinner = NSProgressIndicator()
    private let benefitField = makeLabel("", size: 12.5)
    private let tradeoffField = makeLabel("", size: 12.5)
    private let thumbnail = NSImageView()
    // The preview's height follows the picture's shape, so a wide image has
    // its caption right under it instead of below an empty band.
    private lazy var thumbnailHeight = thumbnail.heightAnchor.constraint(equalToConstant: Self.previewSize * 2 / 3)

    // Cancel is the default answer, so any way out of the window that is not
    // the Convert button reads as a cancel.
    private(set) var result = "__CANCEL__"
    private var currentDetails: [DetailRow] = []
    private var estimateCache: [String: String] = [:]
    private var estimateToken = UUID()
    // Only one estimate runs at a time. Moving through the menu quickly would
    // otherwise start a full conversion of the largest image for each format.
    private var estimateProcess: Process?

    // The last format and detail setting are remembered, since most people
    // convert to the same format again and again.
    private let defaults = UserDefaults.standard
    private static let lastFormatKey = "LastFormat"
    private static func lastDetailKey(_ format: String) -> String { "LastDetail.\(format)" }

    // The controls take the left column and the preview the right, with a
    // rule between them. 28 point side insets on an 840 point window leave
    // 784 points, and the left column gets what the preview and rule leave.
    private static let width: CGFloat = 840
    private static let inner: CGFloat = 784
    private static let previewSize: CGFloat = 260
    private static let columnGap: CGFloat = 22
    private static let left: CGFloat = inner - previewSize - 2 * columnGap - 1

    init(_ request: ChoiceRequest) {
        self.request = request
        // A titled window that can be minimized behaves like any other app
        // window while Scrippy waits for an answer.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 470),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = request.title
        // The controller keeps using the window after it closes, so AppKit must
        // not release it on close.
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildLayout()
        selectRemembered()
        resizeWindow(animated: false)
        window.center()
        loadThumbnail()
    }

    // MARK: Layout

    private func buildLayout() {
        rootStack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 22, right: 28)
        setContent(rootStack, of: window)

        // The preview confirms which picture is about to be converted. For a
        // batch it shows the largest image. It is large enough to recognize
        // the picture, and sits apart from the controls so it reads as a
        // reference rather than as something to set.
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.setAccessibilityLabel("Preview of the image to convert")
        let promptField = wrapping(makeLabel(request.prompt, size: 12.5, color: .secondaryLabelColor), width: Self.previewSize)
        let preview = compactStack(spacing: 10)
        preview.addArrangedSubview(makeLabel("Preview", size: 12.5, weight: .semibold))
        preview.addArrangedSubview(thumbnail)
        preview.addArrangedSubview(promptField)

        let controls = compactStack(spacing: 0)
        let formatSection = compactStack(spacing: 6)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.setAccessibilityLabel("Output format")
        fillFormatMenu()
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        formatSection.addArrangedSubview(makeLabel("Format", size: 12.5, weight: .semibold))
        formatSection.addArrangedSubview(formatPopup)
        controls.addArrangedSubview(formatSection)
        controls.setCustomSpacing(18, after: formatSection)

        // Hidden until a lossy format is chosen. A stack view closes the gap
        // left by a hidden row on its own.
        detailPopup.translatesAutoresizingMaskIntoConstraints = false
        detailPopup.setAccessibilityLabel("Image detail")
        detailPopup.target = self
        detailPopup.action = #selector(detailChanged(_:))
        detailRow.addArrangedSubview(makeLabel("Image detail", size: 12.5, weight: .semibold))
        detailRow.addArrangedSubview(detailPopup)
        controls.addArrangedSubview(detailRow)
        controls.setCustomSpacing(18, after: detailRow)

        let estimateSection = compactStack(spacing: 5)
        let estimateLine = compactStack(axis: .horizontal, spacing: 8)
        estimateField.preferredMaxLayoutWidth = Self.left - 30
        // The spinner shows that an estimate is being worked out, which can take
        // several seconds for a large TIFF or PSD.
        estimateSpinner.style = .spinning
        estimateSpinner.controlSize = .small
        estimateSpinner.isIndeterminate = true
        estimateSpinner.translatesAutoresizingMaskIntoConstraints = false
        estimateLine.addArrangedSubview(estimateSpinner)
        estimateLine.addArrangedSubview(estimateField)
        estimateSection.addArrangedSubview(makeLabel("Estimated output", size: 12.5, weight: .semibold))
        estimateSection.addArrangedSubview(estimateLine)
        controls.addArrangedSubview(estimateSection)
        controls.setCustomSpacing(20, after: estimateSection)

        let summaryCard = makeSummaryCard()
        controls.addArrangedSubview(summaryCard)

        let rule = RuleView()
        let body = compactStack(axis: .horizontal, spacing: Self.columnGap)
        body.alignment = .top
        body.addArrangedSubview(controls)
        body.addArrangedSubview(rule)
        body.addArrangedSubview(preview)
        rootStack.addArrangedSubview(body)
        rootStack.setCustomSpacing(22, after: body)

        let buttonRow = compactStack(axis: .horizontal, spacing: 10)
        // Help sits apart on the left, following the macOS dialog layout.
        let helpButton = NSButton(title: "", target: self, action: #selector(help(_:)))
        helpButton.bezelStyle = .helpButton
        helpButton.setAccessibilityLabel("Scrippy Help")
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        // Escape and Return behave as they do in any Mac dialog.
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        let convertButton = NSButton(title: request.confirmTitle, target: self, action: #selector(convert(_:)))
        convertButton.keyEquivalent = "\r"
        convertButton.bezelStyle = .rounded
        convertButton.controlSize = .large
        [helpButton, spacer, cancelButton, convertButton].forEach { buttonRow.addArrangedSubview($0) }
        rootStack.addArrangedSubview(buttonRow)

        var constraints = [
            rootStack.widthAnchor.constraint(equalToConstant: Self.width),
            thumbnail.widthAnchor.constraint(equalToConstant: Self.previewSize),
            thumbnailHeight,
            rule.heightAnchor.constraint(equalTo: body.heightAnchor),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            body.widthAnchor.constraint(equalToConstant: Self.inner),
            buttonRow.widthAnchor.constraint(equalToConstant: Self.inner),
        ]
        for view in [controls, formatSection, formatPopup, detailRow, detailPopup, estimateSection, estimateLine, summaryCard] as [NSView] {
            constraints.append(view.widthAnchor.constraint(equalToConstant: Self.left))
        }
        NSLayoutConstraint.activate(constraints)
    }

    // The common formats come first, then a separator, then the rest. Each
    // menu item carries the index of its row, so the separator never throws
    // the positions off.
    private func fillFormatMenu() {
        formatPopup.removeAllItems()
        let menu = formatPopup.menu ?? NSMenu()
        var addedSeparator = false
        for (index, row) in request.rows.enumerated() {
            if !row.common, !addedSeparator, index > 0, request.rows[0].common {
                menu.addItem(.separator())
                addedSeparator = true
            }
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
    }

    // The card groups the two notes so they read as one summary of the
    // current choice rather than as more controls.
    private func makeSummaryCard() -> NSView {
        let stack = compactStack(spacing: 14)
        stack.addArrangedSubview(noteRow(symbol: "checkmark.circle", label: "Good for", value: benefitField))
        stack.addArrangedSubview(noteRow(symbol: "exclamationmark.triangle", label: "Consider", value: tradeoffField))
        return CardView(stack, horizontal: 20, vertical: 16)
    }

    // A symbol, a fixed width label, and a wrapping value. The fixed label
    // width lines the two notes up so the values start at the same edge.
    private func noteRow(symbol: String, label: String, value: NSTextField) -> NSStackView {
        let row = compactStack(axis: .horizontal, spacing: 10)
        row.alignment = .top
        let labelField = makeLabel(label, size: 12.5, weight: .semibold)
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        // Low priorities let the value wrap instead of pushing the card wider.
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        value.preferredMaxLayoutWidth = Self.left - 150
        row.addArrangedSubview(symbolView(symbol, size: 13))
        row.addArrangedSubview(labelField)
        row.addArrangedSubview(value)
        labelField.widthAnchor.constraint(equalToConstant: 74).isActive = true
        return row
    }

    // Quick Look makes the thumbnail in the background at the size shown,
    // which is far cheaper than opening a large TIFF or PSD in full.
    private func loadThumbnail() {
        thumbnail.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        let url = URL(fileURLWithPath: request.representativePath)
        let scale = window.backingScaleFactor
        let thumbnailRequest = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: Self.previewSize, height: Self.previewSize),
                                                            scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: thumbnailRequest) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { self?.showThumbnail(image) }
        }
    }

    private func showThumbnail(_ image: NSImage) {
        thumbnail.image = image
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        thumbnailHeight.constant = min(Self.previewSize, Self.previewSize * size.height / size.width)
        resizeWindow(animated: false)
    }

    // MARK: Selection

    private var selectedRow: ChoiceRow? {
        guard let tag = formatPopup.selectedItem?.tag, request.rows.indices.contains(tag) else { return nil }
        return request.rows[tag]
    }

    // Menus can briefly report no selection while their items are replaced,
    // so every index is checked before use.
    private var currentDetail: DetailRow? {
        guard currentDetails.indices.contains(detailPopup.indexOfSelectedItem) else { return nil }
        return currentDetails[detailPopup.indexOfSelectedItem]
    }

    private func selectRemembered() {
        let remembered = defaults.string(forKey: Self.lastFormatKey)
        let index = request.rows.firstIndex { $0.key == remembered } ?? 0
        formatPopup.selectItem(withTag: index)
        updateFormat()
    }

    // Changing format rebuilds the detail menu, which exists only for lossy
    // formats, and starts it at the last setting used for that format.
    private func updateFormat() {
        guard let row = selectedRow else { return }
        currentDetails = request.detailsByFormat[row.key] ?? []
        detailPopup.removeAllItems()
        if currentDetails.isEmpty {
            detailRow.isHidden = true
        } else {
            detailPopup.addItems(withTitles: currentDetails.map(\.title))
            let remembered = defaults.string(forKey: Self.lastDetailKey(row.key))
            detailPopup.selectItem(at: currentDetails.firstIndex { $0.key == remembered } ?? 0)
            detailRow.isHidden = false
        }
        // No animation before the window first appears, or it would visibly
        // resize itself on screen during launch.
        refresh(animated: window.isVisible)
    }

    private func refresh(animated: Bool) {
        updateNotes()
        requestEstimate()
        resizeWindow(animated: animated)
    }

    // The detail note adds to the format note rather than replacing it, since
    // both choices shape the result.
    private func updateNotes() {
        guard let row = selectedRow else { return }
        if let detail = currentDetail {
            benefitField.stringValue = row.benefit + " " + detail.benefit
            tradeoffField.stringValue = row.tradeoff + " " + detail.tradeoff
        } else {
            benefitField.stringValue = row.benefit
            tradeoffField.stringValue = row.tradeoff
        }
    }

    // The window grows and shrinks with its notes so long tradeoffs never
    // scroll. The top edge stays fixed, which reads as the window growing
    // downward rather than jumping.
    private func resizeWindow(animated: Bool) {
        window.contentView?.layoutSubtreeIfNeeded()
        let content = NSRect(x: 0, y: 0, width: Self.width, height: rootStack.fittingSize.height)
        let height = min(680, window.frameRect(forContentRect: content).height)
        let old = window.frame
        window.setFrame(NSRect(x: old.origin.x, y: old.maxY - height, width: Self.width, height: height),
                        display: true, animate: animated)
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) { updateFormat() }
    @objc private func detailChanged(_ sender: NSPopUpButton) { refresh(animated: false) }

    // MARK: Estimate

    private func stopEstimate() {
        if let running = estimateProcess, running.isRunning { running.terminate() }
        estimateProcess = nil
    }

    private func showEstimate(_ text: String) {
        estimateField.stringValue = text
        estimateSpinner.stopAnimation(nil)
        estimateSpinner.isHidden = true
    }

    // Estimates by doing: SIPS converts the largest selected image to a
    // temporary file for the option on screen, and that size is scaled to the
    // whole selection. Results are cached per option while the window is open.
    private func requestEstimate() {
        guard let row = selectedRow, request.representativeBytes > 0, request.sourceTotalBytes > 0 else {
            showEstimate("Estimate unavailable")
            return
        }
        let detailKey = currentDetail?.key
        let cacheKey = row.key + "|" + (detailKey ?? "__NONE__")
        if let cached = estimateCache[cacheKey] {
            showEstimate(cached)
            return
        }

        stopEstimate()
        estimateField.stringValue = "Calculating…"
        estimateSpinner.isHidden = false
        estimateSpinner.startAnimation(nil)
        // A slow estimate can finish after the person has moved on. The token
        // lets only the newest request update the screen.
        let token = UUID()
        estimateToken = token
        // The output name is made here, never from anything the engine sent,
        // and always inside the private work folder.
        let output = URL(fileURLWithPath: request.workDir).appendingPathComponent("estimate-\(UUID().uuidString).\(row.suffix)")
        var arguments = ["-s", "format", row.key]
        if let detailKey, detailKey != "auto" { arguments += ["-s", "formatOptions", detailKey] }
        arguments += [request.representativePath, "--out", output.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sipsPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Launching here, on the main thread, means a later stopEstimate()
        // always finds a running process to stop rather than one still queued.
        do {
            try process.run()
        } catch {
            estimateCache[cacheKey] = "Estimate unavailable"
            showEstimate("Estimate unavailable")
            return
        }
        estimateProcess = process

        let representativeBytes = request.representativeBytes
        let sourceTotalBytes = request.sourceTotalBytes
        let multiple = request.imageCount > 1
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            var text = "Estimate unavailable"
            if process.terminationStatus == 0,
               let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
               let number = attributes[.size] as? NSNumber, number.int64Value > 0 {
                let estimated = Int64((Double(sourceTotalBytes) * Double(number.int64Value) / Double(representativeBytes)).rounded())
                text = estimateText(estimated, baseline: sourceTotalBytes, multiple: multiple)
            }
            try? FileManager.default.removeItem(at: output)
            let finishedNormally = process.terminationReason == .exit
            let finalText = text
            DispatchQueue.main.async {
                // A stopped estimate ends on a signal and reads as unavailable.
                // Caching that would hide the real answer on a later visit.
                if finishedNormally { self.estimateCache[cacheKey] = finalText }
                guard self.estimateToken == token else { return }
                self.estimateProcess = nil
                self.showEstimate(finalText)
            }
        }
    }

    // MARK: Answer

    // Every way out of the window ends here. Stopping the estimate first keeps
    // a running SIPS process from writing into the work folder after the
    // engine has begun to clean it up.
    private func finish(with answer: String) {
        stopEstimate()
        result = answer
        window.orderOut(nil)
        NSApp.stop(nil)
        // stop() takes effect only once the run loop handles another event, so
        // one is posted rather than waiting for the mouse to move.
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(wake, atStart: false)
        }
    }

    @objc func convert(_ sender: Any?) {
        guard let row = selectedRow else { return }
        let detailKey = currentDetail?.key ?? "__NONE__"
        defaults.set(row.key, forKey: Self.lastFormatKey)
        if detailKey != "__NONE__" { defaults.set(detailKey, forKey: Self.lastDetailKey(row.key)) }
        finish(with: row.key + "\t" + detailKey)
    }

    @objc func cancel(_ sender: Any?) {
        finish(with: "__CANCEL__")
    }

    @objc private func help(_ sender: Any?) {
        (NSApp.delegate as? AppController)?.showHelp(topic: "choosing-a-format")
    }

    // The close button, Close in the Window menu, and Command W all arrive
    // here. Hiding the window alone would leave the Quick Action waiting.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel(sender)
        return false
    }
}

func runChoice(_ args: [String], controller app: AppController) -> Int32 {
    let request: ChoiceRequest
    do {
        guard let parsed = try ChoiceRequest(args) else {
            writeStderr("The conversion window did not receive the information it needs.")
            return 2
        }
        request = parsed
    } catch {
        writeStderr(error.localizedDescription)
        return 2
    }
    guard !request.rows.isEmpty else {
        writeStderr("No output formats were available to display.")
        return 2
    }

    // A regular app gets the menu bar and a Dock icon for as long as the
    // window is open, so Scrippy can be found, switched to, and quit like any
    // other app while it waits for an answer.
    NSApp.setActivationPolicy(.regular)
    let choice = ChoiceController(request)
    app.choice = choice
    choice.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // run returns only after finish(with:) stops it. A plain run loop is used
    // rather than a modal one, because a modal session disables menu items
    // whose target is not the window itself.
    NSApp.run()
    writeStdout(choice.result)
    return 0
}
