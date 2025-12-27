//
//  ClaudeCodeQuotaFetcher.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  Fetches quota from Claude Code CLI by running /usage and /status commands
//  Used in Quota-Only mode
//

import Foundation

/// Quota data from Claude Code CLI
struct ClaudeCodeQuotaInfo: Sendable {
    let email: String?
    let organizationName: String?
    let loginMethod: String?
    let planType: String?
    
    /// Weekly usage info
    let weeklyUsage: WeeklyUsage?
    let sonnetOnlyUsage: WeeklyUsage?
    
    struct WeeklyUsage: Sendable {
        let used: Int
        let limit: Int
        let remaining: Int
        let resetTime: Date?
        
        var percentage: Double {
            guard limit > 0 else { return 100 }
            return Double(remaining) / Double(limit) * 100
        }
    }
}

/// Fetches quota from Claude Code CLI
actor ClaudeCodeQuotaFetcher {
    private let executor = CLIExecutor.shared
    
    /// Check if Claude CLI is installed
    func isInstalled() async -> Bool {
        return await executor.isCLIInstalled(name: "claude")
    }
    
    /// Fetch quota info from Claude CLI
    func fetchQuota() async -> ClaudeCodeQuotaInfo? {
        guard await isInstalled() else { return nil }
        
        // Try to get status info first
        let statusResult = await executor.executeCLI(name: "claude", arguments: ["/status"], timeout: 15)
        
        // Then get usage info
        let usageResult = await executor.executeCLI(name: "claude", arguments: ["/usage"], timeout: 15)
        
        // Parse both outputs
        return parseClaudeOutput(statusOutput: statusResult.combinedOutput, usageOutput: usageResult.combinedOutput)
    }
    
    /// Parse Claude CLI output
    private func parseClaudeOutput(statusOutput: String, usageOutput: String) -> ClaudeCodeQuotaInfo? {
        var email: String? = nil
        var orgName: String? = nil
        var loginMethod: String? = nil
        var planType: String? = nil
        var weeklyUsage: ClaudeCodeQuotaInfo.WeeklyUsage? = nil
        var sonnetOnlyUsage: ClaudeCodeQuotaInfo.WeeklyUsage? = nil
        
        // Parse status output for account info
        // Expected format:
        // Email: user@example.com
        // Organization: My Org
        // Login Method: OAuth
        // Plan: Pro
        
        for line in statusOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.lowercased().hasPrefix("email:") {
                email = extractValue(from: trimmed, key: "email")
            } else if trimmed.lowercased().hasPrefix("organization:") || trimmed.lowercased().hasPrefix("org:") {
                orgName = extractValue(from: trimmed, key: "organization") ?? extractValue(from: trimmed, key: "org")
            } else if trimmed.lowercased().hasPrefix("login method:") || trimmed.lowercased().hasPrefix("auth:") {
                loginMethod = extractValue(from: trimmed, key: "login method") ?? extractValue(from: trimmed, key: "auth")
            } else if trimmed.lowercased().hasPrefix("plan:") {
                planType = extractValue(from: trimmed, key: "plan")
            }
        }
        
        // Parse usage output
        // Expected format varies, but typically:
        // Weekly usage: 150/500 (30%)
        // Sonnet-only: 50/100 (50%)
        // Resets in: 3d 5h
        
        weeklyUsage = parseUsageSection(from: usageOutput, sectionName: "weekly")
        sonnetOnlyUsage = parseUsageSection(from: usageOutput, sectionName: "sonnet")
        
        // If we couldn't parse structured data, try alternative patterns
        if weeklyUsage == nil {
            weeklyUsage = parseAlternativeUsageFormat(from: usageOutput)
        }
        
        // Return nil if we got nothing useful
        guard email != nil || weeklyUsage != nil else {
            return nil
        }
        
        return ClaudeCodeQuotaInfo(
            email: email,
            organizationName: orgName,
            loginMethod: loginMethod,
            planType: planType,
            weeklyUsage: weeklyUsage,
            sonnetOnlyUsage: sonnetOnlyUsage
        )
    }
    
    private func extractValue(from line: String, key: String) -> String? {
        let pattern = "\(key):\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = regex.firstMatch(in: line, options: [], range: range) {
            if let valueRange = Range(match.range(at: 1), in: line) {
                return String(line[valueRange]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func parseUsageSection(from output: String, sectionName: String) -> ClaudeCodeQuotaInfo.WeeklyUsage? {
        // Look for patterns like:
        // "Weekly: 150/500" or "Weekly usage: 150 of 500" or "150/500 (30%)"
        
        let lines = output.lowercased().components(separatedBy: "\n")
        
        for line in lines {
            if line.contains(sectionName) || (sectionName == "weekly" && line.contains("usage")) {
                return parseUsageLine(line)
            }
        }
        
        return nil
    }
    
    private func parseUsageLine(_ line: String) -> ClaudeCodeQuotaInfo.WeeklyUsage? {
        // Pattern 1: "150/500" or "150 / 500"
        let slashPattern = #"(\d+)\s*/\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: slashPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) {
            if let usedRange = Range(match.range(at: 1), in: line),
               let limitRange = Range(match.range(at: 2), in: line),
               let used = Int(line[usedRange]),
               let limit = Int(line[limitRange]) {
                return ClaudeCodeQuotaInfo.WeeklyUsage(
                    used: used,
                    limit: limit,
                    remaining: limit - used,
                    resetTime: parseResetTime(from: line)
                )
            }
        }
        
        // Pattern 2: "150 of 500" or "150 out of 500"
        let ofPattern = #"(\d+)\s*(?:of|out of)\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: ofPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) {
            if let usedRange = Range(match.range(at: 1), in: line),
               let limitRange = Range(match.range(at: 2), in: line),
               let used = Int(line[usedRange]),
               let limit = Int(line[limitRange]) {
                return ClaudeCodeQuotaInfo.WeeklyUsage(
                    used: used,
                    limit: limit,
                    remaining: limit - used,
                    resetTime: nil
                )
            }
        }
        
        return nil
    }
    
    private func parseAlternativeUsageFormat(from output: String) -> ClaudeCodeQuotaInfo.WeeklyUsage? {
        // Try to find any usage pattern in the entire output
        let fullText = output.lowercased()
        
        // Look for percentage patterns like "70% remaining" or "30% used"
        let percentPattern = #"(\d+)%\s*(remaining|left|used|consumed)"#
        if let regex = try? NSRegularExpression(pattern: percentPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..<fullText.endIndex, in: fullText)) {
            if let percentRange = Range(match.range(at: 1), in: fullText),
               let typeRange = Range(match.range(at: 2), in: fullText),
               let percent = Int(fullText[percentRange]) {
                let type = String(fullText[typeRange])
                let remaining = type.contains("remaining") || type.contains("left") ? percent : 100 - percent
                
                // Assume a limit of 100 for percentage-based display
                return ClaudeCodeQuotaInfo.WeeklyUsage(
                    used: 100 - remaining,
                    limit: 100,
                    remaining: remaining,
                    resetTime: parseResetTime(from: output)
                )
            }
        }
        
        return nil
    }
    
    private func parseResetTime(from text: String) -> Date? {
        // Look for patterns like "resets in 3d 5h" or "reset in 2 hours"
        let resetPatterns = [
            #"resets?\s+in\s+(\d+)d\s*(\d+)?h?"#,
            #"resets?\s+in\s+(\d+)\s*hours?"#,
            #"resets?\s+in\s+(\d+)\s*days?"#
        ]
        
        for pattern in resetPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                // Parse days and hours
                if match.numberOfRanges >= 2,
                   let daysRange = Range(match.range(at: 1), in: text),
                   let days = Int(text[daysRange]) {
                    var totalHours = days * 24
                    
                    if match.numberOfRanges >= 3,
                       let hoursRange = Range(match.range(at: 2), in: text),
                       let hours = Int(text[hoursRange]) {
                        totalHours += hours
                    }
                    
                    return Date().addingTimeInterval(TimeInterval(totalHours * 3600))
                }
            }
        }
        
        return nil
    }
    
    /// Convert ClaudeCodeQuotaInfo to ProviderQuotaData for unified display
    func fetchAsProviderQuota() async -> [String: ProviderQuotaData] {
        guard let info = await fetchQuota() else { return [:] }
        
        var models: [ModelQuota] = []
        
        if let weekly = info.weeklyUsage {
            // Convert reset time to ISO8601 string
            let resetTimeStr: String
            if let resetTime = weekly.resetTime {
                resetTimeStr = ISO8601DateFormatter().string(from: resetTime)
            } else {
                resetTimeStr = ""
            }
            
            models.append(ModelQuota(
                name: "weekly-usage",
                percentage: weekly.percentage,
                resetTime: resetTimeStr
            ))
        }
        
        if let sonnet = info.sonnetOnlyUsage {
            let resetTimeStr: String
            if let resetTime = sonnet.resetTime {
                resetTimeStr = ISO8601DateFormatter().string(from: resetTime)
            } else {
                resetTimeStr = ""
            }
            
            models.append(ModelQuota(
                name: "sonnet-only",
                percentage: sonnet.percentage,
                resetTime: resetTimeStr
            ))
        }
        
        guard !models.isEmpty else { return [:] }
        
        let email = info.email ?? "Claude Code User"
        let quotaData = ProviderQuotaData(
            models: models,
            lastUpdated: Date(),
            isForbidden: false,
            planType: info.planType
        )
        
        return [email: quotaData]
    }
}
