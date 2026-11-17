//
//  QRScannerView.swift
//  ExamPad
//

import SwiftUI
import UIKit

struct QRScannerView: View {
    @EnvironmentObject var viewModel: ExamFlowViewModel
    @EnvironmentObject var assessmentManager: AssessmentManager
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showGuidedAccessAlert: Bool = false
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 84, weight: .regular))
                    .foregroundColor(Color.examTitle)
                
                Text("Scan Exam QR Code")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color.examTitle)
                
                Text("Enable Guided Access to proceed to the exam.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                attemptStartExam()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Proceed to Exam")
                }
                .font(.title3.weight(.semibold))
                .padding()
                .frame(width: 280)
                .background(Color.examButton)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            Button(action: {
                viewModel.returnToStartScreen()
            }) {
                Text("Back")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            assessmentManager.refreshGuidedAccessStatus()
            if !assessmentManager.isGuidedAccessEnabled {
                showGuidedAccessAlert = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                assessmentManager.refreshGuidedAccessStatus()
                if !assessmentManager.isGuidedAccessEnabled {
                    showGuidedAccessAlert = true
                } else {
                    showGuidedAccessAlert = false
                }
            }
        }
        .onChange(of: assessmentManager.isGuidedAccessEnabled) { _, isEnabled in
            if isEnabled {
                showGuidedAccessAlert = false
            } else {
                showGuidedAccessAlert = true
            }
        }
        .alert("Guided Access Required", isPresented: $showGuidedAccessAlert) {
            Button("Open Settings") {
                assessmentManager.openSettingsApp()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Guided Access must be enabled on this device before you can start the exam. Please open Settings > Accessibility > Guided Access to turn it on, then triple-click the \(assessmentManager.guidedAccessHardwareButtonName) to activate it.")
        }
    }
    
    private func attemptStartExam() {
        assessmentManager.refreshGuidedAccessStatus()
        if assessmentManager.isGuidedAccessEnabled {
            viewModel.startExam(assessmentManager: assessmentManager)
        } else {
            showGuidedAccessAlert = true
        }
    }
}

#Preview {
    QRScannerView()
        .environmentObject(ExamFlowViewModel())
        .environmentObject(AssessmentManager())
}
