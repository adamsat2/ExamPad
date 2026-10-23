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
    @Published var currentDrawing: PKDrawing = PKDrawing()
    @Published var drawingRevision: Int = 0
    
    // PencilKit Tool State
    @Published var selectedPenColor: UIColor = .black
    @Published var selectedPenWidth: CGFloat = 2.0
    @Published var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    var isPenActive: Bool {
        currentTool is PKInkingTool
    }
    
    var isEraserActive: Bool {
        currentTool is PKEraserTool
    }
    
    var isLassoActive: Bool {
        currentTool is PKLassoTool
    }
    
    // Simulates the QR scan bypass for current development stage
    // When QR is integrated, this will decode the payload and transition to .waitingForExam
    func mockScanAndStart() {
        // Bypass directly to the exam 
        currentState = .activeExam
    }
    
    func addGridPage() {
        gridPageCount += 1
    }
    
    func selectPen(color: UIColor? = nil, width: CGFloat? = nil) {
        if let color = color {
            selectedPenColor = color
        }
        if let width = width {
            selectedPenWidth = width
        }
        currentTool = PKInkingTool(.pen, color: selectedPenColor, width: selectedPenWidth)
    }
    
    func selectEraser() {
        currentTool = PKEraserTool(.bitmap)
    }
    
    func selectLasso() {
        currentTool = PKLassoTool()
    }
    
    func selectTool(color: UIColor?, isEraser: Bool = false, isLasso: Bool = false) {
        if isEraser {
            selectEraser()
        } else if isLasso {
            selectLasso()
        } else if let color = color {
            selectPen(color: color)
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
        currentDrawing = PKDrawing()
        drawingRevision = 0
        selectedPenColor = .black
        selectedPenWidth = 2.0
        currentTool = PKInkingTool(.pen, color: .black, width: 2.0)
        currentState = .start
    }
}
