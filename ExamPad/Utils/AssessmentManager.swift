//
//  AssessmentManager.swift
//  ExamPad
//

import Foundation
import Combine
import AutomaticAssessmentConfiguration
import UIKit
import UserNotifications

@MainActor
final class AssessmentManager: NSObject, ObservableObject {
    @Published private(set) var isExamActive: Bool = false
    @Published private(set) var isGuidedAccessEnabled: Bool = UIAccessibility.isGuidedAccessEnabled
    
    static let defaultMinimumWindowSize = CGSize(width: 600, height: 500)
    
    /// Optional callback triggered when Guided Access is turned off during an active exam.
    var onGuidedAccessTurnedOffDuringExam: (() -> Void)?
    
    private var assessmentSession: AEAssessmentSession?
    private var guidedAccessObserver: NSObjectProtocol?
    private var sceneDidActivateObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var guidedAccessPollingTimer: Timer?
    
    private var didReportGuidedAccessOffForCurrentInterruption: Bool = false
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupGuidedAccessStatusObserver()
    }
    
    /// Returns `"Home button"` on iPads with a physical Home button, or `"Top button"` on all-screen iPads.
    var guidedAccessHardwareButtonName: String {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow || !window.isHidden {
                // All-screen iPads (Face ID / Top-button Touch ID) have a bottom safe area inset (> 0)
                // for the Home indicator bar. iPads with a physical Home button have 0 bottom safe area inset.
                return window.safeAreaInsets.bottom > 0 ? "Top button" : "Home button"
            }
        }
        return "Home button"
    }
    
    func refreshGuidedAccessStatus() {
        let currentlyEnabled = UIAccessibility.isGuidedAccessEnabled
        if isGuidedAccessEnabled != currentlyEnabled {
            isGuidedAccessEnabled = currentlyEnabled
        }
    }
    
    func openSettingsApp() {
        let settingsCandidates = [
            "App-Prefs:root=ACCESSIBILITY&path=GUIDED_ACCESS_TITLE",
            "App-Prefs:root=ACCESSIBILITY",
            UIApplication.openSettingsURLString
        ]
        for candidate in settingsCandidates {
            if let url = URL(string: candidate), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
    
    func clearLocalClipboardSafely() {
        UIPasteboard.general.setItems([], options: [.localOnly: true])
    }
    
    func beginExamSession() {
        isExamActive = true
        refreshGuidedAccessStatus()
        didReportGuidedAccessOffForCurrentInterruption = false
        
        clearLocalClipboardSafely()
        blockNotifications()
        startExamGuidedAccessMonitoring()
        
        if !isGuidedAccessEnabled {
            didReportGuidedAccessOffForCurrentInterruption = true
            handleGuidedAccessTurnedOffDuringExam()
        }
    }
    
    func endExamSession() {
        isExamActive = false
        onGuidedAccessTurnedOffDuringExam = nil
        stopExamGuidedAccessMonitoring()
        
        if let session = assessmentSession, session.isActive {
            session.end()
        }
        assessmentSession = nil
        
        unblockNotifications()
    }
    
    // MARK: - Exam Guided Access Event Handler
    
    /// Called during an active exam when Guided Access is turned off.
    private func handleGuidedAccessTurnedOffDuringExam() {
        print("Guided Access was turned off during the active exam.")
        onGuidedAccessTurnedOffDuringExam?()
    }
    
    // MARK: - Guided Access Monitoring
    
    private func setupGuidedAccessStatusObserver() {
        guidedAccessObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateGuidedAccessStateChange()
            }
        }
    }
    
    private func startExamGuidedAccessMonitoring() {
        stopExamGuidedAccessMonitoring()
        
        sceneDidActivateObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidActivateDuringExam()
            }
        }
        
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAppDidActivateDuringExam()
            }
        }
        
        guidedAccessPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateGuidedAccessStateChange()
            }
        }
    }
    
    private func stopExamGuidedAccessMonitoring() {
        for observer in [sceneDidActivateObserver, appDidBecomeActiveObserver] {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
        }
        sceneDidActivateObserver = nil
        appDidBecomeActiveObserver = nil
        
        guidedAccessPollingTimer?.invalidate()
        guidedAccessPollingTimer = nil
    }
    
    private func handleAppDidActivateDuringExam() {
        guard isExamActive else { return }
        evaluateGuidedAccessStateChange()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.isExamActive else { return }
            self.evaluateGuidedAccessStateChange()
            if self.isGuidedAccessEnabled {
                self.didReportGuidedAccessOffForCurrentInterruption = false
            }
        }
    }
    
    private func evaluateGuidedAccessStateChange() {
        let currentlyEnabled = UIAccessibility.isGuidedAccessEnabled
        if isGuidedAccessEnabled != currentlyEnabled {
            isGuidedAccessEnabled = currentlyEnabled
        }
        
        guard isExamActive else { return }
        
        if currentlyEnabled {
            if UIApplication.shared.applicationState == .active {
                didReportGuidedAccessOffForCurrentInterruption = false
            }
        } else {
            if !didReportGuidedAccessOffForCurrentInterruption {
                didReportGuidedAccessOffForCurrentInterruption = true
                handleGuidedAccessTurnedOffDuringExam()
            }
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
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, failedToBeginWithError error: Error) {
        print("Failed to begin Assessment Mode: \(error.localizedDescription)")
    }
    
    nonisolated func assessmentSessionDidEnd(_ session: AEAssessmentSession) {
        print("Successfully exited Assessment Mode.")
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, wasInterruptedWithError error: Error) {
        print("Assessment Mode was interrupted: \(error.localizedDescription)")
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
            let isExamActive = self?.isExamActive ?? false
            if isExamActive {
                completionHandler([])
            } else {
                completionHandler([.banner, .list, .sound, .badge])
            }
        }
    }
}
