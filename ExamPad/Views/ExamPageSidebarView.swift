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
    let onToggleFormulaPage: () -> Void
    let onAddPage: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Action Buttons at the top of the column
            VStack(spacing: 10) {
                Button(action: onToggleFormulaPage) {
                    HStack(spacing: 6) {
                        Image(systemName: "function")
                        Text("Toggle Formula Page")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .background(Color(UIColor.tertiarySystemFill))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                
                Button(action: onAddPage) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Page")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
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
                            thumbnailWidth: 140,
                            thumbnailHeight: 198,
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
        onToggleFormulaPage: {},
        onAddPage: {}
    )
}
