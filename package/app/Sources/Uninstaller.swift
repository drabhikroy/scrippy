// Removes everything the installer placed, after asking. Items go to the
// Trash rather than being deleted, so a mistaken click can be undone by
// putting them back.

import AppKit

enum Uninstaller {
    // The app is removed from where the installer put it. A copy run from
    // anywhere else, such as a development build, is left where it is. The
    // uninstall package removes the same list.
    static var targets: [URL] {
        InstalledPaths.workflows + [InstalledPaths.support, InstalledPaths.logs, InstalledPaths.app]
    }

    static func confirmAndRun(controller: AppController) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Scrippy?"
        alert.informativeText = "Scrippy, its Finder actions, its help, and its log will be moved to the Trash. Your images and the copies Scrippy made are not touched."
        let trash = alert.addButton(withTitle: "Move to Trash")
        trash.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var failed: [String] = []
        let manager = FileManager.default
        for url in targets {
            // attributesOfItem also succeeds for a symbolic link whose target
            // is gone, which fileExists would report as missing.
            guard (try? manager.attributesOfItem(atPath: url.path)) != nil else { continue }
            do {
                try manager.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        // Finder keeps showing removed Quick Actions until the Services list
        // is rebuilt.
        NSUpdateDynamicServices()
        forgetReceipts()

        let done = NSAlert()
        if failed.isEmpty {
            done.messageText = "Scrippy is in the Trash"
            done.informativeText = "Empty the Trash to remove it completely. Thank you for trying Scrippy."
        } else {
            done.alertStyle = .warning
            done.messageText = "Some items could not be moved"
            done.informativeText = "These are still in place and can be moved to the Trash by hand: \(failed.joined(separator: ", "))."
        }
        done.addButton(withTitle: "OK")
        done.runModal()
        controller.choice?.cancel(nil)
        NSApp.terminate(nil)
    }

    // Installer records each package it installs. Forgetting the records
    // keeps a later reinstall from being treated as an upgrade of files that
    // are gone. A failure here changes nothing a person would notice.
    private static func forgetReceipts() {
        for identifier in InstalledPaths.packageIdentifiers {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
            process.arguments = ["--volume", InstalledPaths.home.path, "--forget", identifier]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // A one-step action the person left out has no receipt, and
            // pkgutil saying so is expected.
            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
        }
    }
}
