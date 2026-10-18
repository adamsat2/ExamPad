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
