//
//  ExamCanvasView.swift
//  ExamPad
//

import SwiftUI
import PencilKit
import UIKit

/// Gesture recognizer that tracks ONLY Apple Pencil touches (`.pencil`).
/// Finger touches (`.direct`) are ignored so the outer SwiftUI `ScrollView` always scrolls smoothly with fingers,
/// while Apple Pencil touches are captured exclusively for Hold-to-Snap and Lasso selection/dragging/resizing.
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
        // When the user drags the Apple Pencil, prevent the enclosing UIScrollView's panGestureRecognizer
        // from scrolling the page while drawing a Lasso or stroke with the Apple Pencil.
        if preventedGestureRecognizer is UIPanGestureRecognizer,
           preventedGestureRecognizer.view is UIScrollView {
            return true
        }
        return false
    }
    
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

/// Visual overlay view rendered on top of `FixedCanvasView` to show the active Lasso selection path,
/// committed Freehand or Square selection outline, live transformed strokes preview, and interactive corner resize handles.
final class LassoSelectionOverlayView: UIView {
    enum CornerHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    var lassoMode: LassoMode = .free {
        didSet { setNeedsDisplay() }
    }
    var activeLassoPoints: [CGPoint] = [] {
        didSet { setNeedsDisplay() }
    }
    var activeSquareRect: CGRect? = nil {
        didSet { setNeedsDisplay() }
    }
    /// When the user selects strokes in Free Lasso mode, this stores the exact freehand loop they drew
    /// (or the organic contour around a tapped/pasted stroke) so it stays in the shape they created rather than turning into a square.
    var committedFreeLassoPolygon: [CGPoint] = [] {
        didSet { setNeedsDisplay() }
    }
    var selectionBounds: CGRect? = nil {
        didSet { setNeedsDisplay() }
    }
    var showCornerHandles: Bool = false {
        didSet { setNeedsDisplay() }
    }
    var previewStrokes: [PKStroke] = [] {
        didSet { setNeedsDisplay() }
    }
    
    private let handleRadius: CGFloat = 7.5
    private let hitTestRadius: CGFloat = 28.0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func cornerPosition(for corner: CornerHandle, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
    
    func hitTestCorner(at point: CGPoint) -> CornerHandle? {
        guard showCornerHandles, let rect = selectionBounds else { return nil }
        for corner in CornerHandle.allCases {
            let pos = cornerPosition(for: corner, in: rect)
            if hypot(point.x - pos.x, point.y - pos.y) <= hitTestRadius {
                return corner
            }
        }
        return nil
    }
    
    func containsSelectionPoint(_ point: CGPoint) -> Bool {
        if !committedFreeLassoPolygon.isEmpty {
            let bezier = UIBezierPath()
            bezier.move(to: committedFreeLassoPolygon[0])
            for pt in committedFreeLassoPolygon.dropFirst() {
                bezier.addLine(to: pt)
            }
            bezier.close()
            if bezier.contains(point) {
                return true
            }
        }
        if let rect = selectionBounds, rect.insetBy(dx: -12, dy: -12).contains(point) {
            return true
        }
        return false
    }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let accentBlue = UIColor.systemBlue
        
        // 1. Render live preview of selected strokes while moving or resizing
        if !previewStrokes.isEmpty {
            let subDrawing = PKDrawing(strokes: previewStrokes)
            let renderRect = subDrawing.bounds.insetBy(dx: -12, dy: -12).intersection(bounds)
            if !renderRect.isNull && !renderRect.isEmpty {
                var image: UIImage?
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    image = subDrawing.image(from: renderRect, scale: UIScreen.main.scale)
                }
                image?.draw(in: renderRect)
            }
        }
        
        // 2. Draw ONLY the active in-progress selection marquee (Square OR Free, never both)
        if lassoMode == .square, let marquee = activeSquareRect {
            ctx.saveGState()
            ctx.setFillColor(accentBlue.withAlphaComponent(0.08).cgColor)
            ctx.fill(marquee)
            ctx.setStrokeColor(accentBlue.cgColor)
            ctx.setLineWidth(1.8)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(marquee)
            ctx.restoreGState()
        } else if lassoMode == .free, activeLassoPoints.count >= 2 {
            ctx.saveGState()
            let path = UIBezierPath()
            path.move(to: activeLassoPoints[0])
            for pt in activeLassoPoints.dropFirst() {
                path.addLine(to: pt)
            }
            accentBlue.withAlphaComponent(0.06).setFill()
            path.fill()
            accentBlue.setStroke()
            path.lineWidth = 1.8
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
            ctx.restoreGState()
        }
        
        // 3. Draw committed selection outline:
        //    - If in Free Lasso mode and `committedFreeLassoPolygon` is non-empty, draw the exact freehand shape!
        //    - If in Square Lasso mode (or rectangular selection), draw the rectangle + 4 corner resize handles.
        if !committedFreeLassoPolygon.isEmpty && lassoMode == .free {
            ctx.saveGState()
            let path = UIBezierPath()
            path.move(to: committedFreeLassoPolygon[0])
            for pt in committedFreeLassoPolygon.dropFirst() {
                path.addLine(to: pt)
            }
            path.close()
            accentBlue.withAlphaComponent(0.06).setFill()
            path.fill()
            accentBlue.setStroke()
            path.lineWidth = 1.85
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
            ctx.restoreGState()
        } else if let selRect = selectionBounds {
            ctx.saveGState()
            ctx.setFillColor(accentBlue.withAlphaComponent(0.06).cgColor)
            ctx.fill(selRect)
            
            ctx.setStrokeColor(accentBlue.cgColor)
            ctx.setLineWidth(1.75)
            ctx.setLineDash(phase: 0, lengths: [5, 4])
            ctx.stroke(selRect)
            ctx.restoreGState()
            
            // Draw 4 corner resize handles when Square Lasso is active
            if showCornerHandles {
                for corner in CornerHandle.allCases {
                    let pt = cornerPosition(for: corner, in: selRect)
                    let handleRect = CGRect(
                        x: pt.x - handleRadius,
                        y: pt.y - handleRadius,
                        width: handleRadius * 2,
                        height: handleRadius * 2
                    )
                    ctx.saveGState()
                    ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.25).cgColor)
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: handleRect.insetBy(dx: -2, dy: -2))
                    ctx.restoreGState()
                    
