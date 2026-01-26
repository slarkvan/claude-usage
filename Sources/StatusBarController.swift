import AppKit
import EventKit

class StatusBarController {
    private var statusItem: NSStatusItem!
    private var claudeSession: ClaudePTYSession?
    private var dispatchTimer: DispatchSourceTimer?
    private var usageData: UsageData?
    private var isConnecting = false

    // EventKit 日历
    private let eventStore = EKEventStore()

    // Menu items
    private var menu: NSMenu!
    private var accountItem: NSMenuItem!
    private var sessionItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var sessionResetItem: NSMenuItem!
    private var weeklyResetItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!

    // 添加到日历的按钮
    private var addSessionCalendarItem: NSMenuItem!
    private var addWeeklyCalendarItem: NSMenuItem!

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

        // 添加 Session 重置时间到日历
        addSessionCalendarItem = NSMenuItem(title: "  📅 Add to Calendar", action: #selector(addSessionResetToCalendar), keyEquivalent: "")
        addSessionCalendarItem.target = self
        addSessionCalendarItem.isHidden = true  // 初始隐藏，有数据后显示
        menu.addItem(addSessionCalendarItem)

        menu.addItem(NSMenuItem.separator())

        // Current week (all models) usage
        weeklyItem = NSMenuItem(title: "Weekly: --", action: nil, keyEquivalent: "")
        weeklyItem.isEnabled = false
        menu.addItem(weeklyItem)

        weeklyResetItem = NSMenuItem(title: "  Resets: --", action: nil, keyEquivalent: "")
        weeklyResetItem.isEnabled = false
        menu.addItem(weeklyResetItem)

        // 添加 Weekly 重置时间到日历
        addWeeklyCalendarItem = NSMenuItem(title: "  📅 Add to Calendar", action: #selector(addWeeklyResetToCalendar), keyEquivalent: "")
        addWeeklyCalendarItem.target = self
        addWeeklyCalendarItem.isHidden = true  // 初始隐藏，有数据后显示
        menu.addItem(addWeeklyCalendarItem)

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
        // 使用 DispatchSourceTimer 替代 Timer，获得内核级精度
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)

        // 计算下一个整分钟的时间点
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let delayToNextMinute = Double(60 - seconds)

        // 使用 wallDeadline 确保系统睡眠唤醒后能基于墙上时钟正确恢复
        // leeway: .never 禁用系统的定时器合并优化，确保精确触发
        timer.schedule(
            wallDeadline: .now() + delayToNextMinute,
            repeating: 60.0,
            leeway: .never
        )

        timer.setEventHandler { [weak self] in
            self?.requestStatus()
        }

        timer.resume()
        dispatchTimer = timer
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
                self.addSessionCalendarItem.isHidden = false
            } else {
                self.sessionResetItem.title = "  Resets: --"
                self.addSessionCalendarItem.isHidden = true
            }

            // Update weekly usage
            if let weekly = data.weeklyPercent {
                self.weeklyItem.title = "Weekly (all models): \(weekly)%"
            } else {
                self.weeklyItem.title = "Weekly: N/A"
            }

            if let weeklyReset = data.weeklyReset {
                self.weeklyResetItem.title = "  Resets: \(weeklyReset)"
                self.addWeeklyCalendarItem.isHidden = false
            } else {
                self.weeklyResetItem.title = "  Resets: --"
                self.addWeeklyCalendarItem.isHidden = true
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

    // MARK: - 日历功能

    @objc private func addSessionResetToCalendar() {
        guard let resetTime = usageData?.sessionReset else { return }
        let account = usageData?.accountEmail ?? "Unknown"
        addResetToCalendar(resetTime: resetTime, title: "\(account) - Claude Session Reset")
    }

    @objc private func addWeeklyResetToCalendar() {
        guard let resetTime = usageData?.weeklyReset else { return }
        let account = usageData?.accountEmail ?? "Unknown"
        addResetToCalendar(resetTime: resetTime, title: "\(account) - Claude Weekly Reset")
    }

    private func addResetToCalendar(resetTime: String, title: String) {
        // 请求日历权限
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                if granted {
                    self?.createCalendarEvent(resetTime: resetTime, title: title)
                } else {
                    self?.showCalendarPermissionAlert()
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                if granted {
                    self?.createCalendarEvent(resetTime: resetTime, title: title)
                } else {
                    self?.showCalendarPermissionAlert()
                }
            }
        }
    }

