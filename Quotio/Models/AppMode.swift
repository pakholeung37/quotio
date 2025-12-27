//
//  AppMode.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  Dual-mode support: Full Mode (proxy + quota) vs Quota-Only Mode
//

import Foundation
import SwiftUI

// MARK: - App Mode

/// Represents the two primary operating modes of Quotio
enum AppMode: String, Codable, CaseIterable, Identifiable {
    case full = "full"           // Proxy server + Quota tracking (current behavior)
    case quotaOnly = "quota"     // Quota tracking only (no proxy required)
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .full: return "Full Mode"
        case .quotaOnly: return "Quota Monitor"
        }
    }
    
    var description: String {
        switch self {
        case .full:
            return "Run proxy server, manage multiple accounts, configure CLI agents"
        case .quotaOnly:
            return "Track quota usage without running proxy server"
        }
    }
    
    var icon: String {
        switch self {
        case .full: return "server.rack"
        case .quotaOnly: return "chart.bar.fill"
        }
    }
    
    var features: [String] {
        switch self {
        case .full:
            return [
                "Run local proxy server",
                "Manage multiple AI accounts",
                "Configure CLI agents (Claude Code, Codex, Gemini CLI)",
                "Track quota in menu bar",
                "API key management for clients"
            ]
        case .quotaOnly:
            return [
                "Track quota in menu bar",
                "No proxy server required",
                "Lightweight, minimal UI",
                "Direct quota fetching",
                "Like CodexBar / ccusage"
            ]
        }
    }
    
    /// Sidebar pages visible in this mode
    var visiblePages: [NavigationPage] {
        switch self {
        case .full:
            return [.dashboard, .quota, .providers, .agents, .apiKeys, .logs, .settings, .about]
        case .quotaOnly:
            return [.dashboard, .quota, .providers, .settings, .about]
        }
    }
    
    /// Whether proxy server should be available in this mode
    var supportsProxy: Bool {
        switch self {
        case .full: return true
        case .quotaOnly: return false
        }
    }
}

// MARK: - App Mode Manager

/// Singleton manager for app mode state
@Observable
final class AppModeManager {
    static let shared = AppModeManager()
    
    /// Current app mode - persisted to UserDefaults
    var currentMode: AppMode {
        get {
            if let stored = UserDefaults.standard.string(forKey: "appMode"),
               let mode = AppMode(rawValue: stored) {
                return mode
            }
            return .full
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appMode")
        }
    }
    
    /// Whether onboarding has been completed
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }
    
    /// Convenience check for quota-only mode
    var isQuotaOnlyMode: Bool { currentMode == .quotaOnly }
    
    /// Convenience check for full mode
    var isFullMode: Bool { currentMode == .full }
    
    /// Check if a page should be visible in current mode
    func isPageVisible(_ page: NavigationPage, loggingEnabled: Bool = true) -> Bool {
        var visiblePages = currentMode.visiblePages
        
        // Hide logs if logging is disabled (even in full mode)
        if !loggingEnabled {
            visiblePages.removeAll { $0 == .logs }
        }
        
        return visiblePages.contains(page)
    }
    
    /// Switch mode with validation
    func switchMode(to newMode: AppMode, stopProxyIfNeeded: @escaping () -> Void) {
        if currentMode == .full && newMode == .quotaOnly {
            // Stop proxy when switching to quota-only mode
            stopProxyIfNeeded()
        }
        currentMode = newMode
    }
    
    private init() {}
}
