//
//  ExamPageThumbnailView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ExamPageThumbnailView: View {
    let pageIndex: Int
    let isCurrentPage: Bool
    var drawing: PKDrawing = PKDrawing()
    var drawingVersion: Int = 0
    var pageWidth: CGFloat = 800
    var pageHeight: CGFloat = 1131
    var thumbnailWidth: CGFloat = 140
    var thumbnailHeight: CGFloat = 198
    let onSelect: () -> Void
    
    private var pageDrawingImage: UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let pageRect = CGRect(x: 0, y: 0, width: max(pageWidth, 1), height: max(pageHeight, 1))
        
        // Force light mode trait collection so black ink is rendered black (not inverted to white)
        // Use scale: 1.0 for high resolution, crisp, razor-sharp pen rendering
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: pageRect, scale: 1.0)
        }
        return image
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                let safeWidth = max(pageWidth, 1)
                let safeHeight = max(pageHeight, 1)
                
                ZStack {
                    // Base Page Content scaled down to show the true full page
                    if pageIndex == 0 {
                        QuestionnairePageView()
                            .frame(width: safeWidth, height: safeHeight)
                            .scaleEffect(thumbnailWidth / safeWidth)
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                            .clipped()
                    } else {
                        // Accurately match the exact grid dimensions and square count of the actual page
                        let scaledStep = 25.0 * (thumbnailWidth / safeWidth)
                        MathGridView(
                            step: scaledStep,
                            lineWidth: 0.4,
                            lineColor: Color.black.opacity(0.35)
                        )
                        .frame(width: thumbnailWidth, height: thumbnailHeight)
                        .clipped()
                    }
                    
                    // User's PencilKit drawings on this page (high resolution, accurate ink colors)
                    if let drawingImage = pageDrawingImage {
                        Image(uiImage: drawingImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: thumbnailWidth, height: thumbnailHeight)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: thumbnailWidth, height: thumbnailHeight)
                .background(Color.white)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                // Border frame around preview (no tint overlay on top of the preview)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrentPage ? Color.blue : Color.clear, lineWidth: 2)
                )
                
                // Page number turns blue when on the current page
                Text("\(pageIndex + 1)")
                    .font(.caption)
                    .fontWeight(isCurrentPage ? .semibold : .regular)
                    .foregroundColor(isCurrentPage ? .blue : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 24) {
        ExamPageThumbnailView(
            pageIndex: 0,
            isCurrentPage: true,
            onSelect: {}
        )
        
        ExamPageThumbnailView(
            pageIndex: 1,
            isCurrentPage: false,
            onSelect: {}
        )
    }
    .padding(20)
    .background(Color(UIColor.secondarySystemBackground))
}
