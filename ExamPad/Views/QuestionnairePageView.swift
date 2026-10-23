//
//  QuestionnairePageView.swift
//  ExamPad
//

import SwiftUI

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

#Preview {
    QuestionnairePageView()
        .frame(width: 400, height: 565)
        .shadow(radius: 4)
        .padding()
}
