//
//  ExamFlowViewModel.swift
//  ExamPad
//

import SwiftUI
import PencilKit
import Combine

enum AppFlowState {
    case start
    case scanningQR
    case waitingForExam(ExamSessionModel)
    case activeExam
}

@MainActor
final class ExamFlowViewModel: ObservableObject {
    @Published var currentState: AppFlowState = .start
    
    // Exam State
    @Published var gridPageCount: Int = 1
    @Published var showSubmitConfirmation: Bool = false
    @Published var submissionSuccess: Bool = false
    
    // PencilKit Tool State
    @Published var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    // Simulates the QR scan bypass for current development stage
    // When QR is integrated, this will decode the payload and transition to .waitingForExam
    func mockScanAndStart() {
        // Bypass directly to the exam 
        currentState = .activeExam
    }
    
    func addGridPage() {
        gridPageCount += 1
    }
    
    func selectTool(color: UIColor?, isEraser: Bool = false, isLasso: Bool = false) {
        if isEraser {
            currentTool = PKEraserTool(.bitmap)
        } else if isLasso {
            currentTool = PKLassoTool()
        } else if let color = color {
            currentTool = PKInkingTool(.pen, color: color, width: 2.0)
        }
    }
    
    func submitExam(assessmentManager: AssessmentManager) {
        // TODO: Integrate multipart form data upload to Supervisor App / Backend
        
        submissionSuccess = true
        showSubmitConfirmation = false
        
        // Simulating the delay of network upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.resetToStart(assessmentManager: assessmentManager)
        }
    }
    
    private func resetToStart(assessmentManager: AssessmentManager) {
        assessmentManager.endExamLockdown()
        submissionSuccess = false
        gridPageCount = 1
        currentState = .start
    }
}

