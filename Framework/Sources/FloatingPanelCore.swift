//
//  Copyright © 2018 Shin Yamamoto. All rights reserved.
//

import UIKit

///
/// FloatingPanel presentation model
///
class FloatingPanelCore: NSObject, UIGestureRecognizerDelegate {
    // MUST be a weak reference to prevent UI freeze on the presentation modally
    weak var viewcontroller: FloatingPanelController?

    let surfaceView: FloatingPanelSurfaceView
    let backdropView: FloatingPanelBackdropView
    let layoutAdapter: FloatingPanelLayoutAdapter
    let behaviorAdapter: FloatingPanelBehaviorAdapter

    weak var scrollView: UIScrollView? {
        didSet {
            oldValue?.panGestureRecognizer.removeTarget(self, action: nil)
            scrollView?.panGestureRecognizer.addTarget(self, action: #selector(handle(panGesture:)))
        }
    }

    private(set) var state: FloatingPanelState = .hidden {
        didSet {
            log.debug("state changed: \(oldValue) -> \(state)")
            if let vc = viewcontroller {
                vc.delegate?.floatingPanelDidChangePosition?(vc)
            }
        }
    }

    let panGestureRecognizer: FloatingPanelPanGestureRecognizer
    var isRemovalInteractionEnabled: Bool = false

    fileprivate var animator: UIViewPropertyAnimator?
    fileprivate var moveAnimator: NumericSpringAnimator?

    private var initialFrame: CGRect = .zero
    private var initialTranslationY: CGFloat = 0
    private var initialLocation: CGPoint = .nan

    var interactionInProgress: Bool = false
    var isDecelerating: Bool = false

    // Scroll handling
    private var initialScrollOffset: CGPoint = .zero
    private var stopScrollDeceleration: Bool = false
    private var scrollBouncable = false
    private var scrollIndictorVisible = false

    // MARK: - Interface

    init(_ vc: FloatingPanelController, layout: FloatingPanelLayout, behavior: FloatingPanelBehavior) {
        viewcontroller = vc

        surfaceView = FloatingPanelSurfaceView()
        surfaceView.backgroundColor = .white

        backdropView = FloatingPanelBackdropView()
        backdropView.backgroundColor = .black
        backdropView.alpha = 0.0

        self.layoutAdapter = FloatingPanelLayoutAdapter(vc: vc,
                                                        surfaceView: surfaceView,
                                                        backdropView: backdropView,
                                                        layout: layout)
        self.behaviorAdapter = FloatingPanelBehaviorAdapter(vc: vc, behavior: behavior)

        panGestureRecognizer = FloatingPanelPanGestureRecognizer()

        if #available(iOS 11.0, *) {
            panGestureRecognizer.name = "FloatingPanelSurface"
        }

        super.init()

        panGestureRecognizer.floatingPanel = self
        surfaceView.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.addTarget(self, action: #selector(handle(panGesture:)))
        panGestureRecognizer.delegate = self

        // Set tap-to-dismiss in the backdrop view
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackdrop(tapGesture:)))
        tapGesture.isEnabled = false
        backdropView.dismissalTapGestureRecognizer = tapGesture
        backdropView.addGestureRecognizer(tapGesture)
    }

    func move(to: FloatingPanelState, animated: Bool, completion: (() -> Void)? = nil) {
        move(from: state, to: to, animated: animated, completion: completion)
    }

    private func move(from: FloatingPanelState, to: FloatingPanelState, animated: Bool, completion: (() -> Void)? = nil) {
        assert(layoutAdapter.isValid(to), "Can't move to '\(to)' position because it's not valid in the layout")
        guard let vc = viewcontroller else {
            completion?()
            return
        }
        if state != layoutAdapter.edgeMostState {
            lockScrollView()
        }
        tearDownActiveInteraction()

        interruptAnimationIfNeeded()

        if animated {
            func updateScrollView() {
                if self.state == self.layoutAdapter.edgeMostState, abs(self.layoutAdapter.offsetFromEdgeMost) <= 1.0 {
                    self.unlockScrollView()
                } else {
                    self.lockScrollView()
                }
            }

            let animator: UIViewPropertyAnimator
            switch (from, to) {
            case (.hidden, let to):
                animator = vc.delegate?.floatingPanel?(vc, animatorForPresentingTo: to)
                    ?? FloatingPanelDefaultBehavior().addPanelAnimator(vc, to: to)
            case (let from, .hidden):
                animator = vc.delegate?.floatingPanel?(vc, animatorForDismissingWith: .zero)
                    ?? FloatingPanelDefaultBehavior().removePanelAnimator(vc, from: from, with: .zero)
            default:
                move(to: to, with: .zero) {
                    updateScrollView()
                    completion?()
                }
                return
            }

            animator.addAnimations { [weak self] in
                guard let `self` = self else { return }

                self.state = to
                self.updateLayout(to: to)
            }
            animator.addCompletion { [weak self] _ in
                guard let `self` = self else { return }
                self.animator = nil
                updateScrollView()
                completion?()
            }
            self.animator = animator
            animator.startAnimation()
        } else {
            self.state = to
            self.updateLayout(to: to)
            if self.state == self.layoutAdapter.edgeMostState {
                self.unlockScrollView()
            } else {
                self.lockScrollView()
            }
            completion?()
        }
    }

    // MARK: - Layout update

    private func updateLayout(to target: FloatingPanelState) {
        self.layoutAdapter.activateLayout(for: state, forceLayout: true)
        if let vc = viewcontroller {
            vc.delegate?.floatingPanelDidMove?(vc)
        }
    }

    func getBackdropAlpha(at currentY: CGFloat, with translation: CGPoint) -> CGFloat {
        /* log.debug("currentY: \(currentY) translation: \(translation)") */
        let forwardY = (translation.y >= 0)
        let segment = layoutAdapter.segument(at: currentY, forward: forwardY)
        let lowerPos = segment.lower ?? layoutAdapter.edgeMostState
        let upperPos = segment.upper ?? layoutAdapter.edgeLeastState

        let pre = forwardY ? lowerPos : upperPos
        let next = forwardY ? upperPos : lowerPos

        let nextY = displayTrunc(layoutAdapter.positionY(for: next), by: surfaceView.traitCollection.displayScale)
        let preY = displayTrunc(layoutAdapter.positionY(for: pre), by: surfaceView.traitCollection.displayScale)

        let nextAlpha = layoutAdapter.backdropAlpha(for: next)
        let preAlpha = layoutAdapter.backdropAlpha(for: pre)

        if preY == nextY {
            return preAlpha
        } else {
            return preAlpha + max(min(1.0, 1.0 - (nextY - currentY) / (nextY - preY) ), 0.0) * (nextAlpha - preAlpha)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer else { return false }

        /* log.debug("shouldRecognizeSimultaneouslyWith", otherGestureRecognizer) */

        if let vc = viewcontroller,
            vc.delegate?.floatingPanel?(vc, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer) ?? false {
            return true
        }

        switch otherGestureRecognizer {
        case is FloatingPanelPanGestureRecognizer:
            // All visiable panels' pan gesture should be recognized simultaneously.
            return true
        case is UIPanGestureRecognizer,
             is UISwipeGestureRecognizer,
             is UIRotationGestureRecognizer,
             is UIScreenEdgePanGestureRecognizer,
             is UIPinchGestureRecognizer:
            // all gestures of the tracking scroll view should be recognized in parallel
            // and handle them in self.handle(panGesture:)
            return scrollView?.gestureRecognizers?.contains(otherGestureRecognizer) ?? false
        default:
            // Should recognize tap/long press gestures in parallel when the surface view is at an anchor position.
            let adapterY = layoutAdapter.positionY(for: state)
            return abs(layoutAdapter.surfaceEdgeLocation.y - adapterY) < (1.0 / surfaceView.traitCollection.displayScale)
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        /* log.debug("shouldBeRequiredToFailBy", otherGestureRecognizer) */
        if otherGestureRecognizer is FloatingPanelPanGestureRecognizer {
            // If this panel is the farthest descendant of visiable panels,
            // its ancestors' pan gesture must wait for its pan gesture to fail
            if let view = otherGestureRecognizer.view, surfaceView.isDescendant(of: view) {
                return true
            }
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer else { return false }

        /* log.debug("shouldRequireFailureOf", otherGestureRecognizer) */

        // Should begin the pan gesture without waiting for the tracking scroll view's gestures.
        // `scrollView.gestureRecognizers` can contains the following gestures
        // * UIScrollViewDelayedTouchesBeganGestureRecognizer
        // * UIScrollViewPanGestureRecognizer (scrollView.panGestureRecognizer)
        // * _UIDragAutoScrollGestureRecognizer
        // * _UISwipeActionPanGestureRecognizer
        // * UISwipeDismissalGestureRecognizer
        if let scrollView = scrollView {
            // On short contents scroll, `_UISwipeActionPanGestureRecognizer` blocks
            // the panel's pan gesture if not returns false
            if let scrollGestureRecognizers = scrollView.gestureRecognizers,
                scrollGestureRecognizers.contains(otherGestureRecognizer) {
                switch otherGestureRecognizer {
                case scrollView.panGestureRecognizer:
                    if grabberAreaFrame.contains(gestureRecognizer.location(in: gestureRecognizer.view)) {
                        return false
                    }
                    return allowScrollPanGesture(for: scrollView)
                default:
                    return false
                }
            }
        }

        if let vc = viewcontroller,
            vc.delegate?.floatingPanel?(vc, shouldRecognizeSimultaneouslyWith: otherGestureRecognizer) ?? false {
            return false
        }

        switch otherGestureRecognizer {
        case is FloatingPanelPanGestureRecognizer:
            // If this panel is the farthest descendant of visiable panels,
            // its pan gesture does not require its ancestors' pan gesture to fail
            if let view = otherGestureRecognizer.view, surfaceView.isDescendant(of: view) {
                return false
            }
            return true
        case is UIPanGestureRecognizer,
             is UISwipeGestureRecognizer,
             is UIRotationGestureRecognizer,
             is UIScreenEdgePanGestureRecognizer,
             is UIPinchGestureRecognizer:
            // Do not begin the pan gesture until these gestures fail
            return true
        default:
            // Should begin the pan gesture without waiting tap/long press gestures fail
            return false
        }
    }

    var grabberAreaFrame: CGRect {
        return surfaceView.grabbableAreaFrame
    }

    // MARK: - Gesture handling

    @objc func handleBackdrop(tapGesture: UITapGestureRecognizer) {
        viewcontroller?.dismiss(animated: true) { [weak self] in
            guard let vc = self?.viewcontroller else { return }
            vc.delegate?.floatingPanelDidRemove?(vc)
        }
    }

    @objc func handle(panGesture: UIPanGestureRecognizer) {
        let velocity = panGesture.velocity(in: panGesture.view)

        switch panGesture {
        case scrollView?.panGestureRecognizer:
            guard let scrollView = scrollView else { return }

            let location = panGesture.location(in: surfaceView)

            let belowEdgeMost = 0 > layoutAdapter.offsetFromEdgeMost + (1.0 / surfaceView.traitCollection.displayScale)

            log.debug("scroll gesture(\(state):\(panGesture.state)) --",
                "belowTop = \(belowEdgeMost),",
                "interactionInProgress = \(interactionInProgress),",
                "scroll offset = \(scrollView.contentOffset.y),",
                "location = \(location.y), velocity = \(velocity.y)")

            let offset = scrollView.contentOffset.y - contentOrigin(of: scrollView).y
            let offsetMax = scrollView.fp_contentOffsetMaxY

            if belowEdgeMost {
                // Scroll offset pinning
                if state == layoutAdapter.edgeMostState {
                    if interactionInProgress {
                        log.debug("settle offset --", initialScrollOffset.y)
                        scrollView.setContentOffset(initialScrollOffset, animated: false)
                    } else {
                        if grabberAreaFrame.contains(location) {
                            // Preserve the current content offset in moving from full.
                            scrollView.setContentOffset(initialScrollOffset, animated: false)
                        }
                    }
                } else {
                    scrollView.setContentOffset(initialScrollOffset, animated: false)
                }

                // Hide a scroll indicator at the non-top in dragging.
                if interactionInProgress {
                    lockScrollView()
                } else {
                    if state == layoutAdapter.edgeMostState, self.animator == nil {
                        switch layoutAdapter.layout.anchorPosition {
                        case .top where offset < offsetMax && velocity.y > 0:
                            unlockScrollView()
                        case .bottom where offset > 0 && velocity.y < 0:
                            unlockScrollView()
                        default:
                            break
                        }
                    }
                }
            } else {
                if interactionInProgress {
                    // Show a scroll indicator at the top in dragging.
                    switch layoutAdapter.layout.anchorPosition {
                    case .top where offset <= offsetMax && velocity.y >= 0:
                        unlockScrollView()
                        return
                    case .bottom where offset >= 0 && velocity.y <= 0:
                        unlockScrollView()
                        return
                    default:
                        break
                    }
                    if state == layoutAdapter.edgeMostState {
                        // Adjust a small gap of the scroll offset just after swiping down starts in the grabber area.
                        if grabberAreaFrame.contains(location), grabberAreaFrame.contains(initialLocation) {
                            scrollView.setContentOffset(initialScrollOffset, animated: false)
                        }
                    }
                } else {
                    if state == layoutAdapter.edgeMostState {
                        switch layoutAdapter.layout.anchorPosition {
                        case .top:
                            if velocity.y < 0, !allowScrollPanGesture(for: scrollView) {
                                lockScrollView()
                            }
                            if velocity.y > 0, allowScrollPanGesture(for: scrollView) {
                                unlockScrollView()
                            }
                        case .bottom:
                            // Hide a scroll indicator just before starting an interaction by swiping a panel down.
                            if velocity.y > 0, !allowScrollPanGesture(for: scrollView) {
                                lockScrollView()
                            }
                            // Show a scroll indicator when an animation is interrupted at the top and content is scrolled up
                            if velocity.y < 0, allowScrollPanGesture(for: scrollView) {
                                unlockScrollView()
                            }
                        default:
                            break
                        }
                        // Adjust a small gap of the scroll offset just before swiping down starts in the grabber area,
                        if grabberAreaFrame.contains(location), grabberAreaFrame.contains(initialLocation) {
                            scrollView.setContentOffset(initialScrollOffset, animated: false)
                        }
                    }
                }
            }
        case panGestureRecognizer:
            let translation = panGesture.translation(in: panGestureRecognizer.view!.superview)
            let location = panGesture.location(in: panGesture.view)

            log.debug("panel gesture(\(state):\(panGesture.state)) --",
                "translation =  \(translation.y), location = \(location.y), velocity = \(velocity.y)")

            if interactionInProgress == false, isDecelerating == false,
                let vc = viewcontroller, vc.delegate?.floatingPanelShouldBeginDragging?(vc) == false {
                return
            }

            interruptAnimationIfNeeded()

            if panGesture.state == .began {
                panningBegan(at: location)
                return
            }

            if shouldScrollViewHandleTouch(scrollView, point: location, velocity: velocity) {
                return
            }

            switch panGesture.state {
            case .changed:
                if interactionInProgress == false {
                    startInteraction(with: translation, at: location)
                }
                panningChange(with: translation)
            case .ended, .cancelled, .failed:
                if interactionInProgress == false {
                    startInteraction(with: translation, at: location)
                    // Workaround: Prevent stopping the surface view b/w anchors if the pan gesture
                    // doesn't pass through .changed state after an interruptible animator is interrupted.
                    let dy = translation.y - .leastNonzeroMagnitude
                    layoutAdapter.updateInteractiveEdgeConstraint(diff: dy,
                                                                  overflow: true,
                                                                  with: behaviorAdapter.behavior)
                }
                panningEnd(with: translation, velocity: velocity)
            default:
                break
            }
        default:
            return
        }
    }

    private func interruptAnimationIfNeeded() {
        if let animator = self.moveAnimator, animator.isRunning {
            log.debug("the deceleration animator interrupted!!!")
            animator.stopAnimation(true)
            endDeceleration(false)
        }
        if let animator = self.animator {
            guard 0 >= layoutAdapter.offsetFromEdgeMost else { return }
            log.debug("a panel animation(interruptible: \(animator.isInterruptible)) interrupted!!!")
            if animator.isInterruptible {
                animator.stopAnimation(false)
                // A user can stop a panel at the nearest Y of a target position so this fine-tunes
                // the a small gap between the presentation layer frame and model layer frame
                // to unlock scroll view properly at finishAnimation(at:)
                if abs(layoutAdapter.offsetFromEdgeMost) <= 1.0 {
                    surfaceView.frame.origin.y = layoutAdapter.edgeMostY
                }
                animator.finishAnimation(at: .current)
            } else {
                animator.stopAnimation(true)
            }
        }
    }

    private func shouldScrollViewHandleTouch(_ scrollView: UIScrollView?, point: CGPoint, velocity: CGPoint) -> Bool {
        // When no scrollView, nothing to handle.
        guard let scrollView = scrollView else { return false }

        // For _UISwipeActionPanGestureRecognizer
        if let scrollGestureRecognizers = scrollView.gestureRecognizers {
            for gesture in scrollGestureRecognizers {
                guard gesture.state == .began || gesture.state == .changed
                else { continue }

                if gesture !=  scrollView.panGestureRecognizer {
                    return true
                }
            }
        }

        guard
            state == layoutAdapter.edgeMostState,  // When not top most(i.e. .full), don't scroll.
            interactionInProgress == false,        // When interaction already in progress, don't scroll.
            0 == layoutAdapter.offsetFromEdgeMost
        else {
            return false
        }

        // When the current and initial point within grabber area, do scroll.
        if grabberAreaFrame.contains(point), !grabberAreaFrame.contains(initialLocation) {
            return true
        }

        let scrollViewFrame = scrollView.convert(scrollView.bounds, to: surfaceView)
        guard
            scrollViewFrame.contains(initialLocation), // When initialLocation not in scrollView, don't scroll.
            !grabberAreaFrame.contains(point)           // When point within grabber area, don't scroll.
        else {
            return false
        }

        let offset = scrollView.contentOffset.y - contentOrigin(of: scrollView).y
        // The zero offset must be excluded because the offset is usually zero
        // after a panel moves from half/tip to full.
        switch layoutAdapter.layout.anchorPosition {
        case .top:
            let offsetMax = scrollView.fp_contentOffsetMaxY
            if  offset < offsetMax {
                return true
            }
            if velocity.y >= 0 {
                return true
            }
        case .bottom:
            if  offset > 0.0 {
                return true
            }
            if velocity.y <= 0 {
                return true
            }
        }

        if scrollView.isDecelerating {
            return true
        }

        return false
    }

    private func panningBegan(at location: CGPoint) {
        // A user interaction does not always start from Began state of the pan gesture
        // because it can be recognized in scrolling a content in a content view controller.
        // So here just preserve the current state if needed.
        log.debug("panningBegan -- location = \(location.y)")
        initialLocation = location

        guard let scrollView = scrollView else { return }
        if state == layoutAdapter.edgeMostState {
            if grabberAreaFrame.contains(location) {
                initialScrollOffset = scrollView.contentOffset
            }
        } else {
            initialScrollOffset = scrollView.contentOffset
        }
    }

    private func panningChange(with translation: CGPoint) {
        log.debug("panningChange -- translation = \(translation.y)")
        let preY = layoutAdapter.surfaceEdgeLocation.y
        let dy = translation.y - initialTranslationY
        let nextY = layoutAdapter.edgeY(initialFrame.offsetBy(dx: 0.0, dy: dy))

        let overflow = shouldOverflow(preY: preY, nextY: nextY, dy: dy)

        layoutAdapter.updateInteractiveEdgeConstraint(diff: dy, overflow: overflow, with: behaviorAdapter.behavior)

        let currentY = layoutAdapter.surfaceEdgeLocation.y

        backdropView.alpha = getBackdropAlpha(at: currentY, with: translation)

        let didMove = (preY != currentY)
        guard didMove else { return }

        if let vc = viewcontroller {
            vc.delegate?.floatingPanelDidMove?(vc)
        }
    }

    private func shouldOverflow(preY: CGFloat, nextY: CGFloat, dy: CGFloat) -> Bool {
        if let scrollView = scrollView, scrollView.panGestureRecognizer.state == .changed {
            switch layoutAdapter.layout.anchorPosition {
            case .top:
                if preY > 0, preY < nextY {
                    return false
                }
            case .bottom:
                if preY > 0, preY > nextY {
                    return false
                }
            }
        }
        return true
    }

    private func panningEnd(with translation: CGPoint, velocity: CGPoint) {
        log.debug("panningEnd -- translation = \(translation.y), velocity = \(velocity.y)")

        if state == .hidden {
            log.debug("Already hidden")
            return
        }

        stopScrollDeceleration = (0 > layoutAdapter.offsetFromEdgeMost + (1.0 / surfaceView.traitCollection.displayScale)) // Projecting the dragging to the scroll dragging or not
        if stopScrollDeceleration {
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
                self.stopScrollingWithDeceleration(at: self.initialScrollOffset)
            }
        }

        let currentY = layoutAdapter.surfaceEdgeLocation.y
        var targetPosition = self.targetPosition(from: currentY, with: velocity)

        endInteraction(for: targetPosition)

        if isRemovalInteractionEnabled {
            let distToHidden = CGFloat(abs(currentY - layoutAdapter.positionY(for: .hidden)))
            let removalVector = (distToHidden != 0) ? CGVector(dx: 0, dy: velocity.y/distToHidden) : .zero
            if shouldStartRemovalAnimation(with: removalVector), let vc = viewcontroller {

                vc.delegate?.floatingPanelWillRemove?(vc, with: velocity)

                let animationVector = CGVector(dx: abs(removalVector.dx), dy: abs(removalVector.dy))
                startRemovalAnimation(vc, with: animationVector) { [weak self] in
                    self?.finishRemovalAnimation()
                }
                return
            }
        }

        if let vc = viewcontroller {
            vc.delegate?.floatingPanelWillEndDragging?(vc, withVelocity: velocity, targetState: &targetPosition)
        }

        if shouldDecelerate(to: targetPosition) {
            if let vc = viewcontroller {
                vc.delegate?.floatingPanelDidEndDragging?(vc, willDecelerate: false)
            }

            self.state = targetPosition
            self.updateLayout(to: targetPosition)
            self.unlockScrollView()
            return
        }

        if let vc = viewcontroller {
            vc.delegate?.floatingPanelDidEndDragging?(vc, willDecelerate: true)
        }

        // Workaround: Disable a tracking scroll to prevent bouncing a scroll content in a panel animating
        let isScrollEnabled = scrollView?.isScrollEnabled
        if let scrollView = scrollView, targetPosition != .full {
            scrollView.isScrollEnabled = false
        }

        startDeceleration(to: targetPosition, with: velocity)

        // Workaround: Reset `self.scrollView.isScrollEnabled`
        if let scrollView = scrollView, targetPosition != .full,
            let isScrollEnabled = isScrollEnabled {
            scrollView.isScrollEnabled = isScrollEnabled
        }
    }

    private func shouldStartRemovalAnimation(with velocityVector: CGVector) -> Bool {
        guard let vc = viewcontroller else { return false }
        return vc.delegate?.floatingPanel?(vc, shouldRemoveAt: vc.surfaceEdgeLocation, with: velocityVector)
            ?? (velocityVector.dy >= 10.0)
    }

    private func startRemovalAnimation(_ vc: FloatingPanelController, with velocityVector: CGVector, completion: (() -> Void)?) {
        let animator = vc.delegate?.floatingPanel?(vc, animatorForDismissingWith: velocityVector)
            ?? FloatingPanelDefaultBehavior().removePanelAnimator(vc, from: self.state, with: velocityVector)

        animator.addAnimations { [weak self] in
            self?.state = .hidden
            self?.updateLayout(to: .hidden)
        }
        animator.addCompletion({ _ in
            self.animator = nil
            completion?()
        })
        self.animator = animator
        animator.startAnimation()
    }

    private func finishRemovalAnimation() {
        viewcontroller?.dismiss(animated: false) { [weak self] in
            guard let vc = self?.viewcontroller else { return }
            vc.delegate?.floatingPanelDidRemove?(vc)
        }
    }

    private func startInteraction(with translation: CGPoint, at location: CGPoint) {
        /* Don't lock a scroll view to show a scroll indicator after hitting the top */
        log.debug("startInteraction  -- translation = \(translation.y), location = \(location.y)")
        guard interactionInProgress == false else { return }

        var offset: CGPoint = .zero

        initialFrame = surfaceView.frame
        if state == layoutAdapter.edgeMostState, let scrollView = scrollView {
            if grabberAreaFrame.contains(location) {
                initialScrollOffset = scrollView.contentOffset
            } else {
                switch layoutAdapter.layout.anchorPosition {
                case .top:
                    let offsetMax = scrollView.fp_contentOffsetMaxY
                    initialScrollOffset = CGPoint(x: 0, y: offsetMax)
                    // Fit the surface bounds to a scroll offset content by startInteraction(at:offset:)
                    let scrollOffsetY = (scrollView.contentOffset.y - offsetMax)
                    if scrollOffsetY > 0 {
                        offset = CGPoint(x: -scrollView.contentOffset.x, y: -scrollOffsetY)
                    }
                case .bottom:
                    initialScrollOffset = contentOrigin(of: scrollView)
                    // Fit the surface bounds to a scroll offset content by startInteraction(at:offset:)
                    let scrollOffsetY = (scrollView.contentOffset.y - contentOrigin(of: scrollView).y)
                    if scrollOffsetY < 0 {
                        offset = CGPoint(x: -scrollView.contentOffset.x, y: -scrollOffsetY)
                    }
                default:
                    break
                }
            }
            log.debug("initial scroll offset --", initialScrollOffset)
        }

        initialTranslationY = translation.y

        if let vc = viewcontroller {
            vc.delegate?.floatingPanelWillBeginDragging?(vc)
        }

        layoutAdapter.startInteraction(at: state, offset: offset)

        interactionInProgress = true

        lockScrollView()
    }

    private func endInteraction(for targetPosition: FloatingPanelState) {
        log.debug("endInteraction to \(targetPosition)")

        if let scrollView = scrollView {
            log.debug("endInteraction -- scroll offset = \(scrollView.contentOffset)")
        }

        interactionInProgress = false

        // Prevent to keep a scroll view indicator visible at the half/tip position
        if targetPosition != layoutAdapter.edgeMostState {
            lockScrollView()
        }

        layoutAdapter.endInteraction(at: targetPosition)
    }

    private func tearDownActiveInteraction() {
        // Cancel the pan gesture so that panningEnd(with:velocity:) is called
        panGestureRecognizer.isEnabled = false
        panGestureRecognizer.isEnabled = true
    }

    private func shouldDecelerate(to targetState: FloatingPanelState) -> Bool {
        if scrollView != nil, !stopScrollDeceleration, 0 == layoutAdapter.offsetFromEdgeMost, targetState == layoutAdapter.edgeMostState {
            return true
        }
        if layoutAdapter.positionY(for: targetState) == layoutAdapter.surfaceEdgeLocation.y, targetState == layoutAdapter.edgeLeastState {
            return true
        }
        return false
    }

    private func startDeceleration(to targetPosition: FloatingPanelState, with velocity: CGPoint) {
        log.debug("startAnimation to \(targetPosition) -- velocity = \(velocity.y)")
        guard let vc = viewcontroller else { return }

        isDecelerating = true
        vc.delegate?.floatingPanelWillBeginDecelerating?(vc)
        move(to: targetPosition, with: velocity) {
            self.endDeceleration(true)
        }
    }

    private func move(to targetPosition: FloatingPanelState, with velocity: CGPoint = .zero, completion: @escaping (() -> Void)) {
        guard let vc = viewcontroller else { return }
        let decelerationRate = vc.behavior.springDecelerationRate ?? FloatingPanelDefaultBehavior().springDecelerationRate
        let responseTime = vc.behavior.springResponseTime ?? FloatingPanelDefaultBehavior().springResponseTime

        let (animationConstraint, target) = layoutAdapter.setUpAnimationEdgeConstraint(to: targetPosition)
        let initialData = NumericSpringAnimator.Data(value: animationConstraint.constant, velocity: velocity.y)
        moveAnimator = NumericSpringAnimator(
            initialData: initialData,
            target: target,
            displayScale: surfaceView.traitCollection.displayScale,
            decelerationRate: decelerationRate,
            responseTime: responseTime,
            update: { data in
                animationConstraint.constant = data.value
                let currentY = vc.surfaceEdgeLocation.y
                let translation = CGPoint(x: 0, y: data.value - initialData.value)
                self.backdropView.alpha = self.getBackdropAlpha(at: currentY, with: translation)
                vc.delegate?.floatingPanelDidMove?(vc)
        },
            completion: {
                self.layoutAdapter.activateLayout(for: targetPosition, forceLayout: true)
                completion()
        })
        moveAnimator?.startAnimation()
        state = targetPosition
    }

    private func endDeceleration(_ finished: Bool) {
        self.isDecelerating = false
        self.moveAnimator = nil

        if let vc = viewcontroller {
            vc.delegate?.floatingPanelDidEndDecelerating?(vc)
        }

        if let scrollView = scrollView {
            log.debug("finishAnimation -- scroll offset = \(scrollView.contentOffset)")
        }

        stopScrollDeceleration = false

        log.debug("finishAnimation -- state = \(state) surface.edgeY = \(layoutAdapter.surfaceEdgeLocation.y) edgeMostY = \(layoutAdapter.edgeMostY)")
        if finished, state == layoutAdapter.edgeMostState, abs(layoutAdapter.offsetFromEdgeMost) <= 1.0 {
            unlockScrollView()
        }
    }

    // Distance travelled after decelerating to zero velocity at a constant rate.
    // Refer to the slides p176 of [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)
    private func project(initialVelocity: CGFloat, decelerationRate: CGFloat) -> CGFloat {
        return (initialVelocity / 1000.0) * decelerationRate / (1.0 - decelerationRate)
    }

    func targetPosition(from currentY: CGFloat, with velocity: CGPoint) -> (FloatingPanelState) {
        log.debug("targetPosition -- currentY = \(currentY), velocity = \(velocity.y)")

        guard let vc = viewcontroller else { return state }
        let sortedPositions = layoutAdapter.sortedDirectionalStates

        guard sortedPositions.count > 1 else {
            return state
        }

        // Projection
        let decelerationRate = behaviorAdapter.behavior.momentumProjectionRate ?? FloatingPanelDefaultBehavior().momentumProjectionRate
        let baseY = abs(layoutAdapter.positionY(for: layoutAdapter.edgeLeastState) - layoutAdapter.positionY(for: layoutAdapter.edgeMostState))
        let vecY = velocity.y / baseY
        var pY = project(initialVelocity: vecY, decelerationRate: decelerationRate) * baseY + currentY

        let distance = (currentY - layoutAdapter.positionY(for: state))
        let forwardY = velocity.y == 0 ? distance > 0 : velocity.y > 0

        let segment = layoutAdapter.segument(at: pY, forward: forwardY)

        var fromPos: FloatingPanelState
        var toPos: FloatingPanelState

        let (lowerPos, upperPos) = (segment.lower ?? sortedPositions.first!, segment.upper ?? sortedPositions.last!)
        (fromPos, toPos) = forwardY ? (lowerPos, upperPos) : (upperPos, lowerPos)

        if (behaviorAdapter.behavior.shouldProjectMomentum?(vc, to: toPos) ?? false) == false {
            log.debug("targetPosition -- negate projection: distance = \(distance)")
            let segment = layoutAdapter.segument(at: currentY, forward: forwardY)
            var (lowerPos, upperPos) = (segment.lower ?? sortedPositions.first!, segment.upper ?? sortedPositions.last!)
            // Equate the segment out of {top,bottom} most state to the {top,bottom} most segment
            if lowerPos == upperPos {
                if forwardY {
                    upperPos = lowerPos.next(in: sortedPositions)
                } else {
                    lowerPos = lowerPos.pre(in: sortedPositions)
                }
            }
            (fromPos, toPos) = forwardY ? (lowerPos, upperPos) : (upperPos, lowerPos)
            // Block a projection to a segment over the next from the current segment
            // (= Trim pY with the current segment)
            if forwardY {
                pY = max(min(pY, layoutAdapter.positionY(for: toPos.next(in: sortedPositions))), layoutAdapter.positionY(for: fromPos))
            } else {
                pY = max(min(pY, layoutAdapter.positionY(for: fromPos)), layoutAdapter.positionY(for: toPos.pre(in: sortedPositions)))
            }
        }

        // Redirection
        let redirectionalProgress = max(min(behaviorAdapter.behavior.redirectionalProgress?(vc, from: fromPos, to: toPos) ?? FloatingPanelDefaultBehavior().redirectionalProgress(vc,from: fromPos, to: toPos), 1.0), 0.0)
        let progress = abs(pY - layoutAdapter.positionY(for: fromPos)) / abs(layoutAdapter.positionY(for: fromPos) - layoutAdapter.positionY(for: toPos))
        return progress > redirectionalProgress ? toPos : fromPos
    }

    // MARK: - ScrollView handling

    private func lockScrollView() {
        guard let scrollView = scrollView else { return }

        if scrollView.isLocked {
            log.debug("Already scroll locked.")
            return
        }
        log.debug("lock scroll view")

        scrollBouncable = scrollView.bounces
        scrollIndictorVisible = scrollView.showsVerticalScrollIndicator

        scrollView.isDirectionalLockEnabled = true
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
    }

    private func unlockScrollView() {
        guard let scrollView = scrollView, scrollView.isLocked else { return }
        log.debug("unlock scroll view")

        scrollView.isDirectionalLockEnabled = false
        scrollView.bounces = scrollBouncable
        scrollView.showsVerticalScrollIndicator = scrollIndictorVisible
    }

    private func stopScrollingWithDeceleration(at contentOffset: CGPoint) {
        // Must use setContentOffset(_:animated) to force-stop deceleration
        scrollView?.setContentOffset(contentOffset, animated: false)
    }

    private func contentOrigin(of scrollView: UIScrollView) -> CGPoint {
        if let vc = viewcontroller, let origin = vc.delegate?.floatingPanel?(vc, contentOffsetForPinning: scrollView) {
            return origin
        }
        return CGPoint(x: 0.0, y: 0.0 - scrollView.fp_contentInset.top)
    }

    private func allowScrollPanGesture(for scrollView: UIScrollView) -> Bool {
        guard state == layoutAdapter.edgeMostState else { return false }
        var offsetY: CGFloat = 0
        switch layoutAdapter.layout.anchorPosition {
        case .top:
            offsetY = scrollView.fp_contentOffsetMaxY - scrollView.contentOffset.y
        case .bottom:
            offsetY = scrollView.contentOffset.y - contentOrigin(of: scrollView).y
        default:
            return false
        }
        return offsetY <= -30.0 || offsetY > 0
    }
}

class FloatingPanelPanGestureRecognizer: UIPanGestureRecognizer {
    fileprivate weak var floatingPanel: FloatingPanelCore?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if floatingPanel?.animator != nil || floatingPanel?.moveAnimator != nil {
            self.state = .began
        }
    }
    override weak var delegate: UIGestureRecognizerDelegate? {
        get {
            return super.delegate
        }
        set {
            guard newValue is FloatingPanelCore else {
                let exception = NSException(name: .invalidArgumentException,
                                            reason: "FloatingPanelController's built-in pan gesture recognizer must have its controller as its delegate.",
                                            userInfo: nil)
                exception.raise()
                return
            }
            super.delegate = newValue
        }
    }
}

