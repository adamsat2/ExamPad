//
//  AssessmentManager.swift
//  ExamPad
//

import Foundation
import Combine
import AutomaticAssessmentConfiguration
import UIKit
import UserNotifications

/// Runtime hooks and state used to enforce full-screen lock and block window corner-swipe / resize gestures
/// while `isLocked == true` (from exam entry until the user submits the exam AND returns to the home screen).
enum ExamLockdownState {
    @MainActor static var isLocked: Bool = false
    @MainActor static var lockedFullScreenSize: CGSize = CGSize(width: 1366, height: 1024)
    @MainActor static var isRequestingFullScreenActivation: Bool = false
    
    private static var hasSwizzledSizeRestrictions = false
    
    @MainActor
    static func installLockdownRuntimeSupport() {
        _ = swizzleOnce
    }
    
    private static let swizzleOnce: Void = {
        // 1. Swizzle UIViewController.preferredScreenEdgesDeferringSystemGestures -> .all when locked
        let vcClass: AnyClass = UIViewController.self
        let origEdgeSel = #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures)
        let swizzledEdgeSel = #selector(UIViewController.exampad_preferredScreenEdgesDeferringSystemGestures)
        if let origMethod = class_getInstanceMethod(vcClass, origEdgeSel),
           let swizzledMethod = class_getInstanceMethod(vcClass, swizzledEdgeSel) {
            method_exchangeImplementations(origMethod, swizzledMethod)
        }
        
        // 2. Swizzle UIViewController._multitaskingDragExclusionRects -> full-screen & corner exclusion rects when locked
        //    In iPadOS Windowed Mode, _UISystemAppearanceManager.updateMultitaskingDragExclusionRects queries this
        //    and sends the rects to SpringBoard via UIMutableApplicationSceneClientSettings.multitaskingDragExclusionRects,
        //    blocking the corner-swipe window shrink gesture across all 4 corners and edges.
        let origExclusionSel = NSSelectorFromString("_multitaskingDragExclusionRects")
        let swizzledExclusionSel = #selector(UIViewController.exampad_multitaskingDragExclusionRects)
        if let origMethod = class_getInstanceMethod(vcClass, origExclusionSel),
           let swizzledMethod = class_getInstanceMethod(vcClass, swizzledExclusionSel) {
            method_exchangeImplementations(origMethod, swizzledMethod)
        }
        
        // 3. Hook UIApplication.supportsMultiwindow so activateSceneSessionForRequest:errorHandler:
        //    does not early-return when requesting _UIWindowSceneFullscreenPlacement on the existing scene session.
        let appClass: AnyClass = UIApplication.self
        let multiwindowSel = NSSelectorFromString("supportsMultiwindow")
        if let method = class_getInstanceMethod(appClass, multiwindowSel) {
            typealias SupportsMultiwindowIMP = @convention(c) (AnyObject, Selector) -> Bool
            let origImp = method_getImplementation(method)
            let origFn = unsafeBitCast(origImp, to: SupportsMultiwindowIMP.self)
            let block: @convention(block) (AnyObject) -> Bool = { obj in
                if Thread.isMainThread {
                    let requesting = MainActor.assumeIsolated {
                        ExamLockdownState.isRequestingFullScreenActivation
                    }
                    if requesting {
                        return true
                    }
                }
                return origFn(obj, multiwindowSel)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        
        // 4. Hook _UISceneLayoutPreferenceBuilder (used directly by SwiftUI's _UISceneHostingController
        //    and _UISceneLayoutPreferencesController.updateLayoutPreferences:) so neither SwiftUI nor UIKit
        //    can overwrite minimum/maximum window dimensions while locked.
        if let builderClass = NSClassFromString("_UISceneLayoutPreferenceBuilder") {
            typealias SetCGFloatIMP = @convention(c) (AnyObject, Selector, CGFloat) -> Void
            
            let hookDimension: (String, Bool) -> Void = { selName, isWidth in
                let sel = NSSelectorFromString(selName)
                guard let method = class_getInstanceMethod(builderClass, sel) else { return }
                let origImp = method_getImplementation(method)
                let origFn = unsafeBitCast(origImp, to: SetCGFloatIMP.self)
                let block: @convention(block) (AnyObject, CGFloat) -> Void = { obj, val in
                    if Thread.isMainThread {
                        let (locked, lockedSize) = MainActor.assumeIsolated {
                            (ExamLockdownState.isLocked, ExamLockdownState.lockedFullScreenSize)
                        }
                        if locked {
                            origFn(obj, sel, isWidth ? lockedSize.width : lockedSize.height)
                            return
                        }
                    }
                    origFn(obj, sel, val)
                }
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
            
            hookDimension("setMinimumWidth:", true)
            hookDimension("setMinimumHeight:", false)
            hookDimension("setMaximumWidth:", true)
            hookDimension("setMaximumHeight:", false)
        }
        
        // 5. Hook _UISceneSizeRestrictionsLayoutPreferencesImpl (the concrete backing implementation of UISceneSizeRestrictions)
        if let implClass = NSClassFromString("_UISceneSizeRestrictionsLayoutPreferencesImpl") {
            installSizeHooks(on: implClass)
        }
    }()
    
    @MainActor
    static func installSizeRestrictionsHookIfNeeded(on restrictions: UISceneSizeRestrictions) {
        guard !hasSwizzledSizeRestrictions,
              let implClass = object_getClass(restrictions) else { return }
        hasSwizzledSizeRestrictions = true
        installSizeHooks(on: implClass)
    }
    
    private static func installSizeHooks(on targetClass: AnyClass) {
        typealias SetSizeIMP = @convention(c) (AnyObject, Selector, CGSize) -> Void
        typealias SetBoolIMP = @convention(c) (AnyObject, Selector, Bool) -> Void
        
        let minSel = #selector(setter: UISceneSizeRestrictions.minimumSize)
        if let minMethod = class_getInstanceMethod(targetClass, minSel) {
            let origImp = method_getImplementation(minMethod)
            let origSetMin = unsafeBitCast(origImp, to: SetSizeIMP.self)
            let block: @convention(block) (AnyObject, CGSize) -> Void = { obj, size in
                if Thread.isMainThread {
                    let (locked, lockedSize) = MainActor.assumeIsolated {
                        (ExamLockdownState.isLocked, ExamLockdownState.lockedFullScreenSize)
                    }
                    if locked {
                        origSetMin(obj, minSel, lockedSize)
                        return
                    }
                }
                origSetMin(obj, minSel, size)
            }
            method_setImplementation(minMethod, imp_implementationWithBlock(block))
        }
        
        let maxSel = #selector(setter: UISceneSizeRestrictions.maximumSize)
        if let maxMethod = class_getInstanceMethod(targetClass, maxSel) {
            let origImp = method_getImplementation(maxMethod)
            let origSetMax = unsafeBitCast(origImp, to: SetSizeIMP.self)
            let block: @convention(block) (AnyObject, CGSize) -> Void = { obj, size in
                if Thread.isMainThread {
                    let (locked, lockedSize) = MainActor.assumeIsolated {
                        (ExamLockdownState.isLocked, ExamLockdownState.lockedFullScreenSize)
                    }
                    if locked {
                        origSetMax(obj, maxSel, lockedSize)
                        return
                    }
                }
                origSetMax(obj, maxSel, size)
            }
            method_setImplementation(maxMethod, imp_implementationWithBlock(block))
        }
        
        let fullScreenSel = #selector(setter: UISceneSizeRestrictions.allowsFullScreen)
        if let fsMethod = class_getInstanceMethod(targetClass, fullScreenSel) {
            let origImp = method_getImplementation(fsMethod)
            let origSetFS = unsafeBitCast(origImp, to: SetBoolIMP.self)
            let block: @convention(block) (AnyObject, Bool) -> Void = { obj, allowed in
                if Thread.isMainThread {
                    let locked = MainActor.assumeIsolated { ExamLockdownState.isLocked }
                    if locked {
                        origSetFS(obj, fullScreenSel, true)
                        return
                    }
                }
                origSetFS(obj, fullScreenSel, allowed)
            }
            method_setImplementation(fsMethod, imp_implementationWithBlock(block))
        }
    }
    
    /// Builds an array of `NSValue(cgRect:)` rects covering the entire screen, window bounds, and all 4 corners
    /// so SpringBoard excludes the entire window and its corners from multitasking / corner-swipe resize gestures.
    static func exclusionRectValues(for bounds: CGRect) -> [NSValue] {
        let w = max(bounds.width, 1366)
        let h = max(bounds.height, 1366)
        let fullRect = CGRect(x: 0, y: 0, width: w, height: h)
        let expandedRect = fullRect.insetBy(dx: -300, dy: -300)
        let cornerSize: CGFloat = 350
        return [
            NSValue(cgRect: expandedRect),
            NSValue(cgRect: fullRect),
            // Top-left corner
            NSValue(cgRect: CGRect(x: -100, y: -100, width: cornerSize, height: cornerSize)),
            // Top-right corner
            NSValue(cgRect: CGRect(x: w - cornerSize + 100, y: -100, width: cornerSize, height: cornerSize)),
            // Bottom-left corner
            NSValue(cgRect: CGRect(x: -100, y: h - cornerSize + 100, width: cornerSize, height: cornerSize)),
            // Bottom-right corner
            NSValue(cgRect: CGRect(x: w - cornerSize + 100, y: h - cornerSize + 100, width: cornerSize, height: cornerSize))
        ]
    }
}

extension UIViewController {
    @objc func exampad_preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        if Thread.isMainThread {
            let locked = MainActor.assumeIsolated { ExamLockdownState.isLocked }
            if locked {
                return .all
            }
        }
        return exampad_preferredScreenEdgesDeferringSystemGestures()
    }
    
    @objc func exampad_multitaskingDragExclusionRects() -> NSArray {
        if Thread.isMainThread {
            let (locked, lockedSize) = MainActor.assumeIsolated {
                (ExamLockdownState.isLocked, ExamLockdownState.lockedFullScreenSize)
            }
            if locked {
                let baseBounds = viewIfLoaded?.bounds ?? CGRect(origin: .zero, size: lockedSize)
                return ExamLockdownState.exclusionRectValues(for: baseBounds) as NSArray
            }
        }
        return exampad_multitaskingDragExclusionRects()
    }
}

/// Manages device locking, full-screen window enforcement, corner-swipe & edge gesture blocking,
/// tamper/exit detection, and notification suppression during an exam.
@MainActor
final class AssessmentManager: NSObject, ObservableObject {
    @Published private(set) var isExamLocked: Bool = false
    @Published private(set) var isHardwareAssessmentActive: Bool = false
    @Published var tamperViolationCount: Int = 0
    @Published var showTamperViolationAlert: Bool = false
    @Published var isAppInactiveDuringExam: Bool = false
    @Published private(set) var lockedScreenSize: CGSize = UIScreen.main.bounds.size
    
    static let defaultMinimumWindowSize = CGSize(width: 600, height: 500)
    static let unrestrictedMaximumWindowSize = CGSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    )
    
    private var assessmentSession: AEAssessmentSession?
    private var orientationObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var geometryKVOObservations: [NSKeyValueObservation] = []
    private var windowLockTimer: Timer?
    private var lastFullScreenActivationAttempt: Date = .distantPast
    
    override init() {
        super.init()
        ExamLockdownState.installLockdownRuntimeSupport()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Configures initial window resizability on the home screen (unlocked until an exam begins).
    func configureInitialWindowState() {
        if isExamLocked {
            lockWindowToFullScreen()
        } else {
            unlockWindowResizing()
        }
    }
    
    /// Clears only local iPad clipboard items without triggering Universal Clipboard ("Paste from MacBook") prompts.
    func clearLocalClipboardSafely() {
        UIPasteboard.general.setItems([], options: [.localOnly: true])
    }
    
    /// Locks the iPad into Assessment Mode, forces the app window into full-screen mode,
    /// disables window resizing and corner-swipe gestures, defers system edge gestures (`.all`),
    /// monitors for app-exit tampering, and blocks notifications until the exam is submitted
    /// AND the user returns to the home screen.
    func beginExamLockdown() {
        isExamLocked = true
        ExamLockdownState.isLocked = true
        tamperViolationCount = 0
        showTamperViolationAlert = false
        isAppInactiveDuringExam = false
        lastFullScreenActivationAttempt = .distantPast
        
        // 1. Clear local pasteboard only (prevents Universal Clipboard "Paste from MacBook Air" popup)
        clearLocalClipboardSafely()
        
        // 2. Suppress and clear notifications
        blockNotifications()
        
        // 3. Force window to full-screen & disable resizing + block corner-swipe & edge gestures
        lockWindowToFullScreen()
        
        // 4. Start monitoring app lifecycle for unauthorized exit / multitasking attempts
        startTamperMonitoring()
        
        // 5. Request Autonomous Single App Mode (Guided Access) if supervised / configured
        UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] success in
            Task { @MainActor [weak self] in
                if success {
                    self?.isHardwareAssessmentActive = true
                }
            }
        }
        
        // 6. Start Apple's AutomaticAssessmentConfiguration session
        if assessmentSession?.isActive != true {
            let configuration = AEAssessmentConfiguration()
            let session = AEAssessmentSession(configuration: configuration)
            session.delegate = self
            self.assessmentSession = session
            session.begin()
        }
    }
    
