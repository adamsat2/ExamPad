//
//  ExamFlowViewModel.swift
//  ExamPad
//

import SwiftUI
import PencilKit
import Combine

enum AppFlowState: Equatable {
    case start
    case scanningQR
    case waitingForExam(ExamSessionModel)
    case activeExam
    
    static func == (lhs: AppFlowState, rhs: AppFlowState) -> Bool {
        switch (lhs, rhs) {
        case (.start, .start): return true
        case (.scanningQR, .scanningQR): return true
        case (.activeExam, .activeExam): return true
        case let (.waitingForExam(a), .waitingForExam(b)): return a.id == b.id
        default: return false
        }
    }
}

@MainActor
final class ExamFlowViewModel: ObservableObject {
    @Published var currentState: AppFlowState = .start
    
    // Exam State
    @Published var gridPageCount: Int = 1
    @Published var showSubmitConfirmation: Bool = false
    @Published var submissionSuccess: Bool = false
    @Published var pageDrawings: [Int: PKDrawing] = [:]
    @Published var drawingRevision: Int = 0
    
    // PencilKit Tool State
    @Published var selectedPenColor: UIColor = .black
    @Published var selectedPenWidth: CGFloat = 2.0
    @Published var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    // Undo / Redo State
    let undoManager = UndoManager()
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    func updateUndoRedoState() {
        let newCanUndo = undoManager.canUndo
        let newCanRedo = undoManager.canRedo
        if canUndo != newCanUndo {
            canUndo = newCanUndo
        }
        if canRedo != newCanRedo {
            canRedo = newCanRedo
        }
    }
    
    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        updateUndoRedoState()
        drawingRevision += 1
    }
    
    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        updateUndoRedoState()
        drawingRevision += 1
    }
    
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
    
    func drawing(for pageIndex: Int) -> PKDrawing {
        pageDrawings[pageIndex] ?? PKDrawing()
    }
    
    func setDrawing(_ drawing: PKDrawing, for pageIndex: Int) {
        if let existing = pageDrawings[pageIndex] {
            if existing.strokes.isEmpty && drawing.strokes.isEmpty {
                return
            }
            if existing == drawing {
                return
            }
        } else if drawing.strokes.isEmpty {
            return
        }
        pageDrawings[pageIndex] = drawing
        drawingRevision += 1
        updateUndoRedoState()
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
        pageDrawings.removeAll()
        undoManager.removeAllActions()
        updateUndoRedoState()
        drawingRevision = 0
        selectedPenColor = .black
        selectedPenWidth = 2.0
        currentTool = PKInkingTool(.pen, color: .black, width: 2.0)
        currentState = .start
    }
}
