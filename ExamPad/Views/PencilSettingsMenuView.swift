//
//  PencilSettingsMenuView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct PencilSettingsMenuView: View {
    @ObservedObject var viewModel: ExamFlowViewModel
    
    // Colors: black and blue
    let penColors: [UIColor] = [
        .black,
        .systemBlue
    ]
    
    var body: some View {
        VStack(spacing: 14) {
            // Color Selection Row
            HStack(spacing: 20) {
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
            
            // Notability-style Width Slider Section
            VStack(spacing: 8) {
                HStack {
                    Text("Thickness")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    // Live thickness preview dot
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: viewModel.selectedPenColor))
                            .frame(
                                width: max(3, min(18, viewModel.selectedPenWidth * 1.5)),
                                height: max(3, min(18, viewModel.selectedPenWidth * 1.5))
                            )
                    }
                    .frame(width: 20, height: 20)
                }
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 4, height: 4)
                    
                    Slider(
                        value: Binding(
                            get: { viewModel.selectedPenWidth },
                            set: { viewModel.updateStrokeWidth($0) }
                        ),
                        in: 1.0...12.0,
                        step: 0.25
                    )
                    .tint(Color(uiColor: viewModel.selectedPenColor == .black ? .systemBlue : viewModel.selectedPenColor))
                    
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: 215)
    }
}

#Preview {
    PencilSettingsMenuView(viewModel: ExamFlowViewModel())
}
