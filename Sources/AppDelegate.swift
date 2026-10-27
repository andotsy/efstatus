import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.configure()
        buildAppMenu()
        controller = StatusBarController()
        Updater.shared.start()
        // Debug: `EFStatus --check-for-updates` runs a user-initiated update check right away.
        if CommandLine.arguments.contains("--check-for-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Updater.shared.checkForUpdates() }
        }
    }

    private func buildAppMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Cut",   action: #selector(NSText.cut(_:)),   keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",  action: #selector(NSText.copy(_:)),  keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        NSApp.mainMenu = mainMenu
    }
}
