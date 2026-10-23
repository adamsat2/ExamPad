//
//  ActiveExamView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ActiveExamView: View {
    @EnvironmentObject var viewModel: ExamFlowViewModel
    @EnvironmentObject var assessmentManager: AssessmentManager
    
    @State private var canvasView = PKCanvasView()
    @State private var isPageSidebarPresented: Bool = false
    @State private var isPencilMenuPresented: Bool = false
    @State private var currentPageIndex: Int = 0
    
    private let pageSpacing: CGFloat = 24
    private let sidebarWidth: CGFloat = 210
    
    var body: some View {
        VStack(spacing: 0) {
            // Persistent Top Menu
            HStack(spacing: 24) {
                // Single Pencil Tool with Color & Width Mini Menu
                VStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            viewModel.isPenActive ?
                            AnyShapeStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(red: 1.0, green: 0.82, blue: 0.1), location: 0.0),
                                        .init(color: Color(red: 1.0, green: 0.82, blue: 0.1), location: 0.72),
                                        .init(color: Color(red: 0.95, green: 0.45, blue: 0.55), location: 0.72),
                                        .init(color: Color(red: 0.95, green: 0.45, blue: 0.55), location: 1.0)
                                    ],
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            ) : AnyShapeStyle(Color.secondary)
                        )
                        .frame(height: 26)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(viewModel.isPenActive ? Color.blue : Color.clear)
                        .frame(width: 22, height: 3)
                }
                .frame(width: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !viewModel.isPenActive {
                        viewModel.selectPen()
                    } else {
                        isPencilMenuPresented.toggle()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    if !viewModel.isPenActive {
                        viewModel.selectPen()
                    }
                    isPencilMenuPresented = true
                }
                .popover(isPresented: $isPencilMenuPresented, arrowEdge: .top) {
                    PencilSettingsMenuView(viewModel: viewModel)
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel("Pen Tool")
                
                // Eraser Tool
                VStack(spacing: 4) {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            viewModel.isEraserActive ?
                            AnyShapeStyle(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(red: 0.96, green: 0.50, blue: 0.62), location: 0.0),
                                        .init(color: Color(red: 0.96, green: 0.50, blue: 0.62), location: 0.52),
                                        .init(color: Color(red: 0.78, green: 0.28, blue: 0.42), location: 0.52),
                                        .init(color: Color(red: 0.78, green: 0.28, blue: 0.42), location: 1.0)
                                    ],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading
                                )
                            ) : AnyShapeStyle(Color.secondary)
                        )
                        .frame(height: 26)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(viewModel.isEraserActive ? Color.blue : Color.clear)
                        .frame(width: 22, height: 3)
                }
                .frame(width: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectEraser()
                }
                .accessibilityLabel("Eraser Tool")
                
                // Lasso Tool
                VStack(spacing: 4) {
                    Image(systemName: "lasso")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(viewModel.isLassoActive ? .blue : .secondary)
                        .frame(height: 26)
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(viewModel.isLassoActive ? Color.blue : Color.clear)
                        .frame(width: 22, height: 3)
                }
                .frame(width: 40)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectLasso()
                }
                .accessibilityLabel("Lasso Tool")
                
                Spacer()
                
                HStack(spacing: 20) {
                    // Page Column Toggle Icon (2 cards side by side like Notability)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPageSidebarPresented.toggle()
                        }
                    }) {
                        Image(systemName: isPageSidebarPresented ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(isPageSidebarPresented ? .examButton : .primary)
                    }
                    .accessibilityLabel("Page Manager")
                    
                    Button("Submit") {
                        viewModel.showSubmitConfirmation = true
                    }
                    .foregroundColor(.red)
                    .fontWeight(.bold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(UIColor.systemGroupedBackground))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            
            // Dynamic Document Area & Trailing Page Column
            ScrollViewReader { scrollProxy in
                GeometryReader { fullGeo in
                    // Page dimensions remain constant regardless of sidebar visibility
                    let pageWidth = fullGeo.size.width
                    let pageHeight = pageWidth * 1.414
                    let viewportHeight = fullGeo.size.height
                    let totalPages = 1 + viewModel.gridPageCount
                    let totalDocumentHeight = (CGFloat(totalPages) * pageHeight) + (CGFloat(totalPages - 1) * pageSpacing)
                    
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            ZStack(alignment: .top) {
                                VStack(spacing: pageSpacing) {
                                    // Page 0: Questionnaire Page
                                    QuestionnairePageView()
                                        .frame(width: pageWidth, height: pageHeight)
                                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                        .id(0)
                                        .background(
                                            GeometryReader { pageGeo in
                                                let frame = pageGeo.frame(in: .named("ExamDocumentScrollView"))
                                                Color.clear.preference(
                                                    key: PageFramePreferenceKey.self,
                                                    value: [
                                                        0: PageFrameData(
                                                            index: 0,
                                                            minY: frame.minY,
                                                            maxY: frame.maxY
                                                        )
                                                    ]
                                                )
                                            }
                                        )
                                    
                                    // Math Grid Pages (Page 1+)
                                    ForEach(0..<viewModel.gridPageCount, id: \.self) { gridIndex in
                                        let pageIdx = gridIndex + 1
                                        MathGridView()
                                            .frame(width: pageWidth, height: pageHeight)
                                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                            .id(pageIdx)
                                            .background(
                                                GeometryReader { pageGeo in
                                                    let frame = pageGeo.frame(in: .named("ExamDocumentScrollView"))
                                                    Color.clear.preference(
                                                        key: PageFramePreferenceKey.self,
                                                        value: [
                                                            pageIdx: PageFrameData(
                                                                index: pageIdx,
                                                                minY: frame.minY,
                                                                maxY: frame.maxY
                                                            )
                                                        ]
                                                    )
                                                }
                                            )
                                    }
                                }
                                .padding(.vertical, 20)
                                
                                // PencilKit Canvas overlaid on the pages
                                ExamCanvasView(
                                    canvasView: $canvasView,
                                    currentTool: $viewModel.currentTool,
                                    onDrawingChanged: { drawing in
                                        viewModel.currentDrawing = drawing
                                        viewModel.drawingRevision += 1
                                    }
                                )
                                .frame(width: pageWidth, height: totalDocumentHeight + 40)
                                .allowsHitTesting(true)
                            }
                        }
                        .coordinateSpace(name: "ExamDocumentScrollView")
                        .onPreferenceChange(PageFramePreferenceKey.self) { frames in
                            let centerTarget = viewportHeight / 2.0
                            var closestIndex = currentPageIndex
                            var smallestDistance: CGFloat = .infinity
                            
                            for (index, data) in frames {
                                let distance = abs(data.midY - centerTarget)
                                if distance < smallestDistance {
                                    smallestDistance = distance
                                    closestIndex = index
                                }
                            }
                            
                            if closestIndex != currentPageIndex {
                                currentPageIndex = closestIndex
                            }
                        }
                        
                        // Trailing slide-over sidebar column
                        if isPageSidebarPresented {
                            ExamPageSidebarView(
                                pageCount: totalPages,
                                currentPageIndex: currentPageIndex,
                                drawing: viewModel.currentDrawing,
                                drawingVersion: viewModel.drawingRevision,
                                pageWidth: pageWidth,
                                pageHeight: pageHeight,
                                pageSpacing: pageSpacing,
                                onSelectPage: { selectedIndex in
                                    withAnimation {
                                        scrollProxy.scrollTo(selectedIndex, anchor: .top)
                                    }
                                },
                                onToggleFormulaPage: {
                                    // TODO: Implement formula overlay
                                },
                                onAddPage: {
                                    viewModel.addGridPage()
                                }
                            )
                            .frame(width: sidebarWidth)
                            .transition(.move(edge: .trailing))
                            .shadow(color: .black.opacity(0.18), radius: 8, x: -3, y: 0)
                        }
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .overlay(
            // Submission Confirmation Dialog
            Group {
                if viewModel.showSubmitConfirmation {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        Text("Ready to submit?")
                            .font(.headline)
                        Text("You cannot edit your exam once submitted.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 20) {
                            Button("Cancel") {
                                viewModel.showSubmitConfirmation = false
                            }
                            .foregroundColor(.secondary)
                            
                            Button("Confirm Submit") {
                                viewModel.submitExam(assessmentManager: assessmentManager)
                            }
                            .foregroundColor(.red)
                            .fontWeight(.bold)
                        }
                    }
                    .padding(30)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
        )
        .overlay(
            // Submission Success View
            Group {
                if viewModel.submissionSuccess {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("Exam Submitted!")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Returning to start screen...")
                            .foregroundColor(.gray)
                        
                        Button("Done") {
                            viewModel.currentState = .start
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.examButton)
                    }
                    .padding(40)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
        )
    }
}

struct QuestionnairePageView: View {
    var body: some View {
        ZStack {
            Color.white
            
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(.examTitle)
                
                Text("Exam Questionnaire")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                
                Text("The supervisor's PDF will render on this page.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

private struct PageFrameData: Equatable {
    let index: Int
    let minY: CGFloat
    let maxY: CGFloat
    var midY: CGFloat { (minY + maxY) / 2 }
}

private struct PageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: PageFrameData] = [:]
    static func reduce(value: inout [Int: PageFrameData], nextValue: () -> [Int: PageFrameData]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

#Preview {
    ActiveExamView()
        .environmentObject(ExamFlowViewModel())
        .environmentObject(AssessmentManager())
}