                    ctx.saveGState()
                    ctx.setFillColor(accentBlue.cgColor)
                    ctx.fillEllipse(in: handleRect)
                    ctx.restoreGState()
                }
            }
        }
    }
}

/// Subclass of PKCanvasView that routes undo/redo actions to a shared document UndoManager,
/// integrates real-time Hold-to-Snap 2D shape recognition, and provides Notability-style Apple-Pencil-only
/// Free & Square Lasso selection using UIKit's built-in `UIEditMenuInteraction` callout menu.
final class FixedCanvasView: PKCanvasView {
    /// Shared in-app clipboard for Lasso Copy/Cut/Paste so it never triggers iOS Universal Clipboard prompts.
    /// Also stores the copied freehand polygon (if copied from a Free Lasso selection) so pasting preserves
    /// the exact selection shape shifted to the new paste location!
    private static var copiedStrokesClipboard: [PKStroke] = []
    private static var copiedFreeLassoPolygonClipboard: [CGPoint] = []
    
    private static let selectionMenuIdentifier: NSString = "ExamPad.LassoSelectionMenu"
    private static let pasteOnlyMenuIdentifier: NSString = "ExamPad.LassoPasteOnlyMenu"
    
    weak var customUndoManager: UndoManager?
    
    override var undoManager: UndoManager? {
        return customUndoManager ?? super.undoManager
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    var lassoMode: LassoMode = .free {
        didSet {
            if oldValue != lassoMode {
                clearLassoSelection()
            }
            lassoOverlay.lassoMode = lassoMode
            syncLassoGestureMode()
        }
    }
    
    var isLassoToolSelected: Bool = false {
        didSet {
            if !isLassoToolSelected {
                clearLassoSelection()
            }
            syncLassoGestureMode()
        }
    }
    
    // MARK: - Hold-to-Snap State
    private var touchObserverGesture: PencilTouchObserverGestureRecognizer?
    private var capturedPoints: [CGPoint] = []
    private var capturedTimestamps: [TimeInterval] = []
    private var lastAnchorPoint: CGPoint = .zero
    private var holdTimer: Timer?
    private var preStrokeDrawing: PKDrawing = PKDrawing()
    private(set) var didSnapDuringCurrentTouch: Bool = false
    private var pendingSnappedDrawing: PKDrawing?
    
    var onShapeSnapped: ((PKDrawing) -> Void)?
    
    // MARK: - Custom Lasso, System UIEditMenuInteraction & Resize State
    private let lassoOverlay = LassoSelectionOverlayView()
    private var editMenuInteraction: UIEditMenuInteraction?
    private var isEditMenuVisible: Bool = false
    private var pinchGesture: UIPinchGestureRecognizer?
    private weak var configuredEnclosingScrollView: UIScrollView?
    
    private var selectedStrokeIndices: [Int] = []
    private var preTransformDrawing: PKDrawing = PKDrawing()
    private var unselectedStrokesDuringTransform: [PKStroke] = []
    private var originalSelectedStrokes: [PKStroke] = []
    private var currentTransformedSelectedStrokes: [PKStroke] = []
    private var initialSelectionBounds: CGRect = .zero
    private var initialFreeLassoPolygon: [CGPoint] = []
    private var activeCornerDrag: LassoSelectionOverlayView.CornerHandle?
    private var isMovingSelectedStrokes: Bool = false
    private var moveStartPoint: CGPoint = .zero
    private var pencilTouchDownPoint: CGPoint = .zero
    private var didMoveSignificantlyDuringLassoTouch: Bool = false
    private var tappedInsideExistingSelectionOnBegan: Bool = false
    /// Tracks whether the user had an active selection (or visible Paste pill) when the Apple Pencil touched down,
    /// so tapping away on empty space *only deselects* on the first tap, and only shows the "Paste" popup on a second tap!
    private var hadSelectionOrMenuOnTouchBegan: Bool = false
    private var squareDrawStartPoint: CGPoint?
    private var freeLassoPoints: [CGPoint] = []
    private var pasteTargetPoint: CGPoint = .zero
    private(set) var isTransformingSelection: Bool = false
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureEnclosingDocumentScrollViewForFingerOnlyScrolling()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if lassoOverlay.superview == nil {
            addSubview(lassoOverlay)
        }
        lassoOverlay.frame = bounds
        bringSubviewToFront(lassoOverlay)
        configureEnclosingDocumentScrollViewForFingerOnlyScrolling()
    }
    
