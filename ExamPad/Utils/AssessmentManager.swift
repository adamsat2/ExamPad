//
//  AssessmentManager.swift
//  ExamPad
//


import Foundation
import Combine
import AutomaticAssessmentConfiguration
import UIKit

// Manages device locking and environment restrictions during an exam
@MainActor
final class AssessmentManager: NSObject, ObservableObject, AEAssessmentSessionDelegate {
    private var assessmentSession: AEAssessmentSession?
    
    func clearClipboard() {
        UIPasteboard.general.items.removeAll()
    }
    
    // Locks the iPad into Assessment Mode (Single App Mode)
    func beginExamLockdown() {
        let configuration = AEAssessmentConfiguration()
        
        let session = AEAssessmentSession(configuration: configuration)
        session.delegate = self
        self.assessmentSession = session
        
        session.begin()
    }
    
    // Releases the device from Assessment Mode
    func endExamLockdown() {
        assessmentSession?.end()
    }
    
    // Using nonisolated because these delegate callbacks might return on a background thread,
    // and this class is marked with @MainActor
    nonisolated func assessmentSessionDidBegin(_ session: AEAssessmentSession) {
        print("Successfully entered Assessment Mode.")
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, failedToBeginWithError error: Error) {
        print("Failed to enter Assessment Mode: \(error.localizedDescription)")
        // TODO: Handle failure UI state if the device fails to lock
    }
    
    nonisolated func assessmentSessionDidEnd(_ session: AEAssessmentSession) {
        print("Successfully exited Assessment Mode.")
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, wasInterruptedWithError error: Error) {
        print("Assessment Mode was interrupted: \(error.localizedDescription)")
    }
}
