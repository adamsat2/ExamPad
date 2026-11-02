//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit
import UIKit

///Non-interfering gesture recognizer that observes Apple Pencil touches in parallel with PencilKit's
///internal `drawingGestureRecognizer` to power the 0.45s Hold-to-Snap 2D shape engine.
final class PencilTouchObserverGestureRecognizer: UIGestureRecognizer {
    var onTouchBegan: ((CGPoint, TimeInterval) -> Void)?
    var onTouchMoved: ((CGPoint, TimeInterval) -> Void)?
    var onTouchEnded: ((CGPoint, TimeInterval) -> Void)?
    var onTouchCancelled: (() -> Void)?
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first(where: { $0.type == .pencil }), let view = self.view else {
            state = .failed
            return
        }
        state = .began
        let loc = touch.location(in: view)
        onTouchBegan?(loc, touch.timestamp)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first(where: { $0.type == .pencil }), let view = self.view else { return }
        state = .changed
        // Capture coalesced touches if available for higher fidelity polygon/circle geometry
        if let coalesced = event.coalescedTouches(for: touch), !coalesced.isEmpty {
            for cTouch in coalesced {
                onTouchMoved?(cTouch.location(in: view), cTouch.timestamp)
            }
        } else {
            onTouchMoved?(touch.location(in: view), touch.timestamp)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first(where: { $0.type == .pencil }), let view = self.view else {
            state = .ended
            return
        }
        let loc = touch.location(in: view)
        onTouchEnded?(loc, touch.timestamp)
        state = .ended
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouchCancelled?()
        state = .cancelled
    }
    
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

/// Subclass of PKCanvasView that routes undo/redo actions to a shared document UndoManager
/// and integrates real-time Hold-to-Snap 2D shape recognition.
final class FixedCanvasView: PKCanvasView {
    weak var customUndoManager: UndoManager?
    
    override var undoManager: UndoManager? {
        return customUndoManager ?? super.undoManager
    }
    
    // MARK: - Hold-to-Snap State
    private var touchObserverGesture: PencilTouchObserverGestureRecognizer?
    private var capturedPoints: [CGPoint] = []
    private var capturedTimestamps: [TimeInterval] = []
    private var lastAnchorPoint: CGPoint = .zero
    private var holdTimer: Timer?
    private var preStrokeDrawing: PKDrawing = PKDrawing()
    private(set) var didSnapDuringCurrentTouch: Bool = false
    
    var onShapeSnapped: ((PKDrawing) -> Void)?
    
    func installShapeRecognitionObserver() {
        guard touchObserverGesture == nil else { return }
        let observer = PencilTouchObserverGestureRecognizer(target: nil, action: nil)
        observer.delegate = self
        
        observer.onTouchBegan = { [weak self] point, timestamp in
            self?.handlePencilBegan(at: point, timestamp: timestamp)
        }
        observer.onTouchMoved = { [weak self] point, timestamp in
            self?.handlePencilMoved(to: point, timestamp: timestamp)
        }
        observer.onTouchEnded = { [weak self] _, _ in
            self?.handlePencilEndedOrCancelled()
        }
        observer.onTouchCancelled = { [weak self] in
            self?.handlePencilEndedOrCancelled()
        }
        
        addGestureRecognizer(observer)
        touchObserverGesture = observer
    }
    
    private func handlePencilBegan(at point: CGPoint, timestamp: TimeInterval) {
        holdTimer?.invalidate()
        holdTimer = nil
        didSnapDuringCurrentTouch = false
        
        guard tool is PKInkingTool else {
            capturedPoints.removeAll()
            capturedTimestamps.removeAll()
            return
        }
        
        preStrokeDrawing = drawing
        capturedPoints = [point]
        capturedTimestamps = [timestamp]
        lastAnchorPoint = point
    }
    
    private func handlePencilMoved(to point: CGPoint, timestamp: TimeInterval) {
        guard !didSnapDuringCurrentTouch, tool is PKInkingTool else { return }
        
        capturedPoints.append(point)
        capturedTimestamps.append(timestamp)
        
        // Whenever the pencil moves more than 3.5pt from the stationary anchor, reset the 0.45s hold timer
        let movement = hypot(point.x - lastAnchorPoint.x, point.y - lastAnchorPoint.y)
        if movement > 3.5 {
            lastAnchorPoint = point
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.attemptHoldToSnap()
            }
        }
    }
    
    private func handlePencilEndedOrCancelled() {
        holdTimer?.invalidate()
        holdTimer = nil
        capturedPoints.removeAll()
        capturedTimestamps.removeAll()
    }
    
    private func attemptHoldToSnap() {
        guard !didSnapDuringCurrentTouch,
              let inkingTool = tool as? PKInkingTool,
              capturedPoints.count >= 2 else { return }
        
        // Recognize 2D geometric shape if stroke length > 40pt
        guard let recognized = ShapeRecognitionEngine.recognizeShape(from: capturedPoints) else { return }
        
        didSnapDuringCurrentTouch = true
        holdTimer?.invalidate()
        holdTimer = nil
        
        let snappedStroke = ShapeRecognitionEngine.createPKStroke(from: recognized, tool: inkingTool)
        let previousDrawing = preStrokeDrawing
        
        // Cancel the active raw PencilKit touch stream so lifting the pen won't append the raw freehand stroke
        drawingGestureRecognizer.isEnabled = false
        drawingGestureRecognizer.isEnabled = true
        
        // Build the new drawing by replacing the in-progress stroke with our clean geometric PKStroke
        var updatedStrokes = previousDrawing.strokes
        updatedStrokes.append(snappedStroke)
        let snappedDrawing = PKDrawing(strokes: updatedStrokes)
        
        applyDrawingWithUndo(from: previousDrawing, to: snappedDrawing)
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    private func applyDrawingWithUndo(from oldDrawing: PKDrawing, to newDrawing: PKDrawing) {
        drawing = newDrawing
        onShapeSnapped?(newDrawing)
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyDrawingWithUndo(from: newDrawing, to: oldDrawing)
        }
        undoManager?.setActionName("Snap Shape")
    }
}

