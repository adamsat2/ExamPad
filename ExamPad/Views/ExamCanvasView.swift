//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ExamCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var currentTool: PKTool
    
    func makeUIView(context: Context) -> PKCanvasView {
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
        uiView.tool = currentTool
    }
}

struct MathGridView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 25.0
            var path = Path()
            
            // Vertical lines
            for x in stride(from: 0, through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            
            // Horizontal lines
            for y in stride(from: 0, through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            
            // Draw the grid lines in black
            context.stroke(path, with: .color(.black), lineWidth: 0.5)
        }
        // Expand to fill the allocated frame
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
