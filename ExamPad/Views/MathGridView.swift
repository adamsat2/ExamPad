//
//  MathGridView.swift
//  ExamPad
//

import SwiftUI

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

#Preview {
    MathGridView()
        .frame(width: 400, height: 600)
}
