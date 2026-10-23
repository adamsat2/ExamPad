//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

/// Subclass of PKCanvasView that routes undo/redo actions to a shared document UndoManager.
final class FixedCanvasView: PKCanvasView {
    weak var customUndoManager: UndoManager?
    
    override var undoManager: UndoManager? {
        return customUndoManager ?? super.undoManager
    }
}

struct ExamCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var currentTool: PKTool
    var undoManager: UndoManager? = nil
    var onDrawingChanged: (() -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ExamCanvasView
        var isUsingTool = false
        var isUpdatingFromSwiftUI = false
        var lastCanvasDrawing: PKDrawing?
        
        init(_ parent: ExamCanvasView) {
            self.parent = parent
        }
        
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
        }
        
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            commitDrawing(canvasView)
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Guard against recursive events triggered by makeUIView / updateUIView
            guard !isUpdatingFromSwiftUI else { return }
            // If the user is drawing, we commit when the stroke ends (pen lifts)
            if !isUsingTool {
                commitDrawing(canvasView)
            }
        }
        
        private func commitDrawing(_ canvasView: PKCanvasView) {
            let newDrawing = canvasView.drawing
            lastCanvasDrawing = newDrawing
            
            // Asynchronously dispatch binding update so SwiftUI view hierarchy is never mutated
            // mid-event or mid-layout pass
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.areDrawingsEqual(self.parent.drawing, newDrawing) {
                    self.parent.drawing = newDrawing
                }
                self.parent.onDrawingChanged?()
            }
        }
        
        func areDrawingsEqual(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
            if a.strokes.isEmpty && b.strokes.isEmpty {
                return true
            }
            return a == b
        }
        
        func isSameTool(_ toolA: PKTool, _ toolB: PKTool) -> Bool {
            if let inkingA = toolA as? PKInkingTool, let inkingB = toolB as? PKInkingTool {
                return inkingA.inkType == inkingB.inkType &&
                       inkingA.color == inkingB.color &&
                       inkingA.width == inkingB.width
            }
            if let eraserA = toolA as? PKEraserTool, let eraserB = toolB as? PKEraserTool {
                return eraserA.eraserType == eraserB.eraserType
            }
            if toolA is PKLassoTool && toolB is PKLassoTool {
                return true
            }
            return false
        }
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = FixedCanvasView()
        canvasView.customUndoManager = undoManager
        
        // Populate drawing before attaching delegate to avoid spurious change events during construction
        canvasView.drawing = drawing
        context.coordinator.lastCanvasDrawing = drawing
        
        canvasView.delegate = context.coordinator
        // Only Apple Pencil is recognized for drawing tools (pencil, lasso, eraser)
        // Finger touches are ignored by drawing recognizer so user can scroll naturally
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        
        // Disable automatic content insets
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.bounces = false
        
        // Forces black ink to stay black even if the device is in dark mode
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = currentTool
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        
        if let fixedCanvas = uiView as? FixedCanvasView {
            fixedCanvas.customUndoManager = undoManager
        }
        
        // Only reload uiView.drawing if an external action modified `drawing` (e.g. Undo, Redo, or reset exam).
        // NEVER reload uiView.drawing if the difference is due to the canvas having drawn new content
        // that SwiftUI's async update hasn't settled yet.
        if !context.coordinator.isUsingTool {
            if let last = context.coordinator.lastCanvasDrawing {
                // If `drawing` is genuinely different from what the canvas produced and what's on the canvas:
                if !context.coordinator.areDrawingsEqual(drawing, last) &&
                   !context.coordinator.areDrawingsEqual(uiView.drawing, drawing) {
                    context.coordinator.isUpdatingFromSwiftUI = true
                    uiView.drawing = drawing
                    context.coordinator.lastCanvasDrawing = drawing
                    context.coordinator.isUpdatingFromSwiftUI = false
                }
            } else if !context.coordinator.areDrawingsEqual(uiView.drawing, drawing) {
                context.coordinator.isUpdatingFromSwiftUI = true
                uiView.drawing = drawing
                context.coordinator.lastCanvasDrawing = drawing
                context.coordinator.isUpdatingFromSwiftUI = false
            }
        }
        
        // Only update tool if changed to prevent resetting active tool state mid-stroke
        if !context.coordinator.isSameTool(uiView.tool, currentTool) {
            uiView.tool = currentTool
        }
        if uiView.drawingPolicy != .pencilOnly {
            uiView.drawingPolicy = .pencilOnly
        }
    }
}

#Preview {
    @Previewable @State var drawing = PKDrawing()
    @Previewable @State var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    ExamCanvasView(drawing: $drawing, currentTool: $currentTool)
}
