//
//  ExamSessionModel.swift
//  ExamPad
//

import Foundation
import SwiftData

enum ExamPeriod: String, Codable {
    case moedA = "Moed A"
    case moedB = "Moed B"
    case special = "Special"
}

// NOTE:
// Currently annotated with @Model for local SwiftData persistence
// When migrating to the web backend, this model can be easily adapted to conform to
// Decodable/Encodable, serving as the DTO (Data Transfer Object) for REST/GraphQL endpoints
@Model
final class ExamSessionModel {
    @Attribute(.unique) var id: UUID
    var examName: String
    var year: String
    var semester: String
    var period: ExamPeriod
    var pdfReferenceUrl: String?
    
    init(id: UUID = UUID(), examName: String, year: String, semester: String, period: ExamPeriod, pdfReferenceUrl: String? = nil) {
        self.id = id
        self.examName = examName
        self.year = year
        self.semester = semester
        self.period = period
        self.pdfReferenceUrl = pdfReferenceUrl
    }
}
