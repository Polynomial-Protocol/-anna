import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

final class MacPermissionService: PermissionService {
    func currentStatuses() -> [PermissionStatus] {
        PermissionKind.allCases.map { status(for: $0) }
    }

    func refresh() -> [PermissionStatus] {
        currentStatuses()
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .denied,
                detail: granted ? "Microphone access granted." : "Microphone access denied."
            )
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let granted = AXIsProcessTrustedWithOptions(options)
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .manualStepRequired,
                detail: granted ? "Accessibility access granted." : "Enable Anna in Privacy & Security > Accessibility."
            )
        case .automation:
            _ = Self.runAppleScript("tell application \"Finder\" to get name of startup disk")
            return status(for: kind)
        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .manualStepRequired,
                detail: granted ? "Screen Recording granted." : "Enable Anna in Privacy & Security > Screen Recording."
            )
        }
    }

    func openSystemSettings(for kind: PermissionKind) {
        let paneURL: URL?
        switch kind {
        case .microphone:
            paneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            paneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .automation:
            paneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .screenRecording:
            paneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }

        if let paneURL {
            NSWorkspace.shared.open(paneURL)
        }
    }

    private func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone:
            let state: PermissionState
            let detail: String
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                state = .granted
                detail = "Microphone access is ready."
            case .notDetermined:
                state = .notRequested
                detail = "Anna will ask when you first speak."
            case .denied, .restricted:
                state = .denied
                detail = "Allow microphone access in System Settings."
            @unknown default:
                state = .manualStepRequired
                detail = "Review microphone access manually."
            }
            return PermissionStatus(kind: kind, state: state, detail: detail)
        case .accessibility:
            let granted = AXIsProcessTrusted()
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .manualStepRequired,
                detail: granted ? "Accessibility access is ready." : "Anna needs Accessibility access for shortcuts and text insertion."
            )
        case .automation:
            let granted = Self.checkAutomationAccess()
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .manualStepRequired,
                detail: granted ? "Automation access is ready." : "Grant automation when prompted, or enable in Privacy & Security > Automation."
            )
        case .screenRecording:
            let granted = CGPreflightScreenCaptureAccess()
            return PermissionStatus(
                kind: kind,
                state: granted ? .granted : .notRequested,
                detail: granted ? "Screen Recording is ready." : "Needed so Anna can see your screen and guide you."
            )
        }
    }

    /// Check if we can control System Events (proxy for automation access)
    private static func checkAutomationAccess() -> Bool {
        let script = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        if let error = error,
           let errorNumber = error[NSAppleScript.errorNumber] as? Int,
           errorNumber == -1743 { // "Not authorized" error
            return false
        }
        return error == nil
    }

    private static func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }
}
