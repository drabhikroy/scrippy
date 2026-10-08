// The application delegate and the menu bar. Scrippy runs on its own from the
// Applications folder, as the conversion window for a Finder action, as the
// progress window during a conversion, and briefly for the installer. The
// first two show menus, so this controller owns the menus and decides what
// quitting means.

import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    // Set while a conversion window is waiting for an answer. Quitting then
    // has to become a cancel, so the engine still receives its one line.
    weak var choice: ChoiceController?
    var helpWindow: HelpWindowController?
    var homeWindow: HomeWindowController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let choice {
            choice.cancel(sender)
            return .terminateCancel
        }
        return .terminateNow
    }

    // Opened on its own, Scrippy is a small app with one main window, and
    // closing it is the natural way to finish. The conversion window ends the
    // run loop itself, so this only matters for the landing screen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        choice == nil
    }

    @objc func showHelp(_ sender: Any?) {
        showHelp(topic: nil)
    }

    func showHelp(topic: String?) {
        if helpWindow == nil {
            helpWindow = HelpWindowController()
        }
        helpWindow?.show(topic: topic)
    }

    @objc func openLatestRelease(_ sender: Any?) {
        openExternal(latestReleaseURL)
    }

    @objc func openLicense(_ sender: Any?) {
        openExternal(licenseURL)
    }

    @objc func openExternalHelp(_ sender: Any?) {
        // The external copy lives in the support folder, which a person may
        // have removed. The help window stays available either way.
        guard FileManager.default.fileExists(atPath: InstalledPaths.externalHelp.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(InstalledPaths.externalHelp)
    }

    // The standard panel reads the name, version, copyright, and icon from
    // the bundle. Only the credits, which carry the links, are supplied here.
    @objc func showAbout(_ sender: Any?) {
        let small = NSFont.systemFont(ofSize: 11)
        let body = NSMutableAttributedString(
            string: "Converts images with SIPS, the image tool built into macOS.\n\n",
            attributes: [.font: small, .foregroundColor: NSColor.labelColor])
        let link: (String, URL) -> NSAttributedString = { text, url in
            NSAttributedString(string: text, attributes: [.link: url, .font: small])
        }
        body.append(link(licenseName, licenseURL))
        body.append(NSAttributedString(string: "\n", attributes: [.font: small]))
        body.append(link("Latest version on GitHub", latestReleaseURL))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        body.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: body.length))
        // An empty version string drops the build number in parentheses,
        // which would only repeat the version for this project.
        NSApp.orderFrontStandardAboutPanel(options: [.credits: body, .applicationVersion: appVersion, .version: ""])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func uninstall(_ sender: Any?) {
        Uninstaller.confirmAndRun(controller: self)
    }

    // Builds the menu bar. Edit lets a person copy a note, an estimate, or a
    // passage of help. Window and Help follow the usual Mac layout, so every
    // command is where a person would expect to look for it.
    func makeMainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil,
                  modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = modifiers
            menuItem.target = target
            return menuItem
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> (NSMenuItem, NSMenu) {
            let menu = NSMenu(title: title)
            items.forEach { menu.addItem($0) }
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            return (holder, menu)
        }

        let main = NSMenu()
        let (appItem, _) = submenu("Scrippy", [
            item("About Scrippy", #selector(showAbout(_:)), target: self),
            .separator(),
            item("Uninstall Scrippy…", #selector(uninstall(_:)), target: self),
            .separator(),
            item("Hide Scrippy", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            // terminate goes through applicationShouldTerminate, which turns
            // it into a cancel while a conversion window is waiting.
            item("Quit Scrippy", #selector(NSApplication.terminate(_:)), "q"),
        ])
        let (editItem, _) = submenu("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(HelpWindowController.focusSearch(_:)), "f"),
        ])
        let (windowItem, windowMenu) = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        let (helpItem, helpMenu) = submenu("Help", [
            item("Scrippy Help", #selector(showHelp(_:)), "?", target: self),
            item("Open Help in Browser", #selector(openExternalHelp(_:)), target: self),
            .separator(),
            item("Latest Version on GitHub", #selector(openLatestRelease(_:)), target: self),
            item("View License", #selector(openLicense(_:)), target: self),
        ])
        [appItem, editItem, windowItem, helpItem].forEach { main.addItem($0) }
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        return main
    }
}
