import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController.cleanup()
    }
}
