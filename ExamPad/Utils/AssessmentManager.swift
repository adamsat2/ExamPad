//
//  AssessmentManager.swift
//  ExamPad
//

import Foundation
import Combine
import AutomaticAssessmentConfiguration
import UIKit
import UserNotifications

/// Subclass of UIViewController that swizzles or overrides `preferredScreenEdgesDeferringSystemGestures`
/// on the root hosting controller when `ExamLockdownState.isLocked` is true.
enum ExamLockdownState {
    @MainActor static var isLocked: Bool = false
    
    @MainActor
    static func installEdgeDeferralSupport() {
        _ = swizzleOnce
    }
    
    private static let swizzleOnce: Void = {
        let cls: AnyClass = UIViewController.self
        let originalSelector = #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures)
        let swizzledSelector = #selector(UIViewController.exampad_preferredScreenEdgesDeferringSystemGestures)
        
        if let originalMethod = class_getInstanceMethod(cls, originalSelector),
           let swizzledMethod = class_getInstanceMethod(cls, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()
}

extension UIViewController {
    @objc func exampad_preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        if Thread.isMainThread {
            let locked = MainActor.assumeIsolated { ExamLockdownState.isLocked }
            if locked {
                return .all
            }
        }
        return exampad_preferredScreenEdgesDeferringSystemGestures()
    }
}

/// Manages device locking, window resize blocking, first-swipe edge deferral, tamper/exit detection,
/// and notification suppression during an exam.
@MainActor
final class AssessmentManager: NSObject, ObservableObject {
    @Published private(set) var isExamLocked: Bool = false
    @Published private(set) var isHardwareAssessmentActive: Bool = false
    @Published var tamperViolationCount: Int = 0
    @Published var showTamperViolationAlert: Bool = false
    @Published var isAppInactiveDuringExam: Bool = false
    
    private var assessmentSession: AEAssessmentSession?
    private var orientationObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    
    override init() {
        super.init()
        ExamLockdownState.installEdgeDeferralSupport()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Clears only local iPad clipboard items without triggering Universal Clipboard ("Paste from MacBook") prompts.
    func clearLocalClipboardSafely() {
        UIPasteboard.general.setItems([], options: [.localOnly: true])
    }
    
    /// Locks the iPad into Assessment Mode, restricts window resizing (Stage Manager / Mac-style windowing),
    /// defers system edge gestures (`.all`), monitors for app-exit tampering, and blocks notifications.
    func beginExamLockdown() {
        isExamLocked = true
        ExamLockdownState.isLocked = true
        tamperViolationCount = 0
        showTamperViolationAlert = false
        isAppInactiveDuringExam = false
        
        // 1. Clear local pasteboard only (prevents Universal Clipboard "Paste from MacBook Air" popup)
        clearLocalClipboardSafely()
        
        // 2. Suppress and clear notifications
        blockNotifications()
        
        // 3. Lock window size to full-screen & activate `.all` edge gesture deferral
        lockWindowToFullScreen()
        
        // 4. Start monitoring app lifecycle for unauthorized exit / multitasking attempts
        startTamperMonitoring()
        
        // 5. Request Autonomous Single App Mode (Guided Access) if supervised / configured
        UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] success in
            Task { @MainActor [weak self] in
                if success {
                    self?.isHardwareAssessmentActive = true
                }
            }
        }
        
        // 6. Start Apple's AutomaticAssessmentConfiguration session
        if assessmentSession?.isActive != true {
            let configuration = AEAssessmentConfiguration()
            let session = AEAssessmentSession(configuration: configuration)
            session.delegate = self
            self.assessmentSession = session
            session.begin()
        }
    }
    
    /// Releases the device from Assessment Mode, restores window resizability, stops tamper monitoring,
    /// and unblocks notifications once the exam has been submitted AND the user returns to the home screen.
    func endExamLockdown() {
        isExamLocked = false
        ExamLockdownState.isLocked = false
        isHardwareAssessmentActive = false
        isAppInactiveDuringExam = false
        showTamperViolationAlert = false
        
        // 1. Stop tamper / exit monitoring
        stopTamperMonitoring()
        
        // 2. End Assessment Session
        if let session = assessmentSession, session.isActive {
            session.end()
        }
        assessmentSession = nil
        
        // 3. Release Guided Access / Single App Mode if active
        UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in }
        
