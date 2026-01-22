import AppKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var claudeSession: ClaudePTYSession?
    private var refreshTimer: Timer?
    private var usageData: UsageData?
    private var isConnecting = false

    // Menu items
    private var menu: NSMenu!
    private var accountItem: NSMenuItem!
    private var sessionItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var sessionResetItem: NSMenuItem!
    private var weeklyResetItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!

    init() {
        setupStatusBar()
        setupMenu()
        startClaudeSession()
        startRefreshTimer()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarTitle(text: "Claude: --")
    }

    private func setupMenu() {
        menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Connecting...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Account info
        accountItem = NSMenuItem(title: "Account: --", action: nil, keyEquivalent: "")
        accountItem.isEnabled = false
        menu.addItem(accountItem)

        menu.addItem(NSMenuItem.separator())

        // Current session usage
        sessionItem = NSMenuItem(title: "Session: --", action: nil, keyEquivalent: "")
        sessionItem.isEnabled = false
        menu.addItem(sessionItem)

        sessionResetItem = NSMenuItem(title: "  Resets: --", action: nil, keyEquivalent: "")
        sessionResetItem.isEnabled = false
        menu.addItem(sessionResetItem)

        menu.addItem(NSMenuItem.separator())

        // Current week (all models) usage
        weeklyItem = NSMenuItem(title: "Weekly: --", action: nil, keyEquivalent: "")
        weeklyItem.isEnabled = false
        menu.addItem(weeklyItem)

        weeklyResetItem = NSMenuItem(title: "  Resets: --", action: nil, keyEquivalent: "")
        weeklyResetItem.isEnabled = false
        menu.addItem(weeklyResetItem)

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let reconnectItem = NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "")
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusBarTitle(text: String) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.title = text
            }
        }
    }

    private func startClaudeSession() {
        guard !isConnecting else { return }
        isConnecting = true

        updateStatusBarTitle(text: "Claude: ...")
        updateStatusMenuItem("Connecting to Claude Code...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.claudeSession = ClaudePTYSession()
            self?.claudeSession?.onStatusUpdate = { [weak self] data in
                self?.handleUsageUpdate(data)
            }
            self?.claudeSession?.onError = { [weak self] error in
                self?.handleError(error)
            }
            self?.claudeSession?.onReady = { [weak self] in
                DispatchQueue.main.async {
                    self?.isConnecting = false
                    self?.updateStatusMenuItem("Session ready")
                    // Request status after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self?.requestStatus()
                    }
                }
            }
            self?.claudeSession?.start()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.requestStatus()
        }
    }

    private func requestStatus() {
        guard let session = claudeSession, session.isRunning else {
            updateStatusMenuItem("Session not running")
            updateStatusBarTitle(text: "Claude: X")
            return
        }

        updateStatusMenuItem("Refreshing...")
        session.sendStatus()
    }

    private func handleUsageUpdate(_ data: UsageData) {
        self.usageData = data

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update status bar with session and weekly usage
            let sessionPct = data.sessionPercent ?? 0
            let weeklyPct = data.weeklyPercent ?? 0
            self.updateStatusBarTitle(text: "S:\(sessionPct)% W:\(weeklyPct)%")

            // Update account info
            if let email = data.accountEmail {
                let plan = data.accountPlan ?? ""
                if !plan.isEmpty {
                    self.accountItem.title = "\(email) (\(plan))"
                } else {
                    self.accountItem.title = email
                }
            } else {
                self.accountItem.title = "Account: --"
            }

            // Update session usage
            if let session = data.sessionPercent {
                self.sessionItem.title = "Session: \(session)%"
            } else {
                self.sessionItem.title = "Session: N/A"
            }

            if let sessionReset = data.sessionReset {
                self.sessionResetItem.title = "  Resets: \(sessionReset)"
            } else {
                self.sessionResetItem.title = "  Resets: --"
            }

            // Update weekly usage
            if let weekly = data.weeklyPercent {
                self.weeklyItem.title = "Weekly (all models): \(weekly)%"
            } else {
                self.weeklyItem.title = "Weekly: N/A"
            }

            if let weeklyReset = data.weeklyReset {
                self.weeklyResetItem.title = "  Resets: \(weeklyReset)"
            } else {
                self.weeklyResetItem.title = "  Resets: --"
            }

            self.updateStatusMenuItem("Last update: \(self.currentTimeString())")
        }
    }

    private func handleError(_ error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusBarTitle(text: "Claude: !")
            self?.updateStatusMenuItem("Error: \(error)")
        }
    }

    private func updateStatusMenuItem(_ text: String) {
        DispatchQueue.main.async {
            self.statusMenuItem.title = text
        }
    }

    private func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    @objc private func refreshNow() {
        requestStatus()
    }

    @objc private func reconnect() {
        cleanup()
        startClaudeSession()
    }

    @objc private func quit() {
        cleanup()
        NSApplication.shared.terminate(nil)
    }

    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        claudeSession?.stop()
        claudeSession = nil
    }
}
