//
//  EraserSettingsMenuView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct EraserSettingsMenuView: View {
    @ObservedObject var viewModel: ExamFlowViewModel
    
    var body: some View {
        VStack(spacing: 14) {
            // Mode Selection (Exact/Pixel vs Connected/Whole Stroke)
            VStack(alignment: .leading, spacing: 6) {
                Text("Eraser Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Eraser Mode", selection: Binding(
                    get: { viewModel.selectedEraserMode },
                    set: { viewModel.selectEraser(mode: $0) }
                )) {
                    Text("Exact (Pixel)").tag(EraserMode.exact)
                    Text("Connected").tag(EraserMode.connected)
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            // Shared Width Slider Section
            VStack(spacing: 8) {
                HStack {
                    Text("Size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    // Live size preview circle
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
                            .background(Circle().fill(Color.secondary.opacity(0.25)))
                            .frame(
                                width: max(5, min(20, viewModel.selectedPenWidth * 1.6)),
                                height: max(5, min(20, viewModel.selectedPenWidth * 1.6))
                            )
                    }
                    .frame(width: 22, height: 22)
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
                    .tint(.blue)
                    
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: 235)
    }
}

#Preview {
    EraserSettingsMenuView(viewModel: ExamFlowViewModel())
}
