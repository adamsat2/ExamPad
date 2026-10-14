//
//  ExamPadApp.swift
//  ExamPad
//


import SwiftUI
import SwiftData

@main
struct ExamPadApp: App {
    @StateObject private var viewModel = ExamFlowViewModel()
        @StateObject private var assessmentManager = AssessmentManager()
        
        var body: some Scene {
            WindowGroup {
                NavigationStack {
                    Group {
                        switch viewModel.currentState {
                        case .start:
                            StartScreenView()
                        case .scanningQR:
                            Text("QR Scanner View Placeholder") // TODO: Implement QR
                        case .waitingForExam(_):
                            VStack {
                                Text("Waiting for Exam to Begin...")
                                ProgressView()
                            } // TODO: Implement waiting screen
                        case .activeExam:
                            ActiveExamView()
                        }
                    }
                }
                .environmentObject(viewModel)
                .environmentObject(assessmentManager)
                .preferredColorScheme(.none) // Supports both Light & Dark dynamically
            }
            // SwiftData injection for local DB, TODO: Move to external DB
            .modelContainer(for: ExamSessionModel.self)
        }
    }

    struct StartScreenView: View {
        @EnvironmentObject var viewModel: ExamFlowViewModel
        
        var body: some View {
            VStack(spacing: 40) {
                Text("Exam Portal")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(Color.examTitle)
                
                Button(action: {
                    // Mocks the QR scanning flow and goes straight to exam
                    viewModel.mockScanAndStart()
                }) {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan Exam QR Code")
                    }
                    .font(.title2)
                    .padding()
                    .frame(width: 300)
                    .background(Color.examButton)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
        }
    }
