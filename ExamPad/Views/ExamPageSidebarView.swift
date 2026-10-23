//
//  ExamPageSidebarView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ExamPageSidebarView: View {
    let pageCount: Int
    let currentPageIndex: Int
    var getDrawing: (Int) -> PKDrawing = { _ in PKDrawing() }
    var drawingVersion: Int = 0
    var pageWidth: CGFloat = 800
    var pageHeight: CGFloat = 1131
    let onSelectPage: (Int) -> Void
    var onSubmit: () -> Void = {}
    let onToggleFormulaPage: () -> Void
    let onAddPage: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Action Buttons at the top of the column
            VStack(spacing: 8) {
                // Submit Button (Red-tinted, matching Add Page shape & size)
                Button(action: {
                    onSubmit()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text("Submit Exam")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 10)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                
                // Toggle Formula Page Button
                Button(action: {
                    onToggleFormulaPage()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "function")
                        Text("Toggle Formula Page")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 10)
                    .background(Color(UIColor.tertiarySystemFill))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                
                // Add Page Button (Green-tinted)
                Button(action: {
                    onAddPage()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Page")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 10)
                    .background(Color.examButton.opacity(0.15))
                    .foregroundColor(.examButton)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
            
            // Scrollable list of current pages in the sheet
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 18) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        ExamPageThumbnailView(
                            pageIndex: index,
                            isCurrentPage: index == currentPageIndex,
                            drawing: getDrawing(index),
                            drawingVersion: drawingVersion,
                            pageWidth: pageWidth,
                            pageHeight: pageHeight,
                            onSelect: {
                                onSelectPage(index)
                            }
                        )
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 210)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }
}

#Preview {
    ExamPageSidebarView(
        pageCount: 3,
        currentPageIndex: 1,
        getDrawing: { _ in PKDrawing() },
        onSelectPage: { _ in },
        onSubmit: {},
        onToggleFormulaPage: {},
        onAddPage: {}
    )
}