    private func createCalendarEvent(resetTime: String, title: String) {
        guard let eventDate = parseResetTime(resetTime) else {
            DispatchQueue.main.async {
                self.showAlert(title: "无法解析时间", message: "时间格式无法识别: \(resetTime)")
            }
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = eventDate
        event.endDate = eventDate.addingTimeInterval(60 * 5)  // 5分钟事件
        event.calendar = eventStore.defaultCalendarForNewEvents

        // 添加提前5分钟的提醒
        let alarm = EKAlarm(relativeOffset: -5 * 60)  // 提前5分钟
        event.addAlarm(alarm)

        event.notes = "Claude Code 用量重置提醒\n添加时间: \(currentTimeString())"

        do {
            try eventStore.save(event, span: .thisEvent)
            DispatchQueue.main.async {
                self.showAlert(title: "已添加到日历 ✓", message: "\(title)\n时间: \(self.formatDate(eventDate))")
            }
        } catch {
            DispatchQueue.main.async {
                self.showAlert(title: "添加失败", message: error.localizedDescription)
            }
        }
    }

    private func parseResetTime(_ timeStr: String) -> Date? {
        let now = Date()
        let calendar = Calendar.current

        // 清理字符串
        let cleaned = timeStr.trimmingCharacters(in: .whitespaces)

        // 尝试解析 "8:59pm" 或 "3:59pm" 格式（今天的时间）
        let todayTimePattern = #"^(\d{1,2}):?(\d{2})?\s*(am|pm)$"#
        if let regex = try? NSRegularExpression(pattern: todayTimePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned)) {

            var hour = 0
            var minute = 0

            if let hourRange = Range(match.range(at: 1), in: cleaned) {
                hour = Int(String(cleaned[hourRange])) ?? 0
            }
            if let minuteRange = Range(match.range(at: 2), in: cleaned), minuteRange.lowerBound != minuteRange.upperBound {
                minute = Int(String(cleaned[minuteRange])) ?? 0
            }
            if let ampmRange = Range(match.range(at: 3), in: cleaned) {
                let ampm = String(cleaned[ampmRange]).lowercased()
                if ampm == "pm" && hour != 12 {
                    hour += 12
                } else if ampm == "am" && hour == 12 {
                    hour = 0
                }
            }

            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute

            if let date = calendar.date(from: components) {
                // 如果时间已过，设为明天
                if date <= now {
                    return calendar.date(byAdding: .day, value: 1, to: date)
                }
                return date
            }
        }

        // 尝试解析 "Jan 27, 3:59pm" 格式
        let dateTimePattern = #"^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{1,2}):?(\d{2})?\s*(am|pm)$"#
        if let regex = try? NSRegularExpression(pattern: dateTimePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleaned, options: [], range: NSRange(cleaned.startIndex..., in: cleaned)) {

            var month = 0
            var day = 0
            var hour = 0
            var minute = 0

            if let monthRange = Range(match.range(at: 1), in: cleaned) {
                let monthStr = String(cleaned[monthRange]).lowercased()
                let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                             "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
                month = months[monthStr] ?? 0
            }
            if let dayRange = Range(match.range(at: 2), in: cleaned) {
                day = Int(String(cleaned[dayRange])) ?? 0
            }
            if let hourRange = Range(match.range(at: 3), in: cleaned) {
                hour = Int(String(cleaned[hourRange])) ?? 0
            }
            if let minuteRange = Range(match.range(at: 4), in: cleaned), minuteRange.lowerBound != minuteRange.upperBound {
                minute = Int(String(cleaned[minuteRange])) ?? 0
            }
            if let ampmRange = Range(match.range(at: 5), in: cleaned) {
                let ampm = String(cleaned[ampmRange]).lowercased()
                if ampm == "pm" && hour != 12 {
                    hour += 12
                } else if ampm == "am" && hour == 12 {
                    hour = 0
                }
            }

            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute

            if let date = calendar.date(from: components) {
                // 如果日期已过，设为明年
                if date < now {
                    components.year = (components.year ?? 0) + 1
                    return calendar.date(from: components)
                }
                return date
            }
        }

        return nil
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showCalendarPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要日历权限"
            alert.informativeText = "请在系统设置 > 隐私与安全性 > 日历中允许此应用访问日历"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    func cleanup() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        claudeSession?.stop()
        claudeSession = nil
    }
}
