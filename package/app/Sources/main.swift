// Decides which role this launch plays. The engine starts the app with
// "choice" or "progress" and a list of files to read, and the installer with
// "refresh-services". Any other launch, from the Applications folder,
// Spotlight, or the Dock, opens the landing screen.

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller

switch arguments.first {
case "choice":
    app.mainMenu = controller.makeMainMenu()
    exit(runChoice(Array(arguments.dropFirst()), controller: controller))
case "progress":
    exit(runProgress(Array(arguments.dropFirst())))
case "refresh-services":
    // Run by the installer so the new Quick Actions appear in Finder without
    // logging out first.
    NSUpdateDynamicServices()
    exit(0)
default:
    // macOS can pass its own arguments, such as -psn_ from older launch
    // paths, so anything that is not one of the modes above falls here.
    app.setActivationPolicy(.regular)
    app.mainMenu = controller.makeMainMenu()
    let home = HomeWindowController()
    controller.homeWindow = home
    home.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
