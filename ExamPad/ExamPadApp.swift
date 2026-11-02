//
//  ExamPadApp.swift
//  ExamPad
//

import SwiftUI
import SwiftData
import UIKit

@main
struct ExamPadApp: App {
    @StateObject private var viewModel = ExamFlowViewModel()
    @StateObject private var assessmentManager = AssessmentManager()
    
    var body: some Scene {
        WindowGroup {
            GeometryReader { _ in
                let screenSize = currentScreenSize
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
                .frame(
                    minWidth: screenSize.width,
                    maxWidth: screenSize.width,
                    minHeight: screenSize.height,
                    maxHeight: screenSize.height
                )
            }
            .environmentObject(viewModel)
            .environmentObject(assessmentManager)
            .preferredColorScheme(.none) // Supports both Light & Dark dynamically
            .onAppear {
                assessmentManager.enforceFullScreenAtLaunch()
            }
        }
        .windowResizability(.contentSize)
        // SwiftData injection for local DB, TODO: Move to external DB
        .modelContainer(for: ExamSessionModel.self)
    }
    
    private var currentScreenSize: CGSize {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                return windowScene.screen.bounds.size
            }
        }
        return CGSize(width: 1024, height: 1366)
    }
}
