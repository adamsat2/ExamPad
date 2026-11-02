//
//  LassoSettingsMenuView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct LassoSettingsMenuView: View {
    @ObservedObject var viewModel: ExamFlowViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lasso Shape")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(LassoMode.allCases) { mode in
                    let isSelected = viewModel.selectedLassoMode == mode
                    Button(action: {
                        viewModel.selectLasso(mode: mode)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: mode == .free ? "lasso" : "rectangle.dashed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isSelected ? .blue : .primary)
                                .frame(width: 22)
                            
                            Text(mode.rawValue)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundColor(isSelected ? .blue : .primary)
                            
                            Spacer()
                            
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.blue.opacity(0.12) : Color(UIColor.tertiarySystemFill))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(viewModel.selectedLassoMode == .square
                 ? "Draw a box to select strokes. Drag corners or pinch to resize."
                 : "Draw a freehand loop to select strokes. Pinch with two fingers to resize.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: 230)
    }
}

#Preview {
    LassoSettingsMenuView(viewModel: ExamFlowViewModel())
}
