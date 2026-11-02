//
//  ShapeRecognitionEngine.swift
//  ExamPad
//

import Foundation
import CoreGraphics
import UIKit
import PencilKit

struct RecognizedShape {
    enum ShapeType: String {
        case line
        case circle
        case triangle
        case square
        case rectangle
        case pentagon
        case hexagon
    }
    
    let type: ShapeType
    /// Ordered vertices/points representing the snapped path in canvas coordinates.
    let points: [CGPoint]
    let isClosed: Bool
}

enum ShapeRecognitionEngine {
    /// Recognizes a 2D shape from a sequence of drawn points when the user holds the Apple Pencil still.
    /// Returns `nil` if the stroke is too short (`<= 40pt`) or does not match any supported geometric shape.
    static func recognizeShape(from rawPoints: [CGPoint]) -> RecognizedShape? {
        guard rawPoints.count >= 2 else { return nil }
        
        // Remove consecutive duplicate points
        var points: [CGPoint] = [rawPoints[0]]
        for i in 1..<rawPoints.count {
            if hypot(rawPoints[i].x - points.last!.x, rawPoints[i].y - points.last!.y) > 0.5 {
                points.append(rawPoints[i])
            }
        }
        guard points.count >= 2 else { return nil }
        
        let totalLength = pathLength(points)
        guard totalLength > 40.0 else { return nil }
        
        let startPoint = points.first!
        let endPoint = points.last!
        let startEndDistance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        
        // Step 1: Closed vs. Open Check
        // Measure distance between start point and end point.
        // If distance is < 22% of total path length (or < 45pt), treat as a closed 2D polygon/circle candidate;
        // otherwise check if it is a straight line (collinearity ratio > 0.94) and snap to a straight 2-point line.
        let isClosedCandidate = (startEndDistance < 0.22 * totalLength) || (startEndDistance < 45.0 && totalLength > 90.0)
        
        let collinearity = startEndDistance / totalLength
        if !isClosedCandidate || collinearity > 0.94 {
            if collinearity > 0.94 {
                return RecognizedShape(
                    type: .line,
                    points: interpolateLine(from: startPoint, to: endPoint, spacing: 4.0),
                    isClosed: false
                )
            }
            return nil
        }
        
        // Closed candidate processing
        var closedPoints = points
        if hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) > 1.0 {
            closedPoints.append(startPoint)
        }
        
        let bbox = boundingBox(of: points)
        guard bbox.width > 12.0 && bbox.height > 12.0 else { return nil }
        
        let area = shoelaceArea(closedPoints)
        let perimeter = pathLength(closedPoints)
        guard perimeter > 0 else { return nil }
        
        // Step 2: Circle / Ellipse Detection
        // Circularity C = (4 * pi * Area) / (Perimeter^2)
        let circularity = (4.0 * .pi * area) / (perimeter * perimeter)
        let aspectRatio = bbox.width / bbox.height
        
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        let avgRadius = (bbox.width + bbox.height) / 4.0
        let radialVarianceRatio = normalizedRadialDeviation(points: points, center: center, expectedRadius: avgRadius)
        
        // Step 3: Polygon Simplification via Ramer-Douglas-Peucker
        // Run RDP with adaptive epsilon = 0.035 * Perimeter
        let epsilon = 0.035 * perimeter
        let vertices = extractClosedPolygonVertices(from: points, epsilon: epsilon)
        