extension FixedCanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

struct ExamCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var currentTool: PKTool
    var undoManager: UndoManager? = nil
    var onDrawingChanged: (() -> Void)? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: ExamCanvasView
        var isUsingTool = false
        var isUpdatingFromSwiftUI = false
        var lastCanvasDrawing: PKDrawing?
        
        init(_ parent: ExamCanvasView) {
            self.parent = parent
        }
        
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = true
        }
        
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            // If Hold-to-Snap already committed the geometric shape and cancelled the raw touch,
            // do not let the cancelled raw stroke overwrite the snapped shape.
            if let fixed = canvasView as? FixedCanvasView, fixed.didSnapDuringCurrentTouch {
                return
            }
            commitDrawing(canvasView)
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Guard against recursive events triggered by makeUIView / updateUIView
            guard !isUpdatingFromSwiftUI else { return }
            if let fixed = canvasView as? FixedCanvasView, fixed.didSnapDuringCurrentTouch && isUsingTool {
                return
            }
            // If the user is drawing, we commit when the stroke ends (pen lifts)
            if !isUsingTool {
                commitDrawing(canvasView)
            }
        }
        
        func commitDrawing(_ canvasView: PKCanvasView) {
            let newDrawing = canvasView.drawing
            lastCanvasDrawing = newDrawing
            
            // Asynchronously dispatch binding update so SwiftUI view hierarchy is never mutated
            // mid-event or mid-layout pass
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.areDrawingsEqual(self.parent.drawing, newDrawing) {
                    self.parent.drawing = newDrawing
                }
                self.parent.onDrawingChanged?()
            }
        }
        
        func areDrawingsEqual(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
            if a.strokes.isEmpty && b.strokes.isEmpty {
                return true
            }
            return a == b
        }
        
        func isSameTool(_ toolA: PKTool, _ toolB: PKTool) -> Bool {
            if let inkingA = toolA as? PKInkingTool, let inkingB = toolB as? PKInkingTool {
                return inkingA.inkType == inkingB.inkType &&
                       inkingA.color == inkingB.color &&
                       abs(inkingA.width - inkingB.width) < 0.01
            }
            if let eraserA = toolA as? PKEraserTool, let eraserB = toolB as? PKEraserTool {
                return eraserA.eraserType == eraserB.eraserType &&
                       abs(eraserA.width - eraserB.width) < 0.01
            }
            if toolA is PKLassoTool && toolB is PKLassoTool {
                return true
            }
            return false
        }
    }
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = FixedCanvasView()
        canvasView.customUndoManager = undoManager
        
        // Populate drawing before attaching delegate to avoid spurious change events during construction
        canvasView.drawing = drawing
        context.coordinator.lastCanvasDrawing = drawing
        
        canvasView.delegate = context.coordinator
        canvasView.installShapeRecognitionObserver()
        canvasView.onShapeSnapped = { [weak canvasView] _ in
            guard let canvasView = canvasView else { return }
            context.coordinator.isUsingTool = false
            context.coordinator.commitDrawing(canvasView)
        }
        
        // Only Apple Pencil is recognized for drawing tools (pencil, lasso, eraser)
        // Finger touches are ignored by drawing recognizer so user can scroll naturally
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.isScrollEnabled = false
        
        // Disable automatic content insets
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.bounces = false
        
        // Forces black ink to stay black even if the device is in dark mode
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.tool = currentTool
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        
        if let fixedCanvas = uiView as? FixedCanvasView {
            fixedCanvas.customUndoManager = undoManager
        }
        
        // Only reload uiView.drawing if an external action modified `drawing` (e.g. Undo, Redo, or reset exam).
        // NEVER reload uiView.drawing if the difference is due to the canvas having drawn new content
        // that SwiftUI's async update hasn't settled yet.
        if !context.coordinator.isUsingTool {
            if let last = context.coordinator.lastCanvasDrawing {
                if !context.coordinator.areDrawingsEqual(drawing, last) &&
                   !context.coordinator.areDrawingsEqual(uiView.drawing, drawing) {
                    context.coordinator.isUpdatingFromSwiftUI = true
                    uiView.drawing = drawing
                    context.coordinator.lastCanvasDrawing = drawing
                    context.coordinator.isUpdatingFromSwiftUI = false
                }
            } else if !context.coordinator.areDrawingsEqual(uiView.drawing, drawing) {
                context.coordinator.isUpdatingFromSwiftUI = true
                uiView.drawing = drawing
                context.coordinator.lastCanvasDrawing = drawing
                context.coordinator.isUpdatingFromSwiftUI = false
            }
        }
        
        // Only update tool if changed to prevent resetting active tool state mid-stroke
        if !context.coordinator.isSameTool(uiView.tool, currentTool) {
            uiView.tool = currentTool
        }
        if uiView.drawingPolicy != .pencilOnly {
            uiView.drawingPolicy = .pencilOnly
        }
    }
}

#Preview {
    @Previewable @State var drawing = PKDrawing()
    @Previewable @State var currentTool: PKTool = PKInkingTool(.pen, color: .black, width: 2.5)
    
    ExamCanvasView(drawing: $drawing, currentTool: $currentTool)
}
