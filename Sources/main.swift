import AppKit

// Create the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Run without dock icon
app.setActivationPolicy(.accessory)

app.run()
