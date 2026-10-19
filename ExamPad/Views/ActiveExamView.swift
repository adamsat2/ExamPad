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
    @State private var currentPageIndex: Int = 0
    
    private let pageSpacing: CGFloat = 24
    private let sidebarWidth: CGFloat = 210
    
    var body: some View {
        VStack(spacing: 0) {
            // Persistent Top Menu
            HStack(spacing: 20) {
                Button(action: { viewModel.selectTool(color: .black) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(viewModel.currentTool is PKInkingTool && (viewModel.currentTool as? PKInkingTool)?.color == .black ? .examButton : .primary)
                }
                
                Button(action: { viewModel.selectTool(color: .blue) }) {
                    Image(systemName: "pencil")
                        .foregroundColor(viewModel.currentTool is PKInkingTool && (viewModel.currentTool as? PKInkingTool)?.color == .blue ? .blue : .primary)
                }
                
                Button(action: { viewModel.selectTool(color: nil, isLasso: true) }) {
                    Image(systemName: "lasso")
                        .foregroundColor(.primary)
                }
                
                Button(action: { viewModel.selectTool(color: nil, isEraser: true) }) {
                    Image(systemName: "eraser")
                        .foregroundColor(.primary)
                }
                
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
            .padding()
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
                                
                                // Transparent drawing layer matching exact calculated height
                                ExamCanvasView(
                                    canvasView: $canvasView,
                                    currentTool: $viewModel.currentTool,
                                    onDrawingChanged: { drawing in
                                        viewModel.currentDrawing = drawing
                                        viewModel.drawingRevision += 1
                                    }
                                )
                                .frame(width: pageWidth, height: totalDocumentHeight)
                            }
                            // Add padding to the ZStack so the first/last pages aren't flush against the screen edges
                            .padding(.vertical, pageSpacing)
                        }
                        .frame(width: fullGeo.size.width, height: fullGeo.size.height)
                        .coordinateSpace(name: "ExamDocumentScrollView")
                        .onPreferenceChange(PageFramePreferenceKey.self) { framesDict in
                            let frames = Array(framesDict.values)
                            guard !frames.isEmpty else { return }
                            let center = viewportHeight / 2
                            
                            let activeIndex: Int
                            if let containing = frames.first(where: { $0.minY <= center && $0.maxY >= center }) {
                                activeIndex = containing.index
                            } else if let closest = frames.min(by: { abs($0.midY - center) < abs($1.midY - center) }) {
                                activeIndex = closest.index
                            } else {
                                activeIndex = 0
                            }
                            
                            if currentPageIndex != activeIndex {
                                currentPageIndex = activeIndex
                            }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        
                        // Trailing Page Column (Overlay panel, Notability style)
                        if isPageSidebarPresented {
                            HStack(spacing: 0) {
                                Divider()
                                
                                ExamPageSidebarView(
                                    pageCount: totalPages,
                                    currentPageIndex: currentPageIndex,
                                    drawing: viewModel.currentDrawing,
                                    drawingVersion: viewModel.drawingRevision,
                                    pageWidth: pageWidth,
                                    pageHeight: pageHeight,
                                    pageSpacing: pageSpacing,
                                    onSelectPage: { selectedIndex in
                                        currentPageIndex = selectedIndex
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            scrollProxy.scrollTo(selectedIndex, anchor: .top)
                                        }
                                    },
                                    onToggleFormulaPage: {
                                        // TODO: Implement formula overlay
                                    },
                                    onAddPage: {
                                        viewModel.addGridPage()
                                        let newPageIndex = viewModel.gridPageCount
                                        currentPageIndex = newPageIndex
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                scrollProxy.scrollTo(newPageIndex, anchor: .top)
                                            }
                                        }
                                    }
                                )
                                .frame(width: sidebarWidth)
                                .shadow(color: .black.opacity(0.18), radius: 8, x: -3, y: 0)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            assessmentManager.clearClipboard()
            assessmentManager.beginExamLockdown()
        }
        .alert("Submit Exam", isPresented: $viewModel.showSubmitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, Submit", role: .destructive) {
                viewModel.submitExam(assessmentManager: assessmentManager)
            }
        } message: {
            Text("Are you sure you want to submit your exam? You cannot undo this action.")
        }
        .overlay(
            Group {
                if viewModel.submissionSuccess {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.examButton)
                        
                        Text("Exam Submitted Successfully")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.examTitle)
                        
                        Button("OK") {
                            viewModel.submissionSuccess = false
                            viewModel.currentState = .start
                        }
                        .padding(.top, 8)
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
