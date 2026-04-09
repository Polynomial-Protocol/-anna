import AVFoundation
import ApplicationServices
import AppKit
import CoreGraphics
import EventKit
import Contacts
import UserNotifications
import Foundation

final class MacPermissionService: PermissionService {

    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()

    // MARK: - PermissionService

    func currentStatuses() -> [PermissionStatus] {
        PermissionKind.onboardingSequence.map { status(for: $0) }
    }

    func refresh() -> [PermissionStatus] {
        currentStatuses()
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .microphone:
            return await requestMicrophone()
        case .accessibility:
            return requestAccessibility()
        case .screenRecording:
            return requestScreenRecording()
        case .automation:
            return await requestAutomation()
        case .reminders:
            return await requestReminders()
        case .calendar:
            return await requestCalendar()
        case .contacts:
            return await requestContacts()
        case .notifications:
            return await requestNotifications()
        }
    }

    func openSystemSettings(for kind: PermissionKind) {
        let urlString: String
        switch kind {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .automation:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .reminders:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        case .calendar:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .contacts:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Individual Requests

    private func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return PermissionStatus(
            kind: .microphone,
            state: granted ? .granted : .denied,
            detail: granted
                ? "Microphone access granted."
                : "Microphone was denied. Open System Settings to enable it."
        )
    }

    private func requestAccessibility() -> PermissionStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return PermissionStatus(
            kind: .accessibility,
            state: trusted ? .granted : .manualStepRequired,
            detail: trusted
                ? "Accessibility access granted."
                : "Enable Anna in System Settings \u{2192} Privacy & Security \u{2192} Accessibility."
        )
    }

    private func requestScreenRecording() -> PermissionStatus {
        let granted = CGRequestScreenCaptureAccess()
        return PermissionStatus(
            kind: .screenRecording,
            state: granted ? .granted : .manualStepRequired,
            detail: granted
                ? "Screen Recording access granted."
                : "Enable Anna in System Settings \u{2192} Privacy & Security \u{2192} Screen Recording."
        )
    }

    private func requestAutomation() async -> PermissionStatus {
        _ = Self.runAppleScript("tell application \"System Events\" to return name of first process")
        try? await Task.sleep(for: .milliseconds(500))
        return status(for: .automation)
    }

    private func requestReminders() async -> PermissionStatus {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            return PermissionStatus(
                kind: .reminders,
                state: granted ? .granted : .denied,
                detail: granted
                    ? "Reminders access granted."
                    : "Reminders access denied. Open System Settings to enable it."
            )
        } catch {
            return PermissionStatus(
                kind: .reminders,
                state: .denied,
                detail: "Could not request Reminders access: \(error.localizedDescription)"
            )
        }
    }

    private func requestCalendar() async -> PermissionStatus {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            return PermissionStatus(
                kind: .calendar,
                state: granted ? .granted : .denied,
                detail: granted
                    ? "Calendar access granted."
                    : "Calendar access denied. Open System Settings to enable it."
            )
        } catch {
            return PermissionStatus(
                kind: .calendar,
                state: .denied,
                detail: "Could not request Calendar access: \(error.localizedDescription)"
            )
        }
    }

    private func requestContacts() async -> PermissionStatus {
        return await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                let status = PermissionStatus(
                    kind: .contacts,
                    state: granted ? .granted : .denied,
                    detail: granted
                        ? "Contacts access granted."
                        : "Contacts access denied. Open System Settings to enable it."
                )
                continuation.resume(returning: status)
            }
        }
    }

    private func requestNotifications() async -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return PermissionStatus(
                kind: .notifications,
                state: granted ? .granted : .denied,
                detail: granted
                    ? "Notifications enabled."
                    : "Notifications denied. Open System Settings to enable them."
            )
        } catch {
            return PermissionStatus(
                kind: .notifications,
                state: .denied,
                detail: "Could not request notification access: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Status Checks

    func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone: return microphoneStatus()
        case .accessibility: return accessibilityStatus()
        case .screenRecording: return screenRecordingStatus()
        case .automation: return automationStatus()
        case .reminders: return remindersStatus()
        case .calendar: return calendarStatus()
        case .contacts: return contactsStatus()
        case .notifications: return notificationsStatus()
        }
    }

    private func microphoneStatus() -> PermissionStatus {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let state: PermissionState
        let detail: String
        switch authStatus {
        case .authorized:
            state = .granted; detail = "Microphone access is ready."
        case .notDetermined:
            state = .notRequested; detail = "Anna will ask when you first speak."
        case .denied:
            state = .denied; detail = "Microphone access was denied. Open System Settings to enable it."
        case .restricted:
            state = .denied; detail = "Microphone access is restricted by a system policy."
        @unknown default:
            state = .denied; detail = "Unable to determine microphone status."
        }
        return PermissionStatus(kind: .microphone, state: state, detail: detail)
    }

    private func accessibilityStatus() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return PermissionStatus(
            kind: .accessibility,
            state: trusted ? .granted : .manualStepRequired,
            detail: trusted
                ? "Accessibility access is ready."
                : "Anna needs Accessibility for global shortcuts and text insertion."
        )
    }

    private func screenRecordingStatus() -> PermissionStatus {
        let granted = CGPreflightScreenCaptureAccess()
        return PermissionStatus(
            kind: .screenRecording,
            state: granted ? .granted : .notRequested,
            detail: granted
                ? "Screen Recording is ready."
                : "Needed so Anna can see your screen and guide you visually."
        )
    }

    private func automationStatus() -> PermissionStatus {
        let granted = Self.checkAutomationAccess()
        return PermissionStatus(
            kind: .automation,
            state: granted ? .granted : .manualStepRequired,
            detail: granted
                ? "Automation access is ready."
                : "Grant automation when macOS prompts, or enable in System Settings."
        )
    }

    private func remindersStatus() -> PermissionStatus {
        let authStatus = EKEventStore.authorizationStatus(for: .reminder)
        let state: PermissionState
        let detail: String
        switch authStatus {
        case .fullAccess, .authorized:
            state = .granted; detail = "Reminders access is ready."
        case .notDetermined:
            state = .notRequested; detail = "Anna will ask when you first create a reminder or alarm."
        case .denied:
            state = .denied; detail = "Reminders access was denied. Open System Settings to enable it."
        case .restricted:
            state = .denied; detail = "Reminders access is restricted by a system policy."
        case .writeOnly:
            state = .granted; detail = "Reminders write access is ready."
        @unknown default:
            state = .denied; detail = "Unable to determine Reminders status."
        }
        return PermissionStatus(kind: .reminders, state: state, detail: detail)
    }

    private func calendarStatus() -> PermissionStatus {
        let authStatus = EKEventStore.authorizationStatus(for: .event)
        let state: PermissionState
        let detail: String
        switch authStatus {
        case .fullAccess, .authorized:
            state = .granted; detail = "Calendar access is ready."
        case .notDetermined:
            state = .notRequested; detail = "Anna will ask when you first interact with your calendar."
        case .denied:
            state = .denied; detail = "Calendar access was denied. Open System Settings to enable it."
        case .restricted:
            state = .denied; detail = "Calendar access is restricted by a system policy."
        case .writeOnly:
            state = .granted; detail = "Calendar write access is ready."
        @unknown default:
            state = .denied; detail = "Unable to determine Calendar status."
        }
        return PermissionStatus(kind: .calendar, state: state, detail: detail)
    }

    private func contactsStatus() -> PermissionStatus {
        let authStatus = CNContactStore.authorizationStatus(for: .contacts)
        let state: PermissionState
        let detail: String
        switch authStatus {
        case .authorized:
            state = .granted; detail = "Contacts access is ready."
        case .notDetermined:
            state = .notRequested; detail = "Anna will ask when you first mention a contact."
        case .denied:
            state = .denied; detail = "Contacts access was denied. Open System Settings to enable it."
        case .restricted:
            state = .denied; detail = "Contacts access is restricted by a system policy."
        @unknown default:
            state = .denied; detail = "Unable to determine Contacts status."
        }
        return PermissionStatus(kind: .contacts, state: state, detail: detail)
    }

    private func notificationsStatus() -> PermissionStatus {
        // UNUserNotificationCenter.current().notificationSettings() is async,
        // but status() is synchronous. We return .notRequested as the safe default
        // and let the async request path update it.
        // For a synchronous check, we rely on cached state.
        var resultStatus = PermissionStatus(
            kind: .notifications,
            state: .notRequested,
            detail: "Anna will ask when it first needs to notify you."
        )

        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                resultStatus = PermissionStatus(
                    kind: .notifications,
                    state: .granted,
                    detail: "Notifications are enabled."
                )
            case .denied:
                resultStatus = PermissionStatus(
                    kind: .notifications,
                    state: .denied,
                    detail: "Notifications were denied. Open System Settings to enable them."
                )
            case .notDetermined:
                break // keep default
            @unknown default:
                break
            }
            semaphore.signal()
        }
        semaphore.wait()
        return resultStatus
    }

    // MARK: - Helpers

    private static func checkAutomationAccess() -> Bool {
        let script = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        if let error,
           let errorNumber = error[NSAppleScript.errorNumber] as? Int,
           errorNumber == -1743 {
            return false
        }
        return error == nil
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }
}