    /// Ensures the enclosing SwiftUI document `UIScrollView` ONLY scrolls with finger touches (`.direct`)
    /// and never steals Apple Pencil touches (`.pencil`).
    private func configureEnclosingDocumentScrollViewForFingerOnlyScrolling() {
        var ancestor: UIView? = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView, scrollView !== self {
                if configuredEnclosingScrollView !== scrollView ||
                   scrollView.panGestureRecognizer.allowedTouchTypes != [NSNumber(value: UITouch.TouchType.direct.rawValue)] {
                    scrollView.panGestureRecognizer.allowedTouchTypes = [
                        NSNumber(value: UITouch.TouchType.direct.rawValue)
                    ]
                    configuredEnclosingScrollView = scrollView
                }
                break
            }
            ancestor = current.superview
        }
    }
    
    func installShapeAndLassoObservers() {
        guard touchObserverGesture == nil else { return }
        let observer = PencilTouchObserverGestureRecognizer(target: nil, action: nil)
        observer.delegate = self
        
        observer.onTouchBegan = { [weak self] point, timestamp in
            self?.handlePencilBegan(at: point, timestamp: timestamp)
        }
        observer.onTouchMoved = { [weak self] point, timestamp in
            self?.handlePencilMoved(to: point, timestamp: timestamp)
        }
        observer.onTouchEnded = { [weak self] point, timestamp in
            self?.handlePencilEnded(at: point, timestamp: timestamp)
        }
        observer.onTouchCancelled = { [weak self] in
            self?.handlePencilCancelled()
        }
        
        addGestureRecognizer(observer)
        touchObserverGesture = observer
        
        // Two-finger pinch gesture to scale selected strokes in both Free and Square Lasso modes.
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleSelectionPinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delaysTouchesBegan = false
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = self
        addGestureRecognizer(pinch)
        pinchGesture = pinch
        
        // Install UIKit's built-in UIEditMenuInteraction for the system Cut/Copy/Duplicate/Delete/Paste callout menu
        let menuInteraction = UIEditMenuInteraction(delegate: self)
        addInteraction(menuInteraction)
        editMenuInteraction = menuInteraction
    }
    
    func syncLassoGestureMode() {
        if isLassoToolSelected {
            drawingGestureRecognizer.isEnabled = false
        } else {
            if !drawingGestureRecognizer.isEnabled {
                drawingGestureRecognizer.isEnabled = true
            }
        }
    }
    
    func clearLassoSelection() {
        selectedStrokeIndices.removeAll()
        activeCornerDrag = nil
        isMovingSelectedStrokes = false
        isTransformingSelection = false
        tappedInsideExistingSelectionOnBegan = false
        squareDrawStartPoint = nil
        freeLassoPoints.removeAll()
        initialFreeLassoPolygon.removeAll()
        lassoOverlay.activeLassoPoints = []
        lassoOverlay.activeSquareRect = nil
        lassoOverlay.committedFreeLassoPolygon = []
        lassoOverlay.selectionBounds = nil
        lassoOverlay.showCornerHandles = false
        lassoOverlay.previewStrokes = []
        dismissSystemEditMenu()
    }
    
    // MARK: - Built-In UIKit UIEditMenuInteraction (Cut / Copy / Duplicate / Delete / Paste)
    
    private func presentSystemSelectionMenu() {
        guard !selectedStrokeIndices.isEmpty, let selBounds = lassoOverlay.selectionBounds else {
            dismissSystemEditMenu()
            return
        }
        _ = becomeFirstResponder()
        let topAnchor = CGPoint(x: selBounds.midX, y: max(selBounds.minY, 8))
        let config = UIEditMenuConfiguration(
            identifier: Self.selectionMenuIdentifier,
            sourcePoint: topAnchor
        )
        config.preferredArrowDirection = . automatic
        isEditMenuVisible = true
        editMenuInteraction?.presentEditMenu(with: config)
    }
    
    private func presentSystemPasteOnlyMenu(at point: CGPoint) {
        guard !Self.copiedStrokesClipboard.isEmpty else {
            dismissSystemEditMenu()
            return
        }
        pasteTargetPoint = point
        _ = becomeFirstResponder()
        let config = UIEditMenuConfiguration(
            identifier: Self.pasteOnlyMenuIdentifier,
            sourcePoint: point
        )
        config.preferredArrowDirection = .automatic
        isEditMenuVisible = true
        editMenuInteraction?.presentEditMenu(with: config)
    }
    
    private func dismissSystemEditMenu() {
        if isEditMenuVisible {
            editMenuInteraction?.dismissMenu()
            isEditMenuVisible = false
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if isLassoToolSelected {
            if !selectedStrokeIndices.isEmpty {
                if action == #selector(cut(_:)) ||
                   action == #selector(copy(_:)) ||
                   action == #selector(delete(_:)) {
                    return true
                }
            } else if !Self.copiedStrokesClipboard.isEmpty {
                if action == #selector(paste(_:)) {
                    return true
                }
            }
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func cut(_ sender: Any?) {
        copySelectedStrokes()
        deleteSelectedStrokes(actionName: "Cut Selection")
    }
    
    override func copy(_ sender: Any?) {
        copySelectedStrokes()
        dismissSystemEditMenu()
    }
    
    override func paste(_ sender: Any?) {
        pasteCopiedStrokes()
    }
    
    override func delete(_ sender: Any?) {
        deleteSelectedStrokes(actionName: "Delete Selection")
    }
    
    private func copySelectedStrokes() {
        let strokes = selectedStrokeIndices.compactMap { idx -> PKStroke? in
            guard idx < drawing.strokes.count else { return nil }
            return drawing.strokes[idx]
        }
        guard !strokes.isEmpty else { return }
        Self.copiedStrokesClipboard = strokes
        Self.copiedFreeLassoPolygonClipboard = lassoOverlay.committedFreeLassoPolygon
    }
    
    private func deleteSelectedStrokes(actionName: String) {
        guard !selectedStrokeIndices.isEmpty else { return }
        let oldDrawing = drawing
        let selectedSet = Set(selectedStrokeIndices)
        let remaining = oldDrawing.strokes.enumerated().compactMap { i, s in
            selectedSet.contains(i) ? nil : s
        }
        let newDrawing = PKDrawing(strokes: remaining)
        clearLassoSelection()
        applyDrawingWithUndo(from: oldDrawing, to: newDrawing, actionName: actionName)
    }
    
    private func duplicateSelectedStrokes() {
        let strokes = selectedStrokeIndices.compactMap { idx -> PKStroke? in
            guard idx < drawing.strokes.count else { return nil }
            return drawing.strokes[idx]
        }
        guard !strokes.isEmpty else { return }
        let oldDrawing = drawing
        let dx: CGFloat = 24
        let dy: CGFloat = 24
        let offsetTransform = CGAffineTransform(translationX: dx, y: dy)
        let duplicated = PKDrawing(strokes: strokes).transformed(using: offsetTransform).strokes
        
        var allStrokes = oldDrawing.strokes
        let startIdx = allStrokes.count
        allStrokes.append(contentsOf: duplicated)
        let newIndices = Array(startIdx..<(startIdx + duplicated.count))
        let newDrawing = PKDrawing(strokes: allStrokes)
        
        let shiftedPolygon: [CGPoint]?
        if lassoMode == .free {
            if !lassoOverlay.committedFreeLassoPolygon.isEmpty {
                shiftedPolygon = lassoOverlay.committedFreeLassoPolygon.map {
                    CGPoint(x: $0.x + dx, y: $0.y + dy)
                }
            } else {
                shiftedPolygon = Self.generateOrganicFreeLassoContour(for: duplicated)
            }
        } else {
            shiftedPolygon = nil
        }
        
        applyDrawingWithUndo(from: oldDrawing, to: newDrawing, actionName: "Duplicate Selection")
        updateSelectionState(indices: newIndices, customFreePolygon: shiftedPolygon)
        presentSystemSelectionMenu()
    }
    
    private func pasteCopiedStrokes() {
        let clipboard = Self.copiedStrokesClipboard
        guard !clipboard.isEmpty else { return }
        let oldDrawing = drawing
        let clipDrawing = PKDrawing(strokes: clipboard)
        let clipBounds = clipDrawing.bounds
        let targetCenter = selectedStrokeIndices.isEmpty
            ? pasteTargetPoint
            : CGPoint(x: clipBounds.midX + 24, y: clipBounds.midY + 24)
        let dx = targetCenter.x - clipBounds.midX
        let dy = targetCenter.y - clipBounds.midY
        let translation = CGAffineTransform(translationX: dx, y: dy)
        let pastedStrokes = clipDrawing.transformed(using: translation).strokes
        
        var allStrokes = oldDrawing.strokes
        let startIdx = allStrokes.count
        allStrokes.append(contentsOf: pastedStrokes)
        let newIndices = Array(startIdx..<(startIdx + pastedStrokes.count))
        let newDrawing = PKDrawing(strokes: allStrokes)
        
        let contour: [CGPoint]?
        if lassoMode == .free {
            if !Self.copiedFreeLassoPolygonClipboard.isEmpty {
                // Shift the copied freehand polygon by the exact same (dx, dy) translation!
                contour = Self.copiedFreeLassoPolygonClipboard.map {
                    $0.applying(translation)
                }
            } else {
                // Or generate an organic contour using the transformed points of the pasted strokes
                contour = Self.generateOrganicFreeLassoContour(for: pastedStrokes)
            }
        } else {
            contour = nil
        }
        
        applyDrawingWithUndo(from: oldDrawing, to: newDrawing, actionName: "Paste Strokes")
        updateSelectionState(indices: newIndices, customFreePolygon: contour)
        presentSystemSelectionMenu()
    }
    
    // MARK: - Pencil Touch Routing (Hold-to-Snap & Custom Lasso)
    
    private func handlePencilBegan(at point: CGPoint, timestamp: TimeInterval) {
        configureEnclosingDocumentScrollViewForFingerOnlyScrolling()
        holdTimer?.invalidate()
        holdTimer = nil
        didSnapDuringCurrentTouch = false
        pendingSnappedDrawing = nil
        
        if isLassoToolSelected {
            handleLassoPencilBegan(at: point)
            return
        }
        
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
        if isLassoToolSelected {
            handleLassoPencilMoved(to: point)
            return
        }
        
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
    
    private func handlePencilEnded(at point: CGPoint, timestamp: TimeInterval) {
        if isLassoToolSelected {
            handleLassoPencilEnded(at: point)
            return
        }
        finishPencilStrokeOrCancel()
    }
    
    private func handlePencilCancelled() {
        if isLassoToolSelected {
            if isTransformingSelection {
                drawing = preTransformDrawing
                isTransformingSelection = false
                lassoOverlay.previewStrokes = []
            }
            activeCornerDrag = nil
            isMovingSelectedStrokes = false
            squareDrawStartPoint = nil
            freeLassoPoints.removeAll()
            lassoOverlay.activeLassoPoints = []
            lassoOverlay.activeSquareRect = nil
            return
        }
        finishPencilStrokeOrCancel()
    }
    
    private func finishPencilStrokeOrCancel() {
        holdTimer?.invalidate()
        holdTimer = nil
        capturedPoints.removeAll()
        capturedTimestamps.removeAll()
        
        if let snapped = pendingSnappedDrawing {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.drawing != snapped {
                    self.drawing = snapped
                }
                self.onShapeSnapped?(snapped)
                self.pendingSnappedDrawing = nil
                self.didSnapDuringCurrentTouch = false
            }
        }
    }
    
    // MARK: - Notability-Style Apple-Pencil-Only Lasso Selection, Tap-to-Select, Tap-Away Deselect, Move & Resize
    
    private func beginInteractiveSelectionTransform(currentBounds: CGRect) {
        preTransformDrawing = drawing
        initialSelectionBounds = currentBounds
        initialFreeLassoPolygon = lassoOverlay.committedFreeLassoPolygon
        isTransformingSelection = true
        dismissSystemEditMenu()
        
        let selectedSet = Set(selectedStrokeIndices)
        var unselected: [PKStroke] = []
        var selected: [PKStroke] = []
        for (i, stroke) in preTransformDrawing.strokes.enumerated() {
            if selectedSet.contains(i) {
                selected.append(stroke)
            } else {
                unselected.append(stroke)
            }
        }
        unselectedStrokesDuringTransform = unselected
        originalSelectedStrokes = selected
        currentTransformedSelectedStrokes = selected
        
        // Immediately remove selected strokes from the underlying PKCanvasView so they do NOT remain
        // at their original position while the user moves or resizes them in the overlay!
        drawing = PKDrawing(strokes: unselected)
        lassoOverlay.previewStrokes = selected
    }
    
    private func handleLassoPencilBegan(at point: CGPoint) {
        pencilTouchDownPoint = point
        didMoveSignificantlyDuringLassoTouch = false
        tappedInsideExistingSelectionOnBegan = false
        
        // Record whether the user currently had an active selection or open Paste popup BEFORE this touch began.
        // If they did, and this touch turns out to be a tap on empty canvas, we ONLY deselect / dismiss the menu!
        hadSelectionOrMenuOnTouchBegan = (!selectedStrokeIndices.isEmpty || isEditMenuVisible)
        
        // 1. Check if Apple Pencil touched one of the 4 corner resize handles (Square Lasso mode)
        if let corner = lassoOverlay.hitTestCorner(at: point),
           !selectedStrokeIndices.isEmpty,
           let currentBounds = lassoOverlay.selectionBounds {
            activeCornerDrag = corner
            isMovingSelectedStrokes = false
            beginInteractiveSelectionTransform(currentBounds: currentBounds)
            return
        }
        
        // 2. Check if Apple Pencil touched inside existing selection (freehand polygon or bounds) to move or toggle menu
        if !selectedStrokeIndices.isEmpty,
           let currentBounds = lassoOverlay.selectionBounds,
           lassoOverlay.containsSelectionPoint(point) {
            activeCornerDrag = nil
            isMovingSelectedStrokes = true
            tappedInsideExistingSelectionOnBegan = true
            moveStartPoint = point
            beginInteractiveSelectionTransform(currentBounds: currentBounds)
            return
        }
        
        // 3. Otherwise clear any active selection/menu and prepare for either a new drag-lasso or a tap
        clearLassoSelection()
        if lassoMode == .square {
            squareDrawStartPoint = point
            lassoOverlay.activeLassoPoints = []
            lassoOverlay.activeSquareRect = CGRect(origin: point, size: .zero)
        } else {
            squareDrawStartPoint = nil
            lassoOverlay.activeSquareRect = nil
            freeLassoPoints = [point]
            lassoOverlay.activeLassoPoints = [point]
        }
    }
    
    private func handleLassoPencilMoved(to point: CGPoint) {
        if hypot(point.x - pencilTouchDownPoint.x, point.y - pencilTouchDownPoint.y) > 4.5 {
            didMoveSignificantlyDuringLassoTouch = true
        }
        
        if let corner = activeCornerDrag {
            applyCornerResize(corner: corner, to: point)
            return
        }
        
        if isMovingSelectedStrokes {
            let dx = point.x - moveStartPoint.x
            let dy = point.y - moveStartPoint.y
            let translation = CGAffineTransform(translationX: dx, y: dy)
            updateLiveTransformPreview(translation)
            lassoOverlay.selectionBounds = initialSelectionBounds.offsetBy(dx: dx, dy: dy)
            if !initialFreeLassoPolygon.isEmpty {
                lassoOverlay.committedFreeLassoPolygon = initialFreeLassoPolygon.map {
                    CGPoint(x: $0.x + dx, y: $0.y + dy)
                }
            }
            return
        }
        
        if lassoMode == .square, let start = squareDrawStartPoint {
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            lassoOverlay.activeSquareRect = rect
        } else if lassoMode == .free {
            freeLassoPoints.append(point)
            lassoOverlay.activeLassoPoints = freeLassoPoints
        }
    }
    
    private func handleLassoPencilEnded(at point: CGPoint) {
        if activeCornerDrag != nil || isMovingSelectedStrokes {
            let wasTapOnlyInsideSelection = tappedInsideExistingSelectionOnBegan && !didMoveSignificantlyDuringLassoTouch
            finishInteractiveSelectionTransform(wasZeroMovementTap: wasTapOnlyInsideSelection)
            activeCornerDrag = nil
            isMovingSelectedStrokes = false
            tappedInsideExistingSelectionOnBegan = false
            presentSystemSelectionMenu()
            return
        }
        
        // Check if the user simply tapped with the Apple Pencil (movement <= 7pt)
        let totalDisplacement = hypot(point.x - pencilTouchDownPoint.x, point.y - pencilTouchDownPoint.y)
        if !didMoveSignificantlyDuringLassoTouch && totalDisplacement <= 7.0 {
            lassoOverlay.activeSquareRect = nil
            lassoOverlay.activeLassoPoints = []
            squareDrawStartPoint = nil
            freeLassoPoints.removeAll()
            
            // Hit-test if the Apple Pencil tapped directly on a stroke
            if let hitIndex = hitTestStroke(at: point) {
                let tappedStroke = drawing.strokes[hitIndex]
                let freeContour = lassoMode == .free
                    ? Self.generateOrganicFreeLassoContour(for: [tappedStroke])
                    : nil
                updateSelectionState(indices: [hitIndex], customFreePolygon: freeContour)
                presentSystemSelectionMenu()
            } else {
                // Tapped on empty canvas (no strokes at this location):
                // - If we had an active selection (or open Paste popup) when this tap started,
                //   this 1st tap ONLY deselects / dismisses (just like Notability).
                // - Only on a 2nd tap on empty canvas (when nothing was selected and no menu was open)
                //   do we show the built-in system "Paste" popup!
                clearLassoSelection()
                if !hadSelectionOrMenuOnTouchBegan && !Self.copiedStrokesClipboard.isEmpty {
                    presentSystemPasteOnlyMenu(at: point)
                }
            }
            hadSelectionOrMenuOnTouchBegan = false
            return
        }
        
        hadSelectionOrMenuOnTouchBegan = false
        
        if lassoMode == .square, let rect = lassoOverlay.activeSquareRect {
            lassoOverlay.activeSquareRect = nil
            squareDrawStartPoint = nil
            guard rect.width > 6 || rect.height > 6 else { return }
            selectStrokesInRect(rect)
        } else if lassoMode == .free {
            let pts = freeLassoPoints
            freeLassoPoints.removeAll()
            lassoOverlay.activeLassoPoints = []
            guard pts.count >= 3 else { return }
            selectStrokesInPolygon(pts)
        }
    }
    
    /// Helper to get the actual canvas-space coordinate of a `PKStrokePoint` (applying `stroke.transform`).
    private static func canvasLocation(of point: PKStrokePoint, in stroke: PKStroke) -> CGPoint {
        return point.location.applying(stroke.transform)
    }
    
    /// Finds the topmost stroke within `18pt` of the tapped point, accounting for `stroke.transform`.
    private func hitTestStroke(at point: CGPoint, tolerance: CGFloat = 18.0) -> Int? {
        var bestIndex: Int?
        var bestDistance: CGFloat = tolerance
        
        for (idx, stroke) in drawing.strokes.enumerated().reversed() {
            let expandedBounds = stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance)
            guard expandedBounds.contains(point) else { continue }
            
            for sample in stroke.path.interpolatedPoints(by: .distance(6)) {
                let sampleLoc = Self.canvasLocation(of: sample, in: stroke)
                let dist = hypot(sampleLoc.x - point.x, sampleLoc.y - point.y)
                if dist <= bestDistance {
                    bestDistance = dist
                    bestIndex = idx
                }
            }
            if bestIndex != nil {
                return bestIndex
            }
        }
        return bestIndex
    }
    
    /// Generates a smooth, rounded organic lasso contour around strokes in their actual transformed canvas coordinates!
    private static func generateOrganicFreeLassoContour(for strokes: [PKStroke], padding: CGFloat = 12.0) -> [CGPoint] {
        var allPoints: [CGPoint] = []
        for stroke in strokes {
            for pt in stroke.path.interpolatedPoints(by: .distance(10)) {
                // Apply `stroke.transform` so pasted/moved/duplicated strokes generate their
                // contour at their NEW canvas position rather than their original pre-transform path coordinates!
                let loc = canvasLocation(of: pt, in: stroke)
                for angleIdx in 0..<8 {
                    let angle = CGFloat(angleIdx) * (.pi / 4.0)
                    allPoints.append(CGPoint(
                        x: loc.x + cos(angle) * padding,
                        y: loc.y + sin(angle) * padding
                    ))
                }
            }
        }
        return computeConvexHull(of: allPoints)
    }
    
    /// Monotone chain convex hull algorithm to wrap a smooth freehand contour around tapped/pasted strokes.
    private static func computeConvexHull(of points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted {
            $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x
        }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
    
    @objc private func handleSelectionPinch(_ gesture: UIPinchGestureRecognizer) {
        guard isLassoToolSelected,
              !selectedStrokeIndices.isEmpty,
              let currentBounds = lassoOverlay.selectionBounds else { return }
        
        switch gesture.state {
        case .began:
            beginInteractiveSelectionTransform(currentBounds: currentBounds)
        case .changed:
            let scale = max(0.2, min(5.0, gesture.scale))
            let center = CGPoint(x: initialSelectionBounds.midX, y: initialSelectionBounds.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
            updateLiveTransformPreview(transform)
            lassoOverlay.selectionBounds = initialSelectionBounds.applying(transform)
            if !initialFreeLassoPolygon.isEmpty {
                lassoOverlay.committedFreeLassoPolygon = initialFreeLassoPolygon.map {
                    $0.applying(transform)
                }
            }
        case .ended, .cancelled:
            finishInteractiveSelectionTransform()
            presentSystemSelectionMenu()
        default:
            break
        }
    }
    
    private func applyCornerResize(corner: LassoSelectionOverlayView.CornerHandle, to point: CGPoint) {
        let orig = initialSelectionBounds
        guard orig.width > 4 && orig.height > 4 else { return }
        
        let anchor: CGPoint
        var newMinX = orig.minX
        var newMaxX = orig.maxX
        var newMinY = orig.minY
        var newMaxY = orig.maxY
        
        switch corner {
        case .topLeft:
            anchor = CGPoint(x: orig.maxX, y: orig.maxY)
            newMinX = min(point.x, anchor.x - 16)
            newMinY = min(point.y, anchor.y - 16)
        case .topRight:
            anchor = CGPoint(x: orig.minX, y: orig.maxY)
            newMaxX = max(point.x, anchor.x + 16)
            newMinY = min(point.y, anchor.y - 16)
        case .bottomLeft:
            anchor = CGPoint(x: orig.maxX, y: orig.minY)
            newMinX = min(point.x, anchor.x - 16)
            newMaxY = max(point.y, anchor.y + 16)
        case .bottomRight:
            anchor = CGPoint(x: orig.minX, y: orig.minY)
            newMaxX = max(point.x, anchor.x + 16)
            newMaxY = max(point.y, anchor.y + 16)
        }
        
        let newRect = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
        let sx = newRect.width / orig.width
        let sy = newRect.height / orig.height
        
        let transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
            .scaledBy(x: sx, y: sy)
            .translatedBy(x: -anchor.x, y: -anchor.y)
        
        updateLiveTransformPreview(transform)
        lassoOverlay.selectionBounds = newRect
    }
    
    private func updateLiveTransformPreview(_ transform: CGAffineTransform) {
        let transformedSubDrawing = PKDrawing(strokes: originalSelectedStrokes).transformed(using: transform)
        currentTransformedSelectedStrokes = transformedSubDrawing.strokes
        lassoOverlay.previewStrokes = currentTransformedSelectedStrokes
    }
    
    private func finishInteractiveSelectionTransform(wasZeroMovementTap: Bool = false) {
        guard isTransformingSelection else { return }
        isTransformingSelection = false
        lassoOverlay.previewStrokes = []
        
        if wasZeroMovementTap {
            drawing = preTransformDrawing
            return
        }
        
        let preservedFreePolygon = lassoOverlay.committedFreeLassoPolygon
        
        // Reconstruct full drawing with the transformed strokes in their original z-order indices
        var allStrokes = preTransformDrawing.strokes
        let selectedSet = Set(selectedStrokeIndices)
        var tIdx = 0
        for i in 0..<allStrokes.count where selectedSet.contains(i) {
            if tIdx < currentTransformedSelectedStrokes.count {
                allStrokes[i] = currentTransformedSelectedStrokes[tIdx]
                tIdx += 1
            }
        }
        
        let finalDrawing = PKDrawing(strokes: allStrokes)
        applyDrawingWithUndo(from: preTransformDrawing, to: finalDrawing, actionName: "Transform Selection")
        updateSelectionState(
            indices: selectedStrokeIndices,
            customFreePolygon: preservedFreePolygon.isEmpty ? nil : preservedFreePolygon
        )
    }
    
    private func selectStrokesInRect(_ rect: CGRect) {
        var matched: [Int] = []
        for (idx, stroke) in drawing.strokes.enumerated() {
            if rect.intersects(stroke.renderBounds) {
                matched.append(idx)
            }
        }
        updateSelectionState(indices: matched, customFreePolygon: nil)
        if !matched.isEmpty {
            presentSystemSelectionMenu()
        }
    }
    
    private func selectStrokesInPolygon(_ polygon: [CGPoint]) {
        let bezier = UIBezierPath()
        bezier.move(to: polygon[0])
        for pt in polygon.dropFirst() {
            bezier.addLine(to: pt)
        }
        bezier.close()
        
        var matched: [Int] = []
        for (idx, stroke) in drawing.strokes.enumerated() {
            let bounds = stroke.renderBounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if bezier.contains(center) {
                matched.append(idx)
                continue
            }
            for pt in stroke.path.interpolatedPoints(by: .distance(12)) {
                let sampleLoc = Self.canvasLocation(of: pt, in: stroke)
                if bezier.contains(sampleLoc) {
                    matched.append(idx)
                    break
                }
            }
        }
        // Keep the exact freehand loop drawn by the user!
        updateSelectionState(indices: matched, customFreePolygon: polygon)
        if !matched.isEmpty {
            presentSystemSelectionMenu()
        }
    }
    
    private func updateSelectionState(indices: [Int], customFreePolygon: [CGPoint]? = nil) {
        selectedStrokeIndices = indices
        guard !indices.isEmpty else {
            clearLassoSelection()
            return
        }
        var unionRect = CGRect.null
        for idx in indices where idx < drawing.strokes.count {
            unionRect = unionRect.union(drawing.strokes[idx].renderBounds)
        }
        if let freePoly = customFreePolygon, !freePoly.isEmpty {
            for pt in freePoly {
                unionRect = unionRect.union(CGRect(x: pt.x, y: pt.y, width: 1, height: 1))
            }
        }
        if !unionRect.isNull {
            lassoOverlay.selectionBounds = unionRect.insetBy(dx: -8, dy: -8)
            if lassoMode == .free {
                lassoOverlay.committedFreeLassoPolygon = customFreePolygon ?? []
                lassoOverlay.showCornerHandles = false
            } else {
                lassoOverlay.committedFreeLassoPolygon = []
                lassoOverlay.showCornerHandles = true
            }
        }
    }
    
    // MARK: - Hold-to-Snap Recognition
    
    private func attemptHoldToSnap() {
        guard !didSnapDuringCurrentTouch,
              !isLassoToolSelected,
              let inkingTool = tool as? PKInkingTool,
              capturedPoints.count >= 2 else { return }
        
        // Recognize 2D geometric shape if stroke length > 40pt
        guard let recognized = ShapeRecognitionEngine.recognizeShape(from: capturedPoints) else { return }
        
        didSnapDuringCurrentTouch = true
        holdTimer?.invalidate()
        holdTimer = nil
        
        let snappedStroke = ShapeRecognitionEngine.createPKStroke(from: recognized, tool: inkingTool)
        let previousDrawing = preStrokeDrawing
        
        // Build the new drawing by appending the clean geometric PKStroke onto preStrokeDrawing
        var updatedStrokes = previousDrawing.strokes
        updatedStrokes.append(snappedStroke)
        let snappedDrawing = PKDrawing(strokes: updatedStrokes)
        pendingSnappedDrawing = snappedDrawing
        
        // Cancel the active raw PencilKit touch stream FIRST so PencilKit aborts the freehand stroke
        drawingGestureRecognizer.isEnabled = false
        drawingGestureRecognizer.isEnabled = true
        
        // Apply immediately so the user sees the snapped shape right at 0.45s
        drawing = snappedDrawing
        onShapeSnapped?(snappedDrawing)
        
        // Also apply on the next runloop tick after PKTiledView finishes its async gesture cancellation cleanup,
        // ensuring PencilKit's rollback to preStrokeDrawing never erases our snapped shape.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.applyDrawingWithUndo(from: previousDrawing, to: snappedDrawing, actionName: "Snap Shape")
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    func enforcePendingSnappedDrawingIfNeeded() -> Bool {
        guard let snapped = pendingSnappedDrawing else { return false }
        if drawing != snapped {
            drawing = snapped
        }
        onShapeSnapped?(snapped)
        return true
    }
    
    private func applyDrawingWithUndo(from oldDrawing: PKDrawing, to newDrawing: PKDrawing, actionName: String) {
        if drawing != newDrawing {
            drawing = newDrawing
        }
        onShapeSnapped?(newDrawing)
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.pendingSnappedDrawing = nil
            target.didSnapDuringCurrentTouch = false
            target.clearLassoSelection()
            target.applyDrawingWithUndo(from: newDrawing, to: oldDrawing, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }
}

extension FixedCanvasView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        if let id = configuration.identifier as? NSString, id == Self.selectionMenuIdentifier {
            let cutAction = UIAction(title: "Cut") { [weak self] _ in
                self?.cut(nil)
            }
            let copyAction = UIAction(title: "Copy") { [weak self] _ in
                self?.copy(nil)
            }
            let duplicateAction = UIAction(title: "Duplicate") { [weak self] _ in
                self?.duplicateSelectedStrokes()
            }
            let deleteAction = UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in
                self?.delete(nil)
            }
            return UIMenu(children: [cutAction, copyAction, duplicateAction, deleteAction])
        } else if let id = configuration.identifier as? NSString, id == Self.pasteOnlyMenuIdentifier {
            let pasteAction = UIAction(title: "Paste") { [weak self] _ in
                self?.paste(nil)
            }
            return UIMenu(children: [pasteAction])
        }
        return nil
    }
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        if let id = configuration.identifier as? NSString,
           id == Self.selectionMenuIdentifier,
           let selBounds = lassoOverlay.selectionBounds {
            return selBounds
        }
        return CGRect(x: pasteTargetPoint.x - 2, y: pasteTargetPoint.y - 2, width: 4, height: 4)
    }
    
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willDismissMenuFor configuration: UIEditMenuConfiguration,
        animator: any UIEditMenuInteractionAnimating
    ) {
        isEditMenuVisible = false
    }
}

