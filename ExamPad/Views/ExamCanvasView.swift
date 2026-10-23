//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

/// Subclass of PKCanvasView that strictly locks internal scroll offsets and insets to zero.
/// This prevents PencilKit's live rendering layer and Apple Pencil hover/inking tracking
/// from shifting downwards when nested inside a scrolled container.
final class FixedCanvasView: PKCanvasView {
    override var contentOffset: CGPoint {
        get { .zero }
        set { super.contentOffset = .zero }
    }
    
    override var contentInset: UIEdgeInsets {
        get { .zero }
        set { super.contentInset = .zero }
    }
    
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(.zero, animated: false)
    }
    
    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        // Prevent internal scrolling when touches or hover occurs
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if super.contentOffset != .zero {
            super.contentOffset = .zero
        }
        if contentSize != bounds.size && bounds.size != .zero {
            contentSize = bounds.size
        }
    }
}

struct ExamCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var currentTool: PKTool
    var onDrawingChanged: (() -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ExamCanvasView
        var isUsingTool = false
        var isUpdatingFromSwiftUI = false
        
        init(_ parent: ExamCanvasView) {
            self.parent = parent
        }
        
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
        }
        
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            DispatchQueue.main.async {
                self.parent.drawing = canvasView.drawing
                self.parent.onDrawingChanged?()
            }
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isUpdatingFromSwiftUI else { return }
            if !isUsingTool {
                DispatchQueue.main.async {
                    self.parent.drawing = canvasView.drawing
                    self.parent.onDrawingChanged?()
                }
            }
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
        canvasView.delegate = context.coordinator
        // Only Apple Pencil is recognized for drawing tools (pencil, lasso, eraser)
        // Finger touches are ignored by drawing recognizer so user can scroll naturally
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        
        // Disable automatic content insets to prevent shifts relative to safe area
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.contentInset = .zero
        canvasView.bounces = false
        
        // Forces black ink to stay black even if the device is in dark mode
        canvasView.overrideUserInterfaceStyle = .light
        
        canvasView.drawing = drawing
        canvasView.tool = currentTool
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        
        if uiView.drawing != drawing && !context.coordinator.isUsingTool {
            context.coordinator.isUpdatingFromSwiftUI = true
            uiView.drawing = drawing
            context.coordinator.isUpdatingFromSwiftUI = false
        }
        
        // Only update tool if changed to prevent resetting active tool state mid-stroke
        if !context.coordinator.isSameTool(uiView.tool, currentTool) {
            uiView.tool = currentTool
        }
        if uiView.drawingPolicy != .pencilOnly {
            uiView.drawingPolicy = .pencilOnly
        }
        if uiView.contentSize != uiView.bounds.size && uiView.bounds.size != .zero {
            uiView.contentSize = uiView.bounds.size
        }
    }
}

#Preview {
    @Previewable @State var drawing = PKDrawing()
    @Previewable @State var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    ExamCanvasView(drawing: $drawing, currentTool: $currentTool)
}
