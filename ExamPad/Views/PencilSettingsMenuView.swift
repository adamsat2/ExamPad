//
//  PencilSettingsMenuView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct PencilSettingsMenuView: View {
    @ObservedObject var viewModel: ExamFlowViewModel
    
    // 3 pre-determined widths: small (readable), medium (default), and thick
    let penWidths: [(width: CGFloat, dotSize: CGFloat)] = [
        (1.2, 4.0),
        (2.0, 7.5),
        (3.5, 12.0)
    ]
    
    // Colors: black and blue
    let penColors: [UIColor] = [
        .black,
        .systemBlue
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Color Selection Row
            HStack(spacing: 16) {
                ForEach(penColors, id: \.self) { color in
                    let isSelected = viewModel.selectedPenColor == color
                    Button(action: {
                        viewModel.selectPen(color: color)
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(uiColor: color))
                                .frame(width: 26, height: 26)
                            
                            if isSelected {
                                Circle()
                                    .stroke(Color.primary.opacity(0.85), lineWidth: 2)
                                    .frame(width: 34, height: 34)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color == .black ? "Black Color" : "Blue Color")
                }
            }
            
            Divider()
            
            // Width Selection Row
            HStack(spacing: 16) {
                ForEach(penWidths, id: \.width) { item in
                    let isSelected = abs(viewModel.selectedPenWidth - item.width) < 0.1
                    Button(action: {
                        viewModel.selectPen(width: item.width)
                    }) {
                        ZStack {
                            if isSelected {
                                Circle()
                                    .stroke(Color.primary.opacity(0.85), lineWidth: 2)
                                    .frame(width: 34, height: 34)
                            }
                            
                            Circle()
                                .fill(Color(uiColor: viewModel.selectedPenColor))
                                .frame(width: item.dotSize, height: item.dotSize)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pen width \(item.width)")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: 150)
    }
}

#Preview {
    PencilSettingsMenuView(viewModel: ExamFlowViewModel())
}