    /// Releases the device from Assessment Mode, stops tamper monitoring, unblocks notifications,
    /// and restores normal window resizability and corner gestures once the exam has been submitted
    /// AND the user returns to the home screen.
    func endExamLockdown() {
        isExamLocked = false
        ExamLockdownState.isLocked = false
        isHardwareAssessmentActive = false
        isAppInactiveDuringExam = false
        showTamperViolationAlert = false
        
        // 1. Stop tamper / exit monitoring & window lock enforcement
        stopTamperMonitoring()
        stopWindowLockEnforcement()
        
        // 2. End Assessment Session
        if let session = assessmentSession, session.isActive {
            session.end()
        }
        assessmentSession = nil
        
        // 3. Release Guided Access / Single App Mode if active
        UIAccessibility.requestGuidedAccessSession(enabled: false) { _ in }
        
        // 4. Restore window resizability and corner-swipe gestures now that the user is back on the home screen
        unlockWindowResizing()
        
        // 5. Unblock notifications
        unblockNotifications()
    }
    
    func dismissTamperAlert() {
        showTamperViolationAlert = false
    }
    
    // MARK: - Tamper / Exit Detection (Verifies Lockdown During Development & Production)
    
    private func startTamperMonitoring() {
        stopTamperMonitoring()
        
        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willDeactivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                // Blur exam contents immediately when multitasking switcher or Control Center is pulled
                self.isAppInactiveDuringExam = true
            }
        }
        
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                self.isAppInactiveDuringExam = true
                self.tamperViolationCount += 1
                self.showTamperViolationAlert = true
            }
        }
        
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                if self.isAppInactiveDuringExam {
                    self.isAppInactiveDuringExam = false
                }
                // Re-enforce full-screen window size and corner/edge gesture blocking upon returning
                self.applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
            }
        }
    }
    
    private func stopTamperMonitoring() {
        if let obs = willResignActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            willResignActiveObserver = nil
        }
        if let obs = didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
            didEnterBackgroundObserver = nil
        }
        if let obs = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            didBecomeActiveObserver = nil
        }
    }
    
    // MARK: - Window Locking, Full-Screen Transition & Corner-Swipe Gesture Blocking
    
    private func lockWindowToFullScreen() {
        applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
        
        // Reinforce full-screen geometry and exclusion rects across the transition into ActiveExamView
        for delay in [0.05, 0.2, 0.45, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isExamLocked else { return }
                self.applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
            }
        }
        
        if orientationObserver == nil {
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self, self.isExamLocked else { return }
                    self.applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
                }
            }
        }
        
        // Observe `effectiveGeometry` on every UIWindowScene so if the system or user attempts to resize
        // or exit full-screen during an active exam, we immediately re-assert full-screen mode.
        geometryKVOObservations.removeAll()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let obs = windowScene.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isExamLocked else { return }
                    self.applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
                }
            }
            geometryKVOObservations.append(obs)
        }
        
        windowLockTimer?.invalidate()
        windowLockTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.isExamLocked else { return }
                self.applyFullScreenWindowRestrictions(forceActivationIfNeeded: true)
            }
        }
    }
    
    private func stopWindowLockEnforcement() {
        if let obs = orientationObserver {
            NotificationCenter.default.removeObserver(obs)
            orientationObserver = nil
        }
        geometryKVOObservations.removeAll()
        windowLockTimer?.invalidate()
        windowLockTimer = nil
    }
    
    private func applyFullScreenWindowRestrictions(forceActivationIfNeeded: Bool = false) {
        guard isExamLocked else { return }
        ExamLockdownState.isLocked = true
        
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let screenBounds = windowScene.screen.bounds.size
            guard screenBounds.width > 0, screenBounds.height > 0 else { continue }
            
            ExamLockdownState.lockedFullScreenSize = screenBounds
            if lockedScreenSize != screenBounds {
                lockedScreenSize = screenBounds
            }
            
            // 1. Lock UISceneSizeRestrictions to full screen dimensions
            if let restrictions = windowScene.sizeRestrictions {
                ExamLockdownState.installSizeRestrictionsHookIfNeeded(on: restrictions)
                restrictions.allowsFullScreen = true
                restrictions.minimumSize = screenBounds
                restrictions.maximumSize = screenBounds
            }
            
            // 2. Disable window close/minimize behaviors
            windowScene.windowingBehaviors?.isClosable = false
            windowScene.windowingBehaviors?.isMiniaturizable = false
            
            // 3. Directly update _UISceneLayoutPreferencesController & FBSScene clientSettings
            //    (sets preferredMinimum/MaximumWidth/Height, multitaskingDragExclusionRects,
            //     screenEdgesDeferringSystemGestures = .all, wantsExclusiveForeground = true)
            updateSceneLayoutAndClientSettings(for: windowScene, locked: true, screenBounds: screenBounds)
            
            // 4. Request full-screen scene placement if not currently in full-screen
            let currentSceneSize = windowScene.coordinateSpace.bounds.size
            let isCurrentlyFullScreen = isWindowSceneFullScreen(windowScene)
                && abs(currentSceneSize.width - screenBounds.width) < 2
                && abs(currentSceneSize.height - screenBounds.height) < 2
            
            if !isCurrentlyFullScreen && forceActivationIfNeeded {
                requestFullScreenScenePlacement(for: windowScene)
            }
            
            // 5. Request geometry update for current interface orientation
            let currentOrientation = windowScene.interfaceOrientation
            let mask: UIInterfaceOrientationMask
            switch currentOrientation {
            case .landscapeLeft: mask = .landscapeLeft
            case .landscapeRight: mask = .landscapeRight
            case .portraitUpsideDown: mask = .portraitUpsideDown
            case .portrait: mask = .portrait
            default: mask = .all
            }
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            windowScene.requestGeometryUpdate(geometryPreferences) { _ in }
            
            // 6. Expand windows and trigger updates for screen-edge deferral & multitasking drag exclusion rects
            for window in windowScene.windows {
                if window.frame.size != screenBounds {
                    window.frame = windowScene.screen.bounds
                }
                updateGestureDeferralAndExclusionRectsRecursively(on: window.rootViewController)
            }
        }
    }
    
    private func unlockWindowResizing() {
        ExamLockdownState.isLocked = false
        
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let screenBounds = windowScene.screen.bounds.size
            if screenBounds.width > 0, screenBounds.height > 0, lockedScreenSize != screenBounds {
                lockedScreenSize = screenBounds
            }
            
            if let restrictions = windowScene.sizeRestrictions {
                ExamLockdownState.installSizeRestrictionsHookIfNeeded(on: restrictions)
                restrictions.allowsFullScreen = true
                restrictions.minimumSize = Self.defaultMinimumWindowSize
                restrictions.maximumSize = Self.unrestrictedMaximumWindowSize
            }
            
            windowScene.windowingBehaviors?.isClosable = true
            windowScene.windowingBehaviors?.isMiniaturizable = true
            
            updateSceneLayoutAndClientSettings(for: windowScene, locked: false, screenBounds: screenBounds)
            
            for window in windowScene.windows {
                updateGestureDeferralAndExclusionRectsRecursively(on: window.rootViewController)
            }
        }
    }
    
    /// Checks `-[UIWindowScene isFullScreen]` on iPadOS 26.
    private func isWindowSceneFullScreen(_ windowScene: UIWindowScene) -> Bool {
        let sel = NSSelectorFromString("isFullScreen")
        guard let method = class_getInstanceMethod(object_getClass(windowScene), sel) else {
            return windowScene.coordinateSpace.bounds.size == windowScene.screen.bounds.size
        }
        typealias IsFullScreenIMP = @convention(c) (AnyObject, Selector) -> Bool
        let fn = unsafeBitCast(method_getImplementation(method), to: IsFullScreenIMP.self)
        return fn(windowScene, sel)
    }
    
    /// Requests SpringBoard to transition the existing `UIWindowScene` session into True Full-Screen
    /// using `_UIWindowSceneFullscreenPlacement` (`UISSceneFullscreenPlacementConfiguration`).
    private func requestFullScreenScenePlacement(for windowScene: UIWindowScene) {
        let now = Date()
        guard now.timeIntervalSince(lastFullScreenActivationAttempt) >= 0.3 else { return }
        lastFullScreenActivationAttempt = now
        
        let options = UIWindowScene.ActivationRequestOptions()
        
        // Use UIKit's _UIWindowSceneFullscreenPlacement (which sets requestFullscreen = true
        // and creates UISSceneFullscreenPlacementConfiguration)
        let setPlacementSel = NSSelectorFromString("setPlacement:")
        if let m = class_getInstanceMethod(object_getClass(options), setPlacementSel) {
            typealias SetObjIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
            let setPlacementFn = unsafeBitCast(method_getImplementation(m), to: SetObjIMP.self)
            if let fullscreenPlacementClass = NSClassFromString("_UIWindowSceneFullscreenPlacement") as? NSObject.Type {
                let fullscreenPlacement = fullscreenPlacementClass.init()
                setPlacementFn(options, setPlacementSel, fullscreenPlacement)
            } else if let prominentClass = NSClassFromString("UIWindowSceneProminentPlacement") as AnyObject?,
                      prominentClass.responds(to: NSSelectorFromString("_largeProminentPlacement")),
                      let largePlacement = prominentClass.perform(NSSelectorFromString("_largeProminentPlacement"))?.takeUnretainedValue() {
                setPlacementFn(options, setPlacementSel, largePlacement)
            }
        }
        
        // Also set _preferredSizeCategory = 1 and _preserveLayout = false on UIWindowSceneActivationRequestOptions
        let sizeCatSel = NSSelectorFromString("_setPreferredSizeCategory:")
        if let m = class_getInstanceMethod(object_getClass(options), sizeCatSel) {
            typealias SetUIntIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
            let fn = unsafeBitCast(method_getImplementation(m), to: SetUIntIMP.self)
            fn(options, sizeCatSel, 1)
        }
        let preserveSel = NSSelectorFromString("_setPreserveLayout:")
        if let m = class_getInstanceMethod(object_getClass(options), preserveSel) {
            typealias SetBoolIMP = @convention(c) (AnyObject, Selector, Bool) -> Void
            let fn = unsafeBitCast(method_getImplementation(m), to: SetBoolIMP.self)
            fn(options, preserveSel, false)
        }
        
        let request = UISceneSessionActivationRequest(
            session: windowScene.session,
            userActivity: nil,
            options: options
        )
        
        ExamLockdownState.isRequestingFullScreenActivation = true
        UIApplication.shared.activateSceneSession(for: request) { _ in }
        ExamLockdownState.isRequestingFullScreenActivation = false
    }
    
    /// Updates both `_UISceneLayoutPreferencesController` and `FBSScene` `UIMutableApplicationSceneClientSettings`
    /// to lock/unlock window dimensions, corner-swipe multitasking drag exclusion rects, and edge gesture deferral.
    private func updateSceneLayoutAndClientSettings(
        for windowScene: UIWindowScene,
        locked: Bool,
        screenBounds: CGSize
    ) {
        let fbsSel = NSSelectorFromString("_FBSScene")
        guard windowScene.responds(to: fbsSel),
              let fbsScene = windowScene.perform(fbsSel)?.takeUnretainedValue() as AnyObject? else {
            return
        }
        
        let minW = locked ? screenBounds.width : Self.defaultMinimumWindowSize.width
        let minH = locked ? screenBounds.height : Self.defaultMinimumWindowSize.height
        let maxW = locked ? screenBounds.width : Self.unrestrictedMaximumWindowSize.width
        let maxH = locked ? screenBounds.height : Self.unrestrictedMaximumWindowSize.height
        
        // 1. Update _UISceneLayoutPreferencesController directly
        let prefsCtrlSel = NSSelectorFromString("_ui_layoutPreferencesController")
        if fbsScene.responds(to: prefsCtrlSel),
           let prefsCtrl = fbsScene.perform(prefsCtrlSel)?.takeUnretainedValue() as AnyObject? {
            let updatePrefsSel = NSSelectorFromString("updateLayoutPreferences:")
            if let m = class_getInstanceMethod(object_getClass(prefsCtrl), updatePrefsSel) {
                typealias UpdatePrefsIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
                let fn = unsafeBitCast(method_getImplementation(m), to: UpdatePrefsIMP.self)
                let block: @convention(block) (AnyObject) -> Void = { builder in
                    typealias SetCGFloatIMP = @convention(c) (AnyObject, Selector, CGFloat) -> Void
                    for (selName, value) in [
                        ("setMinimumWidth:", minW),
                        ("setMinimumHeight:", minH),
                        ("setMaximumWidth:", maxW),
                        ("setMaximumHeight:", maxH)
                    ] {
                        let sel = NSSelectorFromString(selName)
                        if let bm = class_getInstanceMethod(object_getClass(builder), sel) {
                            let setFn = unsafeBitCast(method_getImplementation(bm), to: SetCGFloatIMP.self)
                            setFn(builder, sel, value)
                        }
                    }
                }
                fn(prefsCtrl, updatePrefsSel, unsafeBitCast(block, to: AnyObject.self))
            }
        }
        
        // 2. Update UIMutableApplicationSceneClientSettings on FBSScene
        let updateUIClientSel = NSSelectorFromString("updateUIClientSettingsWithBlock:")
        if let m = class_getInstanceMethod(object_getClass(fbsScene), updateUIClientSel) {
            typealias UpdateClientIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
            let fn = unsafeBitCast(method_getImplementation(m), to: UpdateClientIMP.self)
            let exclusionRects: NSArray = locked
                ? (ExamLockdownState.exclusionRectValues(for: CGRect(origin: .zero, size: screenBounds)) as NSArray)
                : ([] as NSArray)
            let edgeMask: UInt = locked ? UIRectEdge.all.rawValue : 0
            
            let block: @convention(block) (AnyObject) -> Void = { clientSettings in
                guard let csClass = object_getClass(clientSettings) else { return }
                typealias SetCGFloatIMP = @convention(c) (AnyObject, Selector, CGFloat) -> Void
                typealias SetObjIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
                typealias SetUIntIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
                typealias SetBoolIMP = @convention(c) (AnyObject, Selector, Bool) -> Void
                
                for (selName, value) in [
                    ("setPreferredMinimumWidth:", minW),
                    ("setPreferredMinimumHeight:", minH),
                    ("setPreferredMaximumWidth:", maxW),
                    ("setPreferredMaximumHeight:", maxH)
                ] {
                    let sel = NSSelectorFromString(selName)
                    if let cm = class_getInstanceMethod(csClass, sel) {
                        let setFn = unsafeBitCast(method_getImplementation(cm), to: SetCGFloatIMP.self)
                        setFn(clientSettings, sel, value)
                    }
                }
                
                // Exclude entire window & all 4 corners from multitasking / corner-swipe resize gestures
                let dragSel = NSSelectorFromString("setMultitaskingDragExclusionRects:")
                if let cm = class_getInstanceMethod(csClass, dragSel) {
                    let setFn = unsafeBitCast(method_getImplementation(cm), to: SetObjIMP.self)
                    setFn(clientSettings, dragSel, exclusionRects)
                }
                
                // Defer system edge gestures on all 4 edges
                let edgeSel = NSSelectorFromString("setScreenEdgesDeferringSystemGestures:")
                if let cm = class_getInstanceMethod(csClass, edgeSel) {
                    let setFn = unsafeBitCast(method_getImplementation(cm), to: SetUIntIMP.self)
                    setFn(clientSettings, edgeSel, edgeMask)
                }
                
                // Request exclusive foreground during exam
                let exclusiveSel = NSSelectorFromString("setWantsExclusiveForeground:")
                if let cm = class_getInstanceMethod(csClass, exclusiveSel) {
                    let setFn = unsafeBitCast(method_getImplementation(cm), to: SetBoolIMP.self)
                    setFn(clientSettings, exclusiveSel, locked)
                }
            }
            fn(fbsScene, updateUIClientSel, unsafeBitCast(block, to: AnyObject.self))
        }
    }
    
    private func updateGestureDeferralAndExclusionRectsRecursively(on viewController: UIViewController?) {
        guard let vc = viewController else { return }
        vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
        
        let exclusionUpdateSel = NSSelectorFromString("_setNeedsUpdateOfMultitaskingDragExclusionRects")
        if vc.responds(to: exclusionUpdateSel) {
            _ = vc.perform(exclusionUpdateSel)
        }
        
        for child in vc.children {
            updateGestureDeferralAndExclusionRectsRecursively(on: child)
        }
        if let presented = vc.presentedViewController {
            updateGestureDeferralAndExclusionRectsRecursively(on: presented)
        }
    }
    
    // MARK: - Notification Blocking
    
    private func blockNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
    
    private func unblockNotifications() {
        UNUserNotificationCenter.current().delegate = self
    }
}

// MARK: - AEAssessmentSessionDelegate
extension AssessmentManager: AEAssessmentSessionDelegate {
    nonisolated func assessmentSessionDidBegin(_ session: AEAssessmentSession) {
        print("Successfully entered Assessment Mode.")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = true
        }
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, failedToBeginWithError error: Error) {
        print("Assessment Mode entitlement not active (using Edge Deferral + Tamper Lock fallback): \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = false
        }
    }
    
    nonisolated func assessmentSessionDidEnd(_ session: AEAssessmentSession) {
        print("Successfully exited Assessment Mode.")
        Task { @MainActor [weak self] in
            self?.isHardwareAssessmentActive = false
        }
    }
    
    nonisolated func assessmentSession(_ session: AEAssessmentSession, wasInterruptedWithError error: Error) {
        print("Assessment Mode was interrupted: \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isExamLocked {
                self.assessmentSession?.begin()
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AssessmentManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor [weak self] in
            let isLocked = self?.isExamLocked ?? false
            if isLocked {
                completionHandler([])
            } else {
                completionHandler([.banner, .list, .sound, .badge])
            }
        }
    }
}
