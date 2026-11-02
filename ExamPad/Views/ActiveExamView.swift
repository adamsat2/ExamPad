//
//  ActiveExamView.swift
//  ExamPad
//

import SwiftUI
import PencilKit

struct ActiveExamView: View {
    @EnvironmentObject var viewModel: ExamFlowViewModel
    @EnvironmentObject var assessmentManager: AssessmentManager
    
    @State private var isPageSidebarPresented: Bool = false
    @State private var isPencilMenuPresented: Bool = false
    @State private var isEraserMenuPresented: Bool = false
    @State private var isLassoMenuPresented: Bool = false
    @State private var isUndoAnimating: Bool = false
    @State private var isRedoAnimating: Bool = false
    @State private var currentPageIndex: Int = 0
    
    private let pageSpacing: CGFloat = 36
    private let horizontalPageMargin: CGFloat = 36
    private let sidebarWidth: CGFloat = 210
    
    var body: some View {
        VStack(spacing: 0) {
            // Persistent Top Menu (with larger Exam Details header + extra spacing above tools)
            VStack(spacing: 14) {
                // Top Row: Exam Details & Live Lockdown Status Badge
                HStack(alignment: .center, spacing: 12) {
                    Text(viewModel.examTitle)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Live Lockdown Status Pill (verifies lockdown state & tamper count on device)
                    HStack(spacing: 6) {
                        Image(systemName: assessmentManager.isExamLocked ? "lock.shield.fill" : "lock.open.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(
                                assessmentManager.tamperViolationCount > 0
                                ? .orange
                                : (assessmentManager.isExamLocked ? .green : .secondary)
                            )
                        
                        Text(
                            assessmentManager.tamperViolationCount > 0
                            ? "Lockdown Active (\(assessmentManager.tamperViolationCount) exit\(assessmentManager.tamperViolationCount == 1 ? "" : "s") logged)"
                            : (assessmentManager.isExamLocked ? "Exam Lockdown Active" : "Unlocked")
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                
                // Bottom Row: Drawing Tools, Undo/Redo, and Side Menu Toggle
                HStack(spacing: 24) {
                    // Single Pencil Tool with Color & Width Mini Menu
                    VStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(viewModel.isPenActive ? .blue : .primary)
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
                    
                    // Eraser Tool with Width & Mode Mini Menu
                    VStack(spacing: 4) {
                        Image(systemName: "eraser.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(viewModel.isEraserActive ? .blue : .primary)
                            .frame(height: 26)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(viewModel.isEraserActive ? Color.blue : Color.clear)
                            .frame(width: 22, height: 3)
                    }
                    .frame(width: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !viewModel.isEraserActive {
                            viewModel.selectEraser()
                        } else {
                            isEraserMenuPresented.toggle()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        if !viewModel.isEraserActive {
                            viewModel.selectEraser()
                        }
                        isEraserMenuPresented = true
                    }
                    .popover(isPresented: $isEraserMenuPresented, arrowEdge: .top) {
                        EraserSettingsMenuView(viewModel: viewModel)
                            .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityLabel("Eraser Tool")
                    
                    // Lasso Tool with Free vs. Square Lasso Mini Menu
                    VStack(spacing: 4) {
                        Image(systemName: viewModel.selectedLassoMode == .square ? "rectangle.dashed" : "lasso")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(viewModel.isLassoActive ? .blue : .primary)
                            .frame(height: 26)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(viewModel.isLassoActive ? Color.blue : Color.clear)
                            .frame(width: 22, height: 3)
                    }
                    .frame(width: 40)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !viewModel.isLassoActive {
                            viewModel.selectLasso()
                        } else {
                            isLassoMenuPresented.toggle()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.35) {
                        if !viewModel.isLassoActive {
                            viewModel.selectLasso()
                        }
                        isLassoMenuPresented = true
                    }
                    .popover(isPresented: $isLassoMenuPresented, arrowEdge: .top) {
                        LassoSettingsMenuView(viewModel: viewModel)
                            .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityLabel("Lasso Tool")
                    
                    // Undo Button with Quick Minimal Blue Flash Tap Animation
                    Button(action: {
                        guard viewModel.canUndo else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            isUndoAnimating = true
                        }
                        viewModel.undo()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                            withAnimation(.easeOut(duration: 0.10)) {
                                isUndoAnimating = false
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(
                                    isUndoAnimating
                                    ? .blue
                                    : (viewModel.canUndo ? .primary : Color(UIColor.systemGray))
                                )
                                .scaleEffect(isUndoAnimating ? 0.92 : 1.0)
                                .frame(height: 26)
                            
                            Color.clear
                                .frame(width: 22, height: 3)
                        }
                        .frame(width: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo")
                    
                    // Redo Button with Quick Minimal Blue Flash Tap Animation
                    Button(action: {
                        guard viewModel.canRedo else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            isRedoAnimating = true
                        }
                        viewModel.redo()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                            withAnimation(.easeOut(duration: 0.10)) {
                                isRedoAnimating = false
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(
                                    isRedoAnimating
                                    ? .blue
                                    : (viewModel.canRedo ? .primary : Color(UIColor.systemGray))
                                )
                                .scaleEffect(isRedoAnimating ? 0.92 : 1.0)
                                .frame(height: 26)
                            
                            Color.clear
                                .frame(width: 22, height: 3)
                        }
                        .frame(width: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Redo")
                    
                    Spacer()
                    
                    // Page Column Toggle Icon (2 cards side by side like Notability) on the trailing side
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            isPageSidebarPresented.toggle()
                        }
                    }) {
                        Image(systemName: isPageSidebarPresented ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(isPageSidebarPresented ? .examButton : .primary)
                    }
                    .accessibilityLabel("Page Manager")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color(UIColor.systemGroupedBackground))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
            .zIndex(2)
            
            // Dynamic Document Area & Trailing Page Column
            ScrollViewReader { scrollProxy in
                GeometryReader { fullGeo in
                    let basePageWidth = max(fullGeo.size.width - (horizontalPageMargin * 2), 200)
                    let basePageHeight = basePageWidth * 1.414
                    
                    let availableContainerWidth = isPageSidebarPresented
                        ? max(fullGeo.size.width - sidebarWidth, 240)
                        : fullGeo.size.width
                    let displayedPageWidth = max(availableContainerWidth - (horizontalPageMargin * 2), 180)
                    let scaleFactor = displayedPageWidth / basePageWidth
                    let displayedPageHeight = basePageHeight * scaleFactor
                    
                    let viewportHeight = fullGeo.size.height
                    let totalPages = 1 + viewModel.gridPageCount
                    
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: pageSpacing) {
                                // Page 0: Questionnaire Page with its dedicated canvas
                                ZStack {
                                    QuestionnairePageView()
                                    
                                    ExamCanvasView(
                                        drawing: Binding(
                                            get: { viewModel.drawing(for: 0) },
                                            set: { viewModel.setDrawing($0, for: 0) }
                                        ),
                                        currentTool: $viewModel.currentTool,
                                        lassoMode: viewModel.selectedLassoMode,
                                        undoManager: viewModel.undoManager,
                                        onDrawingChanged: {
                                            viewModel.updateUndoRedoState()
                                        }
                                    )
                                }
                                .frame(width: basePageWidth, height: basePageHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.28), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 5)
                                .scaleEffect(scaleFactor)
                                .frame(width: displayedPageWidth, height: displayedPageHeight)
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
                                
                                // Math Grid Pages (Page 1+) with dedicated per-page canvases
                                ForEach(0..<viewModel.gridPageCount, id: \.self) { gridIndex in
                                    let pageIdx = gridIndex + 1
                                    ZStack {
                                        MathGridView()
                                        
                                        ExamCanvasView(
                                            drawing: Binding(
                                                get: { viewModel.drawing(for: pageIdx) },
                                                set: { viewModel.setDrawing($0, for: pageIdx) }
                                            ),
                                            currentTool: $viewModel.currentTool,
                                            lassoMode: viewModel.selectedLassoMode,
                                            undoManager: viewModel.undoManager,
                                            onDrawingChanged: {
                                                viewModel.updateUndoRedoState()
                                            }
                                        )
                                    }
                                    .frame(width: basePageWidth, height: basePageHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.28), lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 5)
                                    .scaleEffect(scaleFactor)
                                    .frame(width: displayedPageWidth, height: displayedPageHeight)
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
                            .padding(.vertical, 28)
                            .padding(.horizontal, horizontalPageMargin)
                            .frame(width: availableContainerWidth)
                        }
                        .frame(width: availableContainerWidth)
                        .background(Color(UIColor.systemGray4).opacity(0.55))
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
                        
                        // Trailing sidebar column that smoothly resizes the document canvas area
                        if isPageSidebarPresented {
                            ExamPageSidebarView(
                                pageCount: totalPages,
                                currentPageIndex: currentPageIndex,
                                getDrawing: { viewModel.drawing(for: $0) },
                                drawingVersion: viewModel.drawingRevision,
                                pageWidth: basePageWidth,
                                pageHeight: basePageHeight,
                                onSelectPage: { selectedIndex in
                                    withAnimation {
                                        scrollProxy.scrollTo(selectedIndex, anchor: .top)
                                    }
                                },
                                onSubmit: {
                                    viewModel.showSubmitConfirmation = true
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
                    .animation(.easeInOut(duration: 0.28), value: isPageSidebarPresented)
                }
            }
        }
        .blur(radius: assessmentManager.isAppInactiveDuringExam ? 18 : 0)
        .edgesIgnoringSafeArea(.bottom)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if !assessmentManager.isExamLocked {
                assessmentManager.beginExamLockdown()
            }
        }
        .overlay(
            // Security Blur Shield when app switcher / Control Center is opened
            Group {
                if assessmentManager.isAppInactiveDuringExam {
                    ZStack {
                        Color.black.opacity(0.65)
                            .edgesIgnoringSafeArea(.all)
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 52))
                                .foregroundColor(.orange)
                            Text("Exam Protected")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Return to ExamPad immediately.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        )
        .overlay(
            // Tamper / Unauthorized Exit Warning Dialog
            Group {
                if assessmentManager.showTamperViolationAlert {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 18) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        
                        VStack(spacing: 8) {
                            Text("Exam Lockdown Warning")
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            Text("Leaving the exam before submitting is not permitted. This event has been logged (\(assessmentManager.tamperViolationCount) violation\(assessmentManager.tamperViolationCount == 1 ? "" : "s")).")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Button(action: {
                            assessmentManager.dismissTamperAlert()
                        }) {
                            Text("Return to Exam")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Color.examButton)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(28)
                    .frame(width: 370)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                }
            }
        )
        .overlay(
            // Submission Confirmation Dialog
            Group {
                if viewModel.showSubmitConfirmation {
                    Color.black.opacity(0.45)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 22) {
                        VStack(spacing: 8) {
                            Text("Ready to submit?")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("You cannot edit your exam once submitted.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        HStack(spacing: 14) {
                            Button(action: {
                                viewModel.showSubmitConfirmation = false
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color(UIColor.tertiarySystemFill))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                viewModel.submitExam(assessmentManager: assessmentManager)
                            }) {
                                Text("Confirm Submit")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.red)
                                    .cornerRadius(10)
                                    .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(28)
                    .frame(width: 360)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
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
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            viewModel.finishSubmissionAndReturnHome(assessmentManager: assessmentManager)
                        }) {
                            Text("Done")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 140, height: 42)
                                .background(Color.examButton)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(30)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(18)
                    .shadow(radius: 12)
                }
            }
        )
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
