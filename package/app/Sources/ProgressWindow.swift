// The progress window shown during a conversion that takes more than a
// moment. The engine and this window share only files: the engine writes
// progress, and this window can ask it to stop by creating a file.

import AppKit

// The engine rewrites the progress file after each image as
// "completed<TAB>status". A partial read during a rewrite returns nil and is
// simply tried again on the next tick.
func readProgress(_ path: String) -> (Double, String)? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    let parts = text.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first, let completed = Double(first.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    let status = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return (completed, status)
}

private final class StopTarget: NSObject {
    let stopPath: String
    let status: NSTextField
    init(stopPath: String, status: NSTextField) {
        self.stopPath = stopPath
        self.status = status
    }

    // The engine checks for this file between images, so the image being
    // converted right now always finishes and no half written copy is left.
    @objc func stop(_ sender: NSButton) {
        FileManager.default.createFile(atPath: stopPath, contents: nil)
        sender.isEnabled = false
        status.stringValue = "Stopping after the current image…"
    }
}

// Arguments, in order: progress file, done marker, image count, seconds to
// wait before showing, window title, heading, and the stop request file.
func runProgress(_ args: [String]) -> Int32 {
    guard args.count >= 6, let total = Int(args[2]), let wait = Double(args[3]) else {
        writeStderr("The progress window did not receive the information it needs.")
        return 2
    }
    let progressPath = args[0]
    let donePath = args[1]
    let stopPath = args.count > 6 ? args[6] : nil
    let manager = FileManager.default

    // Most conversions finish within the wait, and then no window appears.
    let end = Date().addingTimeInterval(wait)
    while Date() < end {
        if manager.fileExists(atPath: donePath) { return 0 }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if manager.fileExists(atPath: donePath) { return 0 }

    // An accessory app shows its window without adding a Dock icon, which
    // suits something that lives only as long as one conversion.
    NSApp.setActivationPolicy(.accessory)
    NSApp.finishLaunching()

    // No close button. Closing the window would not stop the conversion, so
    // offering one would suggest a choice that does not exist. Stop does.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 168), styleMask: [.titled], backing: .buffered, defer: false)
    window.title = args[4]
    window.isReleasedWhenClosed = false

    let root = compactStack(spacing: 10)
    root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
    setContent(root, of: window)
    let heading = makeLabel(args[5], size: 15, weight: .semibold)
    heading.preferredMaxLayoutWidth = 392
    heading.isSelectable = false
    let status = makeLabel("Starting", size: 13, color: .secondaryLabelColor)
    status.isSelectable = false
    // The status line is announced as it changes, so VoiceOver users hear
    // the count without having to move to it.
    status.setAccessibilityElement(true)

    let bar = NSProgressIndicator()
    bar.isDisplayedWhenStopped = true
    bar.translatesAutoresizingMaskIntoConstraints = false
    bar.setAccessibilityLabel(args[5])
    // One image has no meaningful fraction to show, so it gets a moving bar.
    if total == 1 {
        bar.isIndeterminate = true
        bar.startAnimation(nil)
    } else {
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = Double(total)
    }
    [heading, status, bar].forEach { root.addArrangedSubview($0) }

    // Stop is offered only for a batch. A single image cannot be stopped
    // partway, so the button would promise something it cannot do.
    var stopTarget: StopTarget?
    if total > 1, let stopPath {
        let target = StopTarget(stopPath: stopPath, status: status)
        let row = compactStack(axis: .horizontal, spacing: 0)
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let stop = NSButton(title: "Stop", target: target, action: #selector(StopTarget.stop(_:)))
        stop.bezelStyle = .rounded
        stop.keyEquivalent = "\u{1b}"
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(stop)
        root.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: 392).isActive = true
        stopTarget = target
    }
    NSLayoutConstraint.activate([
        root.widthAnchor.constraint(equalToConstant: 440),
        bar.widthAnchor.constraint(equalToConstant: 392),
        heading.widthAnchor.constraint(equalToConstant: 392),
        status.widthAnchor.constraint(equalToConstant: 392),
    ])
    window.contentView?.layoutSubtreeIfNeeded()
    window.setContentSize(window.contentView?.fittingSize ?? root.fittingSize)
    window.center()
    // An accessory app is not always the active app, so a plain
    // makeKeyAndOrderFront could leave the window behind Finder.
    window.orderFrontRegardless()
    window.makeKey()

    // Events are pumped by hand rather than with NSApp.run(), so the loop can
    // also watch the done marker. Polling a file keeps the two processes
    // independent. The engine never waits on this window, so a stuck window
    // cannot stall a conversion.
    var lastStatus = ""
    while !manager.fileExists(atPath: donePath) {
        if let progress = readProgress(progressPath) {
            if total > 1 { bar.doubleValue = progress.0 }
            let stopping = stopPath.map { manager.fileExists(atPath: $0) } ?? false
            if !progress.1.isEmpty, !stopping, progress.1 != lastStatus {
                status.stringValue = progress.1
                lastStatus = progress.1
                NSAccessibility.post(element: status, notification: .valueChanged)
            }
        }
        if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.15), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
    // A button holds its target weakly, so the target is kept alive here until
    // the window is gone.
    _ = stopTarget
    bar.stopAnimation(nil)
    window.orderOut(nil)
    return 0
}
