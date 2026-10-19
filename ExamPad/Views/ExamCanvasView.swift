//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ExamCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var currentTool: PKTool
    var onDrawingChanged: ((PKDrawing) -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ExamCanvasView
        
        init(_ parent: ExamCanvasView) {
            self.parent = parent
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?(canvasView.drawing)
        }
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        // Only Apple Pencil is recognized for drawing tools (pencil, lasso, eraser)
        // Finger touches are ignored by drawing recognizer so user can scroll naturally
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        
        // PKCanvasView is a UIScrollView under the hood. When it receives a touch,
        // iOS automatically tries to apply Safe Area insets, causing the content to shift
        // Setting this to .never locks the canvas rigidly in place
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.bounces = false
        
        // Forces black ink to stay black even if the device is in dark mode
        canvasView.overrideUserInterfaceStyle = .light
        
        canvasView.tool = currentTool
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        uiView.tool = currentTool
        uiView.drawingPolicy = .pencilOnly
    }
}

#Preview {
    @Previewable @State var canvasView = PKCanvasView()
    @Previewable @State var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.0)
    
    ExamCanvasView(canvasView: $canvasView, currentTool: $currentTool)
}