extension FixedCanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Never allow the enclosing UIScrollView's panGestureRecognizer to recognize simultaneously
        // with our Apple Pencil touch observer (`touchObserverGesture`).
        if (gestureRecognizer === touchObserverGesture && otherGestureRecognizer.view is UIScrollView) ||
           (otherGestureRecognizer === touchObserverGesture && gestureRecognizer.view is UIScrollView) {
            return false
        }
        if gestureRecognizer === touchObserverGesture || otherGestureRecognizer === touchObserverGesture {
            return true
        }
        return false
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pinchGesture {
            return isLassoToolSelected && !selectedStrokeIndices.isEmpty && gestureRecognizer.numberOfTouches >= 2
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

struct ExamCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var currentTool: PKTool
    var lassoMode: LassoMode = .free
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
            if let fixed = canvasView as? FixedCanvasView {
                if fixed.enforcePendingSnappedDrawingIfNeeded() || fixed.isTransformingSelection {
                    return
                }
            }
            commitDrawing(canvasView)
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Guard against recursive events triggered by makeUIView / updateUIView
            guard !isUpdatingFromSwiftUI else { return }
            if let fixed = canvasView as? FixedCanvasView {
                if fixed.didSnapDuringCurrentTouch {
                    _ = fixed.enforcePendingSnappedDrawingIfNeeded()
                    return
                }
                if fixed.isTransformingSelection {
                    return
                }
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
        canvasView.installShapeAndLassoObservers()
        canvasView.lassoMode = lassoMode
        let isLasso = (currentTool is PKLassoTool)
        canvasView.isLassoToolSelected = isLasso
        canvasView.onShapeSnapped = { [weak canvasView] snappedDrawing in
            guard let canvasView = canvasView else { return }
            context.coordinator.isUsingTool = false
            context.coordinator.lastCanvasDrawing = snappedDrawing
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
        
        // Never assign PKLassoTool directly to PKCanvasView.tool—otherwise PKSelectionGestureView
        // activates its built-in freehand lasso simultaneously and duplicates strokes.
        if !isLasso {
            canvasView.tool = currentTool
        }
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        let isLasso = (currentTool is PKLassoTool)
        
        if let fixedCanvas = uiView as? FixedCanvasView {
            fixedCanvas.customUndoManager = undoManager
            fixedCanvas.lassoMode = lassoMode
            fixedCanvas.isLassoToolSelected = isLasso
            if fixedCanvas.didSnapDuringCurrentTouch || fixedCanvas.isTransformingSelection {
                return
            }
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
        
        // Only update PKCanvasView.tool for non-lasso tools so PKSelectionGestureView never interferes
        if !isLasso && !context.coordinator.isSameTool(uiView.tool, currentTool) {
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
