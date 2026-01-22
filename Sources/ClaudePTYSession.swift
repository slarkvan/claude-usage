import Foundation

struct UsageData {
    var sessionPercent: Int?      // Current session usage
    var weeklyPercent: Int?       // Current week (all models) usage
    var sessionReset: String?     // Session reset time
    var weeklyReset: String?      // Weekly reset time
    var accountEmail: String?     // Account email
    var accountPlan: String?      // Account plan name
}

class ClaudePTYSession {
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = ""
    private var isWaitingForStatus = false
    private var statusTimeout: DispatchWorkItem?
    private var logFileHandle: FileHandle?
    private var isReady = false

    var onStatusUpdate: ((UsageData) -> Void)?
    var onError: ((String) -> Void)?
    var onRawOutput: ((String) -> Void)?
    var onReady: (() -> Void)?

    var isRunning: Bool {
        return process?.isRunning ?? false
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            logFileHandle?.write(data)
        }
    }

    func start() {
        // Setup log file
        let logPath = NSHomeDirectory() + "/.claude/widget-debug.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        logFileHandle = FileHandle(forWritingAtPath: logPath)
        log("Starting Claude PTY Session...")

        // Find claude binary
        let claudePath = findClaudePath()
        guard let path = claudePath else {
            onError?("Claude binary not found")
            log("ERROR: Claude binary not found")
            return
        }
        log("Found claude at: \(path)")

        // Create pipes
        inputPipe = Pipe()
        outputPipe = Pipe()

        // Use unbuffer or script to get PTY
        // Try unbuffer first (from expect package), fall back to script
        let unbufferPath = "/opt/homebrew/bin/unbuffer"
        let useUnbuffer = FileManager.default.fileExists(atPath: unbufferPath)

        process = Process()

        if useUnbuffer {
            log("Using unbuffer for PTY")
            process?.executableURL = URL(fileURLWithPath: unbufferPath)
            process?.arguments = ["-p", path]
        } else {
            log("Using script for PTY (macOS native)")
            // macOS script command syntax: script -q outputfile command
            // Using /dev/null as output file and passing command directly
            process?.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process?.arguments = ["-q", "/dev/null", path]
        }

        process?.standardInput = inputPipe
        process?.standardOutput = outputPipe
        process?.standardError = outputPipe

        // Set environment - inherit from shell to get proxy settings etc.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["HOME"] = NSHomeDirectory()

        // Load user's shell environment to get proxy settings
        if let shellEnv = loadShellEnvironment() {
            for (key, value) in shellEnv {
                // Copy all env vars, especially proxy settings
                env[key] = value
                // Also set uppercase versions for compatibility
                if key.lowercased().contains("proxy") {
                    env[key.uppercased()] = value
                    log("Proxy setting: \(key)=\(value)")
                }
            }
        }

        process?.environment = env

        // Set current directory to home
        process?.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Setup output handler
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                self?.onError?("Session ended")
                return
            }

            if let str = String(data: data, encoding: .utf8) {
                self?.handleOutput(str)
            }
        }

        // Start process
        do {
            try process?.run()
            log("Process started")

            // Auto-confirm the "trust folder" dialog
            // Wait for the dialog to fully render before sending Enter
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self = self else { return }
                self.log("Sending Enter to confirm trust dialog...")
                self.sendInput("\r")  // Use \r for Enter in terminal
            }

            // Fallback: Mark as ready after startup if not detected earlier
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self = self, !self.isReady else { return }
                self.isReady = true
                self.log("Session marked as ready (fallback timer)")
                self.onReady?()
            }
        } catch {
            onError?("Failed to start: \(error.localizedDescription)")
            log("Failed to start: \(error.localizedDescription)")
        }
    }

    private func sendInput(_ text: String) {
        if let data = text.data(using: .utf8) {
            inputPipe?.fileHandleForWriting.write(data)
            log("Sent input: \(text.debugDescription)")
        }
    }

    private func loadShellEnvironment() -> [String: String]? {
        // Run shell to get environment variables including proxy settings
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let envProcess = Process()
        let pipe = Pipe()

        envProcess.executableURL = URL(fileURLWithPath: shell)
        // Use -l for login shell to load .zprofile/.zshrc
        // Avoid -i (interactive) as it can hang waiting for input
        envProcess.arguments = ["-l", "-c", "env"]
        envProcess.standardOutput = pipe
        envProcess.standardError = FileHandle.nullDevice
        envProcess.standardInput = FileHandle.nullDevice  // Prevent waiting for input
        envProcess.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        do {
            try envProcess.run()

            // Add timeout to prevent hanging
            let deadline = DispatchTime.now() + .seconds(5)
            let result = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                envProcess.waitUntilExit()
                result.signal()
            }

            if result.wait(timeout: deadline) == .timedOut {
                envProcess.terminate()
                log("Shell environment loading timed out")
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            var envDict = [String: String]()
            for line in output.components(separatedBy: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    envDict[String(parts[0])] = String(parts[1])
                }
            }
            log("Loaded \(envDict.count) environment variables from shell")
            return envDict
        } catch {
            log("Failed to load shell environment: \(error)")
            return nil
        }
    }

    private func findClaudePath() -> String? {
        // Common installation paths
        let paths = [
            "\(NSHomeDirectory())/.nvm/versions/node/v22.18.0/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "\(NSHomeDirectory())/.npm-global/bin/claude"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try which command
        let whichProcess = Process()
        let whichPipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        whichProcess.arguments = ["-c", "which claude"]
        whichProcess.standardOutput = whichPipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return output
            }
        } catch {
            // Ignore
        }

        return nil
    }

    private func handleOutput(_ text: String) {
        outputBuffer += text
        onRawOutput?(text)
        log("RAW OUTPUT: \(text.debugDescription)")

        // Check for ready indicators - look for the main prompt after trust dialog
        // The prompt shows "Welcome back" after the trust dialog is confirmed
        // Also look for "? for shortcuts" which appears at the bottom of the main UI
        let hasWelcome = text.contains("Welcome back") || outputBuffer.contains("Welcome back")
        let hasShortcuts = text.contains("? for shortcuts")
        let hasMainPrompt = hasWelcome || hasShortcuts

        if !isReady && hasMainPrompt {
            isReady = true
            log("Session became ready (detected main prompt)")
            // Clear the buffer since we're past the trust dialog
            outputBuffer = ""
            onReady?()
        }

        if isWaitingForStatus {
            // Check for "forbidden" error and retry
            if outputBuffer.contains("forbidden") || outputBuffer.contains("Request not allowed") {
                log("Detected forbidden error, sending 'r' to retry...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.sendInput("r")  // Press 'r' to retry
                }
                outputBuffer = ""  // Clear buffer for retry
                return
            }

            // Check if we have the USAGE TAB data specifically
            // Must have "Current session" AND "% used" to confirm Usage tab loaded
            let hasCurrentSession = outputBuffer.lowercased().contains("current session")
            let hasCurrentWeek = outputBuffer.lowercased().contains("current week")
            let hasPercentUsed = outputBuffer.contains("% used")

            // Only parse when we have Usage tab data (not Status or Config tab)
            if hasCurrentSession && hasPercentUsed && hasCurrentWeek {
                log("Detected Usage tab data in buffer (\(outputBuffer.count) chars)")

                // Wait a bit more to collect complete output
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, self.isWaitingForStatus else { return }

                    self.log("BUFFER FOR PARSE: \(self.outputBuffer.debugDescription)")

                    if let data = StatusParser.parse(self.outputBuffer) {
                        self.log("Parsed successfully: session=\(data.sessionPercent ?? -1)%, weekly=\(data.weeklyPercent ?? -1)%")
                        self.isWaitingForStatus = false
                        self.statusTimeout?.cancel()
                        self.statusTimeout = nil
                        self.outputBuffer = ""
                        self.onStatusUpdate?(data)
                    }
                }
            }
        }

        // Keep buffer from growing too large
        if outputBuffer.count > 50000 {
            outputBuffer = String(outputBuffer.suffix(10000))
        }
    }

    func sendStatus() {
        guard isRunning else {
            onError?("Session not running")
            log("sendStatus called but session not running")
            return
        }

        guard isReady else {
            log("sendStatus called but session not ready")
            return
        }

        log("Sending /status command...")
        isWaitingForStatus = true
        outputBuffer = ""

        // Cancel any existing timeout
        statusTimeout?.cancel()

        // Set a timeout for status response
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.isWaitingForStatus else { return }
            self.isWaitingForStatus = false
            self.log("Status timeout reached. Buffer: \(self.outputBuffer.debugDescription)")

            // Try to parse whatever we have
            if let data = StatusParser.parse(self.outputBuffer) {
                self.log("Timeout parse succeeded")
                self.onStatusUpdate?(data)
            } else {
                self.log("Timeout parse failed")
                self.onError?("Status timeout - no data parsed")
            }
            self.outputBuffer = ""
        }
        statusTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        // Send /status command
        // Type /status, press Tab to autocomplete, then Enter to execute
        sendInput("/status")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendInput("\t")  // Tab to accept autocomplete
            self?.log("Sent Tab for autocomplete")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sendInput("\r")  // Enter to execute
            self?.log("Sent Enter to execute")
        }
        // Navigate to Usage tab (right arrow twice: Status -> Config -> Usage)
        // Wait longer for the status dialog to appear
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { [weak self] in
            // Right arrow: ESC [ C
            self?.sendInput("\u{1B}[C")  // First right arrow
            self?.log("Sent Right arrow 1")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.sendInput("\u{1B}[C")  // Second right arrow
            self?.log("Sent Right arrow 2")
        }
    }

    func stop() {
        log("Stopping session...")
        statusTimeout?.cancel()
        statusTimeout = nil

        outputPipe?.fileHandleForReading.readabilityHandler = nil

        if let process = process, process.isRunning {
            // Send exit command first
            sendInput("/exit\r")

            // Wait a bit then terminate
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        try? inputPipe?.fileHandleForWriting.close()
        try? logFileHandle?.close()
        process = nil
        inputPipe = nil
        outputPipe = nil
        logFileHandle = nil
    }
}