        // Evaluate Polygon by RDP vertex count
        switch vertices.count {
        case 3:
            let snappedTriangle = regularizeTriangleIfAppropriate(vertices: vertices)
            let polyPoints = interpolatePolygon(vertices: snappedTriangle, spacing: 4.0)
            return RecognizedShape(type: .triangle, points: polyPoints, isClosed: true)
            
        case 4:
            let (quadVerts, isSquare) = regularizeQuadrilateral(vertices: vertices, boundingBox: bbox)
            let polyPoints = interpolatePolygon(vertices: quadVerts, spacing: 4.0)
            return RecognizedShape(type: isSquare ? .square : .rectangle, points: polyPoints, isClosed: true)
            
        case 5:
            // If circularity is very high (> 0.90) and radial deviation is minimal (< 0.045), it's a circle; otherwise Pentagon
            if circularity > 0.90 && (0.75...1.33).contains(aspectRatio) && radialVarianceRatio < 0.045 {
                let circlePts = generateCirclePoints(center: center, radius: avgRadius, segments: 72)
                return RecognizedShape(type: .circle, points: circlePts, isClosed: true)
            }
            let pentagonVerts = regularPolygonVertices(sides: 5, center: center, radius: avgRadius, referenceVertices: vertices)
            let polyPoints = interpolatePolygon(vertices: pentagonVerts, spacing: 4.0)
            return RecognizedShape(type: .pentagon, points: polyPoints, isClosed: true)
            
        case 6:
            // A regular hexagon has C ≈ 0.907 and radialVarianceRatio ≈ 0.045; a true circle has C > 0.93 and radialVarianceRatio < 0.035
            if circularity > 0.93 && (0.75...1.33).contains(aspectRatio) && radialVarianceRatio < 0.035 {
                let circlePts = generateCirclePoints(center: center, radius: avgRadius, segments: 72)
                return RecognizedShape(type: .circle, points: circlePts, isClosed: true)
            }
            let hexagonVerts = regularPolygonVertices(sides: 6, center: center, radius: avgRadius, referenceVertices: vertices)
            let polyPoints = interpolatePolygon(vertices: hexagonVerts, spacing: 4.0)
            return RecognizedShape(type: .hexagon, points: polyPoints, isClosed: true)
            
        default:
            // Step 2: Circle / Ellipse Detection
            // If C > 0.80 and the aspect ratio of the bounding box is between 0.75 and 1.33, generate a Perfect Circle
            if circularity > 0.80 && (0.75...1.33).contains(aspectRatio) && radialVarianceRatio < 0.16 {
                let circlePts = generateCirclePoints(center: center, radius: avgRadius, segments: 72)
                return RecognizedShape(type: .circle, points: circlePts, isClosed: true)
            }
            return nil
        }
    }
    
    /// Constructs a `PKStroke` matching the active `PKInkingTool` from a `RecognizedShape`.
    static func createPKStroke(from shape: RecognizedShape, tool: PKInkingTool) -> PKStroke {
        let strokeWidth = max(tool.width, 1.0)
        let pointSize = CGSize(width: strokeWidth, height: strokeWidth)
        
        var controlPoints: [PKStrokePoint] = []
        controlPoints.reserveCapacity(shape.points.count)
        
        for (index, pt) in shape.points.enumerated() {
            let strokePoint = PKStrokePoint(
                location: pt,
                timeOffset: TimeInterval(index) * 0.005,
                size: pointSize,
                opacity: 1.0,
                force: 1.0,
                azimuth: 0,
                altitude: .pi / 2.0
            )
            controlPoints.append(strokePoint)
        }
        
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        let ink = PKInk(tool.inkType, color: tool.color)
        return PKStroke(ink: ink, path: path)
    }
    
    // MARK: - Geometry Helpers
    
    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }
    
    static func shoelaceArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[(i + 1) % points.count]
            sum += (p1.x * p2.y) - (p2.x * p1.y)
        }
        return abs(sum) * 0.5
    }
    
    static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    static func normalizedRadialDeviation(points: [CGPoint], center: CGPoint, expectedRadius: CGFloat) -> CGFloat {
        guard !points.isEmpty, expectedRadius > 0 else { return 1.0 }
        var sumSqDiff: CGFloat = 0
        for p in points {
            let r = hypot(p.x - center.x, p.y - center.y)
            let diff = (r - expectedRadius) / expectedRadius
            sumSqDiff += diff * diff
        }
        return sqrt(sumSqDiff / CGFloat(points.count))
    }
    
    /// Ramer-Douglas-Peucker simplification for an open point sequence.
    static func rdpSimplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        
        var maxDistance: CGFloat = 0
        var maxIndex = 0
        let start = points.first!
        let end = points.last!
        
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: start, lineEnd: end)
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }
        
        if maxDistance > epsilon {
            let left = rdpSimplify(Array(points[0...maxIndex]), epsilon: epsilon)
            let right = rdpSimplify(Array(points[maxIndex..<points.count]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [start, end]
        }
    }
    
    /// Extracts clean corner vertices from a closed stroke using RDP + collinear vertex merging.
    static func extractClosedPolygonVertices(from points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 3 else { return points }
        
        let start = points[0]
        var farthestIdx = 0
        var maxDist: CGFloat = -1
        for (i, pt) in points.enumerated() {
            let d = hypot(pt.x - start.x, pt.y - start.y)
            if d > maxDist {
                maxDist = d
                farthestIdx = i
            }
        }
        
        guard farthestIdx > 0 && farthestIdx < points.count - 1 else {
            return rdpSimplify(points, epsilon: epsilon)
        }
        
        let firstHalf = Array(points[0...farthestIdx])
        var secondHalf = Array(points[farthestIdx..<points.count])
        if hypot(secondHalf.last!.x - start.x, secondHalf.last!.y - start.y) > 1.0 {
            secondHalf.append(start)
        }
        
        let simp1 = rdpSimplify(firstHalf, epsilon: epsilon)
        let simp2 = rdpSimplify(secondHalf, epsilon: epsilon)
        
        let vertices = Array(simp1.dropLast()) + Array(simp2.dropLast())
        
        var merged: [CGPoint] = []
        for v in vertices {
            if let last = merged.last, hypot(v.x - last.x, v.y - last.y) < epsilon * 0.8 {
                continue
            }
            merged.append(v)
        }
        if merged.count > 1, let first = merged.first, let last = merged.last,
           hypot(first.x - last.x, first.y - last.y) < epsilon * 0.8 {
            merged.removeLast()
        }
        
        var cleaned = merged
        var changed = true
        while changed && cleaned.count > 3 {
            changed = false
            for i in 0..<cleaned.count {
                let prev = cleaned[(i - 1 + cleaned.count) % cleaned.count]
                let curr = cleaned[i]
                let next = cleaned[(i + 1) % cleaned.count]
                let angle = interiorAngleDegrees(prev: prev, curr: curr, next: next)
                if angle > 156.0 {
                    cleaned.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        
        return cleaned
    }
    
    static func perpendicularDistance(_ pt: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let mag = hypot(dx, dy)
        guard mag > 0.0001 else {
            return hypot(pt.x - lineStart.x, pt.y - lineStart.y)
        }
        return abs(dy * pt.x - dx * pt.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / mag
    }
    
    static func interiorAngleDegrees(prev: CGPoint, curr: CGPoint, next: CGPoint) -> CGFloat {
        let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
        let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
        let mag1 = hypot(v1.x, v1.y)
        let mag2 = hypot(v2.x, v2.y)
        guard mag1 > 0.0001 && mag2 > 0.0001 else { return 180.0 }
        let cosTheta = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / (mag1 * mag2)))
        return acos(cosTheta) * 180.0 / .pi
    }
    
    // MARK: - Shape Regularization
    
    static func regularizeTriangleIfAppropriate(vertices: [CGPoint]) -> [CGPoint] {
        guard vertices.count == 3 else { return vertices }
        let d01 = hypot(vertices[1].x - vertices[0].x, vertices[1].y - vertices[0].y)
        let d12 = hypot(vertices[2].x - vertices[1].x, vertices[2].y - vertices[1].y)
        let d20 = hypot(vertices[0].x - vertices[2].x, vertices[0].y - vertices[2].y)
        
        let maxSide = max(d01, max(d12, d20))
        let minSide = min(d01, min(d12, d20))
        guard maxSide > 0 else { return vertices }
        
        // Regular/isosceles triangle if sides are within 15% length
        if (maxSide - minSide) / maxSide <= 0.15 {
            let cx = (vertices[0].x + vertices[1].x + vertices[2].x) / 3.0
            let cy = (vertices[0].y + vertices[1].y + vertices[2].y) / 3.0
            let center = CGPoint(x: cx, y: cy)
            let avgR = (hypot(vertices[0].x - cx, vertices[0].y - cy) +
                        hypot(vertices[1].x - cx, vertices[1].y - cy) +
                        hypot(vertices[2].x - cx, vertices[2].y - cy)) / 3.0
            return regularPolygonVertices(sides: 3, center: center, radius: avgR, referenceVertices: vertices)
        }
        
        return vertices
    }
    
    static func regularizeQuadrilateral(vertices: [CGPoint], boundingBox: CGRect) -> (vertices: [CGPoint], isSquare: Bool) {
        guard vertices.count == 4 else { return (vertices, false) }
        
        var allNear90 = true
        for i in 0..<4 {
            let prev = vertices[(i + 3) % 4]
            let curr = vertices[i]
            let next = vertices[(i + 1) % 4]
            let angle = interiorAngleDegrees(prev: prev, curr: curr, next: next)
            if abs(angle - 90.0) > 24.0 {
                allNear90 = false
                break
            }
        }
        
        if allNear90 {
            let ratio = boundingBox.width / max(boundingBox.height, 1.0)
            let isSquare = (0.82...1.18).contains(ratio)
            let cx = boundingBox.midX
            let cy = boundingBox.midY
            let halfW = isSquare ? (boundingBox.width + boundingBox.height) / 4.0 : boundingBox.width / 2.0
            let halfH = isSquare ? halfW : boundingBox.height / 2.0
            
            let rectVerts = [
                CGPoint(x: cx - halfW, y: cy - halfH),
                CGPoint(x: cx + halfW, y: cy - halfH),
                CGPoint(x: cx + halfW, y: cy + halfH),
                CGPoint(x: cx - halfW, y: cy + halfH)
            ]
            return (rectVerts, isSquare)
        }
        
        return (vertices, false)
    }
    
    static func regularPolygonVertices(sides: Int, center: CGPoint, radius: CGFloat, referenceVertices: [CGPoint]) -> [CGPoint] {
        guard sides >= 3 else { return referenceVertices }
        let baseAngle: CGFloat
        if let first = referenceVertices.first {
            baseAngle = atan2(first.y - center.y, first.x - center.x)
        } else {
            baseAngle = -.pi / 2.0
        }
        
        return (0..<sides).map { i in
            let angle = baseAngle + CGFloat(i) * (2.0 * .pi / CGFloat(sides))
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }
    
    // MARK: - Path Interpolation for Smooth PKStroke Rendering
    
    static func interpolateLine(from start: CGPoint, to end: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let dist = hypot(end.x - start.x, end.y - start.y)
        let steps = max(2, Int(ceil(dist / spacing)))
        return (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
    }
    
    static func interpolatePolygon(vertices: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard vertices.count >= 3 else { return vertices }
        var result: [CGPoint] = []
        for i in 0..<vertices.count {
            let p1 = vertices[i]
            let p2 = vertices[(i + 1) % vertices.count]
            let seg = interpolateLine(from: p1, to: p2, spacing: spacing)
            if i < vertices.count - 1 {
                result.append(contentsOf: seg.dropLast())
            } else {
                result.append(contentsOf: seg)
            }
        }
        return result
    }
    
    static func generateCirclePoints(center: CGPoint, radius: CGFloat, segments: Int) -> [CGPoint] {
        return (0...segments).map { i in
            let angle = CGFloat(i) * (2.0 * .pi / CGFloat(segments))
            return CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }
}