class NumericSpringAnimator: NSObject {
    struct Data {
        let value: CGFloat
        let velocity: CGFloat
    }

    private class UnfairLock {
        var unfairLock = os_unfair_lock()
        func lock() {
            os_unfair_lock_lock(&unfairLock);
        }
        func tryLock() -> Bool {
            return os_unfair_lock_trylock(&unfairLock);
        }
        func unlock() {
            os_unfair_lock_unlock(&unfairLock);
        }
    }

    var isRunning = false

    private var lock = UnfairLock()

    private lazy var displayLink = CADisplayLink(target: self, selector: #selector(update(_:)))

    private var data: Data

    private let target: CGFloat
    private let displayScale: CGFloat
    private let zeta: CGFloat
    private let omega: CGFloat

    private let update: ((_ data: Data) -> Void)
    private let completion: (() -> Void)

    init(initialData: Data,
         target: CGFloat,
         displayScale: CGFloat,
         decelerationRate: CGFloat,
         responseTime: CGFloat,
         update: @escaping ((_ data: Data) -> Void),
         completion: @escaping (() -> Void)) {

        self.data = initialData
        self.target = target
        self.displayScale = displayScale

        let frequency = 1 / responseTime // oscillation frequency
        let duration: CGFloat = 0.001 // millisecond
        self.zeta = abs(initialData.velocity) > 300 ? CoreGraphics.log(decelerationRate) / (-2.0 * .pi * frequency * duration)  : 1.0
        self.omega = 2.0 * .pi * frequency

        self.update = update
        self.completion = completion
    }

    @discardableResult
    func startAnimation() -> Bool{
        lock.lock()
        defer { lock.unlock() }

        if isRunning {
            return false
        }
        log.debug("startAnimation --", displayLink)
        isRunning = true
        displayLink.add(to: RunLoop.main, forMode: .common)
        return true
    }

    func stopAnimation(_ withoutFinishing: Bool) {
        let locked = lock.tryLock()
        defer {
            if locked { lock.unlock() }
        }

        log.debug("stopAnimation --", displayLink)
        isRunning = false
        displayLink.invalidate()
        if withoutFinishing {
            return
        }
        completion()
    }

    var count: Int = 0
    @objc
    func update(_ displayLink: CADisplayLink) {
        lock.lock()
        defer { lock.unlock() }

        var cur = data.value
        let pre = cur
        var velocity = data.velocity
        spring(x: &cur,
               v: &velocity,
               xt: target,
               zeta: zeta,
               omega: omega,
               h: CGFloat(displayLink.duration))
        data = Data(value: cur, velocity: velocity)
        update(data)
        if abs(target - data.value) <= (1 / displayScale),
           abs(pre - data.value) / (1 / displayScale) <= 1 {
            stopAnimation(false)
        }
    }
    /**
     - Parameters:
         - x: value
         - v: velocity
         - xt: target value
         - zeta: damping ratio
         - omega: angular frequency
         - h: time step
      */
     private func spring(x: inout CGFloat, v: inout CGFloat, xt: CGFloat, zeta: CGFloat, omega: CGFloat, h: CGFloat) {
        let f = 1.0 + 2.0 * h * zeta * omega
        let h2 = pow(h, 2)
        let o2 = pow(omega, 2)
        let det = f + h2 * o2
        x = (f * x + h * v + h2 * o2 * xt) / det
        v = (v + h * o2 * (xt - x)) / det
     }
}
