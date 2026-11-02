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
            let isWindowLocked = assessmentManager.isExamLocked || viewModel.currentState == .activeExam
            let screenSize = assessmentManager.lockedScreenSize.width > 0
                ? assessmentManager.lockedScreenSize
                : currentScreenSize
            
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
                minWidth: isWindowLocked ? screenSize.width : AssessmentManager.defaultMinimumWindowSize.width,
                idealWidth: isWindowLocked ? screenSize.width : nil,
                maxWidth: isWindowLocked ? screenSize.width : .infinity,
                minHeight: isWindowLocked ? screenSize.height : AssessmentManager.defaultMinimumWindowSize.height,
                idealHeight: isWindowLocked ? screenSize.height : nil,
                maxHeight: isWindowLocked ? screenSize.height : .infinity
            )
            .environmentObject(viewModel)
            .environmentObject(assessmentManager)
            .preferredColorScheme(.none) // Supports both Light & Dark dynamically
            .onAppear {
                assessmentManager.configureInitialWindowState()
            }
            .onChange(of: viewModel.currentState) { _, newState in
                if newState == .activeExam && !assessmentManager.isExamLocked {
                    assessmentManager.beginExamLockdown()
                }
            }
        }
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
