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

enum EraserMode: String, CaseIterable, Identifiable {
    case exact = "Pixel"
    case connected = "Whole Stroke"
    
    var id: String { rawValue }
    
    var pkEraserType: PKEraserTool.EraserType {
        switch self {
        case .exact:
            return .fixedWidthBitmap
        case .connected:
            return .vector
        }
    }
}

enum LassoMode: String, CaseIterable, Identifiable {
    case free = "Free Lasso"
    case square = "Square Lasso"
    
    var id: String { rawValue }
}

@MainActor
final class ExamFlowViewModel: ObservableObject {
    @Published var currentState: AppFlowState = .start
    
    // Exam State
    @Published var examTitle: String = "Test Exam 2026 X"
    @Published var gridPageCount: Int = 1
    @Published var showSubmitConfirmation: Bool = false
    @Published var submissionSuccess: Bool = false
    @Published var pageDrawings: [Int: PKDrawing] = [:]
    @Published var drawingRevision: Int = 0
    
    // PencilKit Tool State
    @Published var selectedPenColor: UIColor = .black
    @Published var selectedPenWidth: CGFloat = 2.5
    @Published var selectedEraserMode: EraserMode = .exact
    @Published var selectedLassoMode: LassoMode = .free
    @Published var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.5)
    
    // Undo / Redo State
    let undoManager = UndoManager()
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    private var submitResetWorkItem: DispatchWorkItem?
    
    /// Maps the shared stroke width slider (`1.0...12.0`) to a balanced eraser width (`16.4...64.0`).
    var effectiveEraserWidth: CGFloat {
        let clamped = min(max(selectedPenWidth, 1.0), 12.0)
        let normalized = (clamped - 1.0) / 11.0
        return 16.4 + normalized * 47.6
    }
    
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
    func mockScanAndStart(assessmentManager: AssessmentManager? = nil) {
        // Cancel any lingering submission timer and ensure a clean exam state
        submitResetWorkItem?.cancel()
        submitResetWorkItem = nil
        submissionSuccess = false
        showSubmitConfirmation = false
        assessmentManager?.beginExamLockdown()
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
    
    func updateStrokeWidth(_ width: CGFloat) {
        selectedPenWidth = width
        if isPenActive {
            currentTool = PKInkingTool(.pen, color: selectedPenColor, width: selectedPenWidth)
        } else if isEraserActive {
            currentTool = PKEraserTool(selectedEraserMode.pkEraserType, width: effectiveEraserWidth)
        }
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
    
    func selectEraser(mode: EraserMode? = nil, width: CGFloat? = nil) {
        if let mode = mode {
            selectedEraserMode = mode
        }
        if let width = width {
            selectedPenWidth = width
        }
        currentTool = PKEraserTool(selectedEraserMode.pkEraserType, width: effectiveEraserWidth)
    }
    
    func selectLasso(mode: LassoMode? = nil) {
        if let mode = mode {
            selectedLassoMode = mode
        }
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
        submitResetWorkItem?.cancel()
        
        submissionSuccess = true
        showSubmitConfirmation = false
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishSubmissionAndReturnHome(assessmentManager: assessmentManager)
        }
        submitResetWorkItem = workItem
        
        // Simulating the delay of network upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    func finishSubmissionAndReturnHome(assessmentManager: AssessmentManager) {
        submitResetWorkItem?.cancel()
        submitResetWorkItem = nil
        resetToStart(assessmentManager: assessmentManager)
    }
    
    private func resetToStart(assessmentManager: AssessmentManager) {
        assessmentManager.endExamLockdown()
        submissionSuccess = false
        showSubmitConfirmation = false
        gridPageCount = 1
        pageDrawings.removeAll()
        undoManager.removeAllActions()
        updateUndoRedoState()
        drawingRevision = 0
        selectedPenColor = .black
        selectedPenWidth = 2.5
        selectedEraserMode = .exact
        selectedLassoMode = .free
        currentTool = PKInkingTool(.pen, color: .black, width: 2.5)
        currentState = .start
    }
}
