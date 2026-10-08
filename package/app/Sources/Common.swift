// Values and small helpers shared by every Scrippy window. The app is built
// with swiftc from a plain folder of sources rather than an Xcode project, so
// anything two windows need lives here instead of in a framework.

import AppKit
import Foundation

// Matches the engine, which allows the same override for testing.
let sipsPath = ProcessInfo.processInfo.environment["SIPS_BIN"] ?? "/usr/bin/sips"

let latestReleaseURL = URL(string: "https://github.com/drabhikroy/scrippy/releases/latest")!
let licenseURL = URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!
// Opens the list of Finder Quick Actions in System Settings, where each one
// can be turned on or off. The help gives the Finder menu route as well, in
// case a future macOS moves this pane.
let quickActionSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.finder-quick-actions")!

let copyrightLine = "Copyright 2026 Abhik Roy"
let licenseName = "PolyForm Noncommercial License 1.0.0"

// Read from the bundle so the About panel, the help window, and the landing
// screen all show the number the build stamped from VERSION.
var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
}

// Everything the installer places, by fixed location. The landing screen
// checks these and the uninstaller removes exactly these, nothing found by
// searching, so neither can reach a file Scrippy did not put there.
enum InstalledPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/Scrippy", isDirectory: true)
    static let logs = home.appendingPathComponent("Library/Logs/Scrippy", isDirectory: true)
    static let services = home.appendingPathComponent("Library/Services", isDirectory: true)
    static let app = home.appendingPathComponent("Applications/Scrippy.app", isDirectory: true)
    static let externalHelp = support.appendingPathComponent("Scrippy Help.html")
    static let example = support.appendingPathComponent("Example/Example Image - Messier 88.png")
    // The main action always comes with the app. The one-step actions are
    // optional on the installer's Installation Type page.
    static let mainAction = "Convert with Scrippy"
    static let oneStepActions = [
        "Convert to JPEG with Scrippy",
        "Convert to PNG with Scrippy",
        "Convert to HEIC with Scrippy",
    ]
    static var quickActions: [String] { [mainAction] + oneStepActions }
    static func workflow(_ name: String) -> URL {
        services.appendingPathComponent("\(name).workflow", isDirectory: true)
    }
    static var workflows: [URL] { quickActions.map(workflow) }
    // One receipt for the app and one for each optional action.
    static let packageIdentifiers = ["com.scrippy.pkg"]
        + ["jpeg", "png", "heic"].map { "com.scrippy.quickaction.\($0).pkg" }
}

// Standard output carries the engine's answer and nothing else. Messages for
// people and for the log go to standard error instead.
func writeStdout(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

// Only these schemes may leave the app from a link. Help text and the landing
// screen are written by us, but a fixed list means a mistake in either can
// never open a file or launch another app by URL.
func openExternal(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), ["https", "x-apple.systempreferences"].contains(scheme) else { return }
    NSWorkspace.shared.open(url)
}

// Labels are selectable so a person can copy an error or a size estimate,
// and they wrap because long format notes would otherwise clip.
func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.isSelectable = true
    field.lineBreakMode = .byWordWrapping
    field.usesSingleLineMode = false
    field.maximumNumberOfLines = 0
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

// A label whose text carries links. AppKit only follows a link in a text
// field that allows editing text attributes, which is why both flags are set
// even though nothing in it can be edited.
func makeLinkLabel(_ text: NSAttributedString) -> NSTextField {
    let field = NSTextField(labelWithAttributedString: text)
    field.isSelectable = true
    field.allowsEditingTextAttributes = true
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

// The same thresholds and rounding as human_size in the engine, so the
// prompt and the estimate never describe one size two different ways.
func humanSize(_ bytes: Int64) -> String {
    let value = Double(bytes)
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1_048_576 { return String(format: "%.1f KB", value / 1024) }
    if bytes < 1_073_741_824 { return String(format: "%.1f MB", value / 1_048_576) }
    return String(format: "%.2f GB", value / 1_073_741_824)
}

// Every stack starts from the same settings. Layout is done with constraints
// so windows can resize themselves around their text.
func compactStack(axis: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = axis
    stack.alignment = axis == .vertical ? .leading : .centerY
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

// SF Symbols carry meaning by shape as well as color, so a status that is
// green with a check and one that is orange with a triangle still differ for
// someone who cannot tell the colors apart.
func symbolView(_ name: String, size: CGFloat, color: NSColor? = nil, description: String? = nil) -> NSImageView {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    let view = NSImageView(image: image)
    view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    if let color { view.contentTintColor = color }
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setAccessibilityHidden(description == nil)
    return view
}

// Makes a stack the whole content of a window. The stack goes inside a plain
// view rather than becoming the content view itself, because the window sets
// its content view's frame directly and that fights a stack sized by
// constraints. The bottom edge may leave room but never pulls on the stack,
// since stretching a stack spreads its rows apart.
func setContent(_ stack: NSStackView, of window: NSWindow) {
    let container = NSView()
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: container.topAnchor),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
    ])
    window.contentView = container
}

// A rounded panel around one stack. The panel is drawn rather than set on a
// layer, so its colors follow light and dark appearance as they change. Its
// height comes from the stack inside, which NSBox does not provide when its
// content is laid out with constraints.
final class CardView: NSView {
    init(_ stack: NSStackView, horizontal: CGFloat, vertical: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        panel.fill()
        NSColor.separatorColor.setStroke()
        panel.lineWidth = 1
        panel.stroke()
    }
}

// A one point vertical rule that divides two columns. It is drawn in the
// separator color, which follows light and dark appearance.
final class RuleView: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 1).isActive = true
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

// A label that wraps at a fixed width. A wrapping label needs to know its
// width before layout, or it measures itself as one long line.
func wrapping(_ label: NSTextField, width: CGFloat) -> NSTextField {
    label.preferredMaxLayoutWidth = width
    label.widthAnchor.constraint(equalToConstant: width).isActive = true
    return label
}

func appIconView(size: CGFloat) -> NSImageView {
    let view = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
    view.imageScaling = .scaleProportionallyUpOrDown
    view.translatesAutoresizingMaskIntoConstraints = false
    view.setAccessibilityHidden(true)
    NSLayoutConstraint.activate([
        view.widthAnchor.constraint(equalToConstant: size),
        view.heightAnchor.constraint(equalToConstant: size),
    ])
    return view
}

func pushButton(_ title: String, target: AnyObject?, action: Selector, primary: Bool = false) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    // A larger control size gives the main buttons a click target closer to
    // the 44 point guideline than the regular size does.
    button.controlSize = .large
    if primary { button.keyEquivalent = "\r" }
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}
