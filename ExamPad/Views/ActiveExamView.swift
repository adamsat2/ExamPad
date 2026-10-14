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
    
    private let pageSpacing: CGFloat = 24
    
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
                
                HStack(spacing: 24) {
                    Button("Toggle Formula Page") {
                        // TODO: Implement formula overlay
                    }
                    .foregroundColor(.primary)
                    
                    Button("Add Page") {
                        viewModel.addGridPage()
                    }
                    .foregroundColor(.primary)
                    
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
            
            // Dynamic Document Area
            GeometryReader { geometry in
                // Standard A4 aspect ratio
                let pageWidth = geometry.size.width
                let pageHeight = pageWidth * 1.414
                let totalPages = 1 + viewModel.gridPageCount
                let totalDocumentHeight = (CGFloat(totalPages) * pageHeight) + (CGFloat(totalPages - 1) * pageSpacing)
                
                ScrollView {
                    ZStack(alignment: .top) {
                        VStack(spacing: pageSpacing) {
                            // PDF Placeholder
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
                            .frame(width: pageWidth, height: pageHeight)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            
                            // Math Grid Pages
                            ForEach(0..<viewModel.gridPageCount, id: \.self) { _ in
                                MathGridView()
                                    .frame(width: pageWidth, height: pageHeight)
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                            }
                        }
                        
                        // Transparent drawing layer matching exact calculated height
                        ExamCanvasView(canvasView: $canvasView, currentTool: $viewModel.currentTool)
                            .frame(width: pageWidth, height: totalDocumentHeight)
                    }
                    // Add padding to the ZStack so the first/last pages aren't flush against the screen edges
                    .padding(.vertical, pageSpacing)
                }
                .background(Color(UIColor.secondarySystemBackground))
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
