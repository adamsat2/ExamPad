//
//  StartScreenView.swift
//  ExamPad
//

import SwiftUI

struct StartScreenView: View {
    @EnvironmentObject var viewModel: ExamFlowViewModel
    @EnvironmentObject var assessmentManager: AssessmentManager
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Exam Portal")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(Color.examTitle)
            
            Button(action: {
                // Mocks the QR scanning flow, locks down the device & notifications, and enters the exam
                viewModel.mockScanAndStart(assessmentManager: assessmentManager)
            }) {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan Exam (QR Code)")
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

#Preview {
    StartScreenView()
        .environmentObject(ExamFlowViewModel())
        .environmentObject(AssessmentManager())
}
