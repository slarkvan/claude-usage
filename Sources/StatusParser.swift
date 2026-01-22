import Foundation

class StatusParser {
    /// Strip ANSI escape codes from string
    static func stripAnsi(_ text: String) -> String {
        // Remove ANSI escape sequences
        let pattern = "\\x1B\\[[0-9;]*[a-zA-Z]|\\x1B\\][^\\x07]*\\x07|\\x1B[PX^_][^\\x1B]*\\x1B\\\\|\\x1B."
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        var result = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")

        // Normalize multiple spaces to single space
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        return result
    }

    /// Parse /status output to extract usage data
    static func parse(_ output: String) -> UsageData? {
        let cleaned = stripAnsi(output)
        // Split by both \n and \r since terminal output uses mixed line endings
        let lines = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "\n")
                           .components(separatedBy: "\n")

        var data = UsageData()
        var foundData = false

        // Parse account email
        let emailPattern = "([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})"
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, options: [], range: range),
               let emailRange = Range(match.range(at: 1), in: cleaned) {
                data.accountEmail = String(cleaned[emailRange])
                foundData = true
            }
        }

        // Parse plan name - look for "Claude Pro", "Claude Max", etc.
        let planPattern = "Claude\\s+(Pro|Max|Team|Enterprise|Free)"
        if let regex = try? NSRegularExpression(pattern: planPattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, options: [], range: range),
               let planRange = Range(match.range(at: 1), in: cleaned) {
                data.accountPlan = String(cleaned[planRange])
            }
        }

        // State machine to track which section we're in
        var currentSection: String? = nil

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Check for "Current session"
            if trimmedLine.lowercased().contains("current session") {
                currentSection = "session"
            }
            // Check for "Current week (all models)"
            else if trimmedLine.lowercased().contains("current week") {
                currentSection = "weekly"
            }
            // Check for "XX% used" pattern
            else if trimmedLine.contains("% used") || trimmedLine.contains("%used") {
                if let percent = extractPercentage(from: trimmedLine) {
                    if currentSection == "session" && data.sessionPercent == nil {
                        data.sessionPercent = percent
                        foundData = true
                    } else if currentSection == "weekly" && data.weeklyPercent == nil {
                        data.weeklyPercent = percent
                        foundData = true
                    }
                }
            }
            // Check for "Resets XXX" or "Rese s XXX" pattern on separate line
            else if let resetTime = extractResetTimeFromLine(trimmedLine) {
                if currentSection == "session" && data.sessionReset == nil {
                    data.sessionReset = resetTime
                } else if currentSection == "weekly" && data.weeklyReset == nil {
                    data.weeklyReset = resetTime
                }
            }
        }

        return foundData ? data : nil
    }

    /// Extract reset time from a line like "Resets 7pm (Asia/Shanghai)" or "Rese s 7pm"
    private static func extractResetTimeFromLine(_ line: String) -> String? {
        // Pattern: Resets (or various ANSI-stripped artifacts) followed by time
        // After ANSI stripping, "Resets" might become:
        // - "Resets" (normal)
        // - "Rese s" (with space from cursor movement)
        // - "Reses" (cursor movements stripped, no space)
        // - "Reset s" etc.
        let patterns = [
            "Resets\\s+([^(]+)",              // Normal "Resets XXX"
            "Rese\\s*t?\\s*s\\s+([^(]+)",     // "Rese s XXX" or "Reset s XXX"
            "Reses\\s*([^(]+)",               // "Reses7pm" - no space after strip
            "Reset\\s+([^(]+)"                // "Reset XXX"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let timeRange = Range(match.range(at: 1), in: line) {
                return String(line[timeRange]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    /// Extract percentage number from string like "11% used"
    private static func extractPercentage(from text: String) -> Int? {
        let pattern = "(\\d+)\\s*%"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let percentRange = Range(match.range(at: 1), in: text) {
            return Int(String(text[percentRange]))
        }

        return nil
    }
}