        // 4. Restore window resizability & normal edge gestures
        unlockWindowSize()
        
        // 5. Unblock notifications
        unblockNotifications()
    }
    
    func dismissTamperAlert() {
        showTamperViolationAlert = false
    }
    
    // MARK: - Tamper / Exit Detection (Verifies Lockdown During Development & Production)
    
    private func startTamperMonitoring() {
        stopTamperMonitoring()
        
        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willDeactivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                // Blur exam contents immediately when multitasking switcher or Control Center is pulled
                self.isAppInactiveDuringExam = true
            }
        }
        
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                self.isAppInactiveDuringExam = true
                self.tamperViolationCount += 1
                self.showTamperViolationAlert = true
            }
        }
        
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                if self.isAppInactiveDuringExam {
                    self.isAppInactiveDuringExam = false
                    // Re-enforce window size and edge gesture deferral upon returning
                    self.applyFullScreenWindowRestrictions()
                }
            }
        }
    }
    
    private func stopTamperMonitoring() {
        if let obs = willResignActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            willResignActiveObserver = nil
        }
        if let obs = didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
            didEnterBackgroundObserver = nil
        }
        if let obs = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            didBecomeActiveObserver = nil
        }
    }
    
    // MARK: - Window Locking & First-Swipe Edge Gesture Deferral
    
    private func lockWindowToFullScreen() {
        applyFullScreenWindowRestrictions()
        
        if orientationObserver == nil {
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self, self.isExamLocked else { return }
                    self.applyFullScreenWindowRestrictions()
                }
            }
        }
    }
    
    private func applyFullScreenWindowRestrictions() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let screenBounds = windowScene.screen.bounds.size
            // Force both minimum and maximum window size to match the full screen dimensions,
            // disabling corner drag-resizing and compact windowing in Stage Manager.
            windowScene.sizeRestrictions?.minimumSize = screenBounds
            windowScene.sizeRestrictions?.maximumSize = screenBounds
            
            for window in windowScene.windows {
                updateGestureDeferralRecursively(on: window.rootViewController)
            }
        }
    }
    
    private func unlockWindowSize() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 480)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10000, height: 10000)
            
            for window in windowScene.windows {
                updateGestureDeferralRecursively(on: window.rootViewController)
            }
        }
    }
    
    private func updateGestureDeferralRecursively(on viewController: UIViewController?) {
        guard let vc = viewController else { return }
        vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
        for child in vc.children {
            updateGestureDeferralRecursively(on: child)
        }
        if let presented = vc.presentedViewController {
            updateGestureDeferralRecursively(on: presented)
        }
    }
    
    // MARK: - Notification Blocking
    
    private func blockNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
    
    private func unblockNotifications() {
        UNUserNotificationCenter.current().delegate = self
    }
}

// MARK: - AEAssessmentSessionDelegate
extension AssessmentManager: AEAssessmentSessionDelegate {
    nonisolated func assessmentSessionDidBegin(_ session: AEAssessmentSession) {
        print("Successfully entered Assessment Mode.")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = true
        }
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, failedToBeginWithError error: Error) {
        print("Assessment Mode entitlement not active (using Edge Deferral + Tamper Lock fallback): \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = false
        }
    }
    
    nonisolated func assessmentSessionDidEnd(_ session: AEAssessmentSession) {
        print("Successfully exited Assessment Mode.")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = false
        }
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, wasInterruptedWithError error: Error) {
        print("Assessment Mode was interrupted: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isExamLocked {
                self.assessmentSession?.begin()
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AssessmentManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor [weak self] in
            let isLocked = self?.isExamLocked ?? false
            if isLocked {
                completionHandler([])
            } else {
                completionHandler([.banner, .list, .sound, .badge])
            }
        }
    }
}
