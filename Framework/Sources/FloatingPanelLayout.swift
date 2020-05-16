//
//  Created by Shin Yamamoto on 2018/09/27.
//  Copyright © 2018 Shin Yamamoto. All rights reserved.
//

import UIKit

@objc public enum FloatingPanelLayoutReferenceGuide: Int {
    case superview = 0
    case safeArea = 1
}

@objc public enum FloatingPanelPosition: Int {
    case top
    case bottom
    /* TODO:
      case left
      case right
     */
}

@objc public enum FloatingPanelDirectionalEdge: Int {
    case auto
    case top
    case leading
    case bottom
    case trailing
}

@objc public protocol FloatingPanelLayoutAnchoring {
    var referenceGuide: FloatingPanelLayoutReferenceGuide { get }
    var referenceEdge: FloatingPanelDirectionalEdge { get }
    func layoutConstraints(_ fpc: FloatingPanelController, for position: FloatingPanelPosition) -> [NSLayoutConstraint]
}

@objc final public class FloatingPanelLayoutAnchor: NSObject, FloatingPanelLayoutAnchoring /*, NSCopying */ {
    public static let hidden: FloatingPanelLayoutAnchor = FloatingPanelLayoutAnchor(absoluteInset: 0.0, edge: .auto, referenceGuide: .superview)

    @objc public init(absoluteInset: CGFloat, edge: FloatingPanelDirectionalEdge, referenceGuide: FloatingPanelLayoutReferenceGuide) {
        self.inset = absoluteInset
        self.referenceGuide = referenceGuide
        self.referenceEdge = edge
        self.isAbsolute = true
    }

    @objc public init(fractionalInset: CGFloat, edge: FloatingPanelDirectionalEdge, referenceGuide: FloatingPanelLayoutReferenceGuide) {
        self.inset = fractionalInset
        self.referenceGuide = referenceGuide
        self.referenceEdge = edge
        self.isAbsolute = false
    }
    fileprivate let inset: CGFloat
    fileprivate let isAbsolute: Bool
    @objc public let referenceGuide: FloatingPanelLayoutReferenceGuide
    @objc public let referenceEdge: FloatingPanelDirectionalEdge
}

public extension FloatingPanelLayoutAnchor {
    func layoutConstraints(_ vc: FloatingPanelController, for position: FloatingPanelPosition) -> [NSLayoutConstraint] {
        switch position {
        case .top:
            let edgeAnchor = vc.surfaceView.bottomAnchor
            if self == FloatingPanelLayoutAnchor.hidden {
                return [edgeAnchor.constraint(equalTo: vc.view.topAnchor, constant: 0.0)]
            }
            return layoutConstraints(vc, for: edgeAnchor)
        case .bottom:
            let edgeAnchor = vc.surfaceView.topAnchor
            if self == FloatingPanelLayoutAnchor.hidden {
                return [edgeAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: 0.0)]
            }
            return layoutConstraints(vc, for: edgeAnchor)
        }
    }

    private func layoutConstraints(_ vc: FloatingPanelController, for edgeAnchor: NSLayoutYAxisAnchor) -> [NSLayoutConstraint] {
        switch referenceEdge {
        case .top:
            let referenceAnchor: NSLayoutYAxisAnchor
            let heightAnchor: NSLayoutDimension
            switch self.referenceGuide {
            case .superview:
                referenceAnchor = vc.view.topAnchor
                heightAnchor = vc.view.heightAnchor
            case .safeArea:
                referenceAnchor = vc.fp_safeAreaLayoutGuide.topAnchor
                heightAnchor = vc.fp_safeAreaLayoutGuide.heightAnchor
            }
            if isAbsolute {
                return [edgeAnchor.constraint(equalTo: referenceAnchor, constant: inset)]
            }
            let offsetAnchor = referenceAnchor.anchorWithOffset(to: edgeAnchor)
            return [offsetAnchor.constraint(equalTo:heightAnchor, multiplier: inset)]

        case .bottom:
            let referenceAnchor: NSLayoutYAxisAnchor
            let heightAnchor: NSLayoutDimension
            switch self.referenceGuide {
            case .superview:
                referenceAnchor = vc.view.bottomAnchor
                heightAnchor = vc.view.heightAnchor
            case .safeArea:
                referenceAnchor = vc.fp_safeAreaLayoutGuide.bottomAnchor
                heightAnchor = vc.fp_safeAreaLayoutGuide.heightAnchor
            }

            if isAbsolute {
                return [referenceAnchor.constraint(equalTo: edgeAnchor, constant: inset)]
            }
            let offsetAnchor = edgeAnchor.anchorWithOffset(to: referenceAnchor)
            return [offsetAnchor.constraint(equalTo: heightAnchor, multiplier: inset)]
        default:
            fatalError("Unsupported edges")
        }
    }
}

@objc final public class FloatingPanelIntrinsicLayoutAnchor: NSObject, FloatingPanelLayoutAnchoring /*, NSCopying */ {
    @objc public init(absoluteOffset offset: CGFloat, referenceGuide: FloatingPanelLayoutReferenceGuide = .safeArea) {
        self.offset = offset
        self.referenceGuide = referenceGuide
        self.referenceEdge = .auto
        self.isAbsolute = true
    }
    // offset = 0.0 -> All content visible
    // offset = 1.0 -> All content invisible
    @objc public init(fractionalOffset offset: CGFloat, referenceGuide: FloatingPanelLayoutReferenceGuide = .safeArea) {
        self.offset = offset
        self.referenceGuide = referenceGuide
        self.referenceEdge = .auto
        self.isAbsolute = false
    }
    fileprivate let offset: CGFloat
    fileprivate let isAbsolute: Bool
    @objc public let referenceGuide: FloatingPanelLayoutReferenceGuide
    @objc public let referenceEdge: FloatingPanelDirectionalEdge

}

public extension FloatingPanelIntrinsicLayoutAnchor {
    func layoutConstraints(_ vc: FloatingPanelController, for position: FloatingPanelPosition) -> [NSLayoutConstraint] {
        let surfaceIntrinsicHeight = vc.surfaceView.intrinsicContentSize.height
        switch position {
        case .top:
            let edgeAnchor = vc.surfaceView.bottomAnchor
            let constant = isAbsolute ? surfaceIntrinsicHeight - offset : surfaceIntrinsicHeight * (1 - offset)
            switch self.referenceGuide {
            case .superview:
                return [edgeAnchor.constraint(equalTo: vc.view.topAnchor, constant: constant)]
            case .safeArea:
                return [edgeAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.topAnchor, constant: constant)]
            }
        case .bottom:
            let edgeAnchor = vc.surfaceView.topAnchor
            let constant = isAbsolute ? -(surfaceIntrinsicHeight - offset) : -surfaceIntrinsicHeight * (1 - offset)
            switch self.referenceGuide {
            case .superview:
                return [edgeAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: constant)]
            case .safeArea:
                return [edgeAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.bottomAnchor, constant: constant)]
            }
        }
    }
}

@objc public protocol FloatingPanelLayout {
    /// TODO: Write doc comment
    @objc var anchoredPosition: FloatingPanelPosition { get }

    /// TODO: Write doc comment
    @objc var initialState: FloatingPanelState { get }

    /// TODO: Write doc comment
    @objc var stateAnchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] { get }

    /// Returns X-axis and width layout constraints of the surface view of a floating panel.
    /// You must not include any Y-axis and height layout constraints of the surface view
    /// because their constraints will be configured by the floating panel controller.
    /// By default, the width of a surface view fits a safe area.
    @objc optional func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint]

    /// Returns a CGFloat value to determine the backdrop view's alpha for a state.
    ///
    /// Default is 0.3 at full state, otherwise 0.0.
    @objc optional func backdropAlpha(for state: FloatingPanelState) -> CGFloat
}

@objcMembers
open class FloatingPanelDefaultLayout: NSObject, FloatingPanelLayout {
    public override init() {
        super.init()
    }
    open var initialState: FloatingPanelState {
        return .half
    }

    open var stateAnchors: [FloatingPanelState: FloatingPanelLayoutAnchoring]  {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 18.0, edge: .top, referenceGuide: .safeArea),
            .half: FloatingPanelLayoutAnchor(fractionalInset: 0.5, edge: .bottom, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 69.0, edge: .bottom, referenceGuide: .safeArea),
        ]
    }

    open var anchoredPosition: FloatingPanelPosition {
        return .bottom
    }

    open func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        return [
            surfaceView.leftAnchor.constraint(equalTo: view.sideLayoutGuide.leftAnchor, constant: 0.0),
            surfaceView.rightAnchor.constraint(equalTo: view.sideLayoutGuide.rightAnchor, constant: 0.0),
        ]
    }

    open func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        return state == .full ? 0.3 : 0.0
    }
}

struct LayoutSegment {
    let lower: FloatingPanelState?
    let upper: FloatingPanelState?
}

class FloatingPanelLayoutAdapter {
    weak var vc: FloatingPanelController!
    private weak var surfaceView: FloatingPanelSurfaceView!
    private weak var backdropView: FloatingPanelBackdropView!
    private let defaultLayout = FloatingPanelDefaultLayout()

    var layout: FloatingPanelLayout {
        didSet {
            surfaceView.position = layout.anchoredPosition
        }
    }

    private var safeAreaInsets: UIEdgeInsets {
        return vc?.fp_safeAreaInsets ?? .zero
    }

    private var initialConst: CGFloat = 0.0

    private var fixedConstraints: [NSLayoutConstraint] = []
    private var fullConstraints: [NSLayoutConstraint] = []
    private var halfConstraints: [NSLayoutConstraint] = []
    private var tipConstraints: [NSLayoutConstraint] = []
    private var offConstraints: [NSLayoutConstraint] = []
    private var fitToBoundsConstraint: NSLayoutConstraint?

    private(set) var interactionEdgeConstraint: NSLayoutConstraint?
    private(set) var animationEdgeConstraint: NSLayoutConstraint?

    private var heightConstraint: NSLayoutConstraint?

    private var activeStates: Set<FloatingPanelState> {
        return Set(layout.stateAnchors.keys)
    }

    var orderedStates: [FloatingPanelState] {
        return activeStates.sorted(by: {
            return $0.order < $1.order
        })
    }

    var sortedDirectionalStates: [FloatingPanelState] {
        return activeStates.sorted(by: {
            switch layout.anchoredPosition {
            case .top:
                return $0.order < $1.order
            case .bottom:
                return $0.order > $1.order
            }
        })
    }

    private var directionalLeastState: FloatingPanelState {
        return sortedDirectionalStates.first ?? .hidden
    }

    private var directionalMostState: FloatingPanelState {
        return sortedDirectionalStates.last ?? .hidden
    }

    var edgeLeastState: FloatingPanelState {
        return orderedStates.first ?? .hidden
    }
    
    var edgeMostState: FloatingPanelState {
        return orderedStates.last ?? .hidden
    }

    var edgeMostY: CGFloat {
        return positionY(for: edgeMostState)
    }

    var adjustedContentInsets: UIEdgeInsets {
        switch layout.anchoredPosition {
        case .top:
            return UIEdgeInsets(top: safeAreaInsets.top,
                                left: 0.0,
                                bottom: 0.0,
                                right: 0.0)
        case .bottom:
            return UIEdgeInsets(top: 0.0,
                                left: 0.0,
                                bottom: safeAreaInsets.bottom,
                                right: 0.0)
        }
    }

    func positionY(for pos: FloatingPanelState) -> CGFloat {
        let bounds = vc.view.bounds
        let safeAreaBounds = vc.view.bounds.inset(by: vc.fp_safeAreaInsets)

        if pos == .hidden {
            switch layout.anchoredPosition {
            case .top: return 0.0
            case .bottom: return bounds.height
            }
        }

        guard let anchor = layout.stateAnchors[pos] else {
            return .nan
        }

        switch anchor {
        case let ianchor as FloatingPanelIntrinsicLayoutAnchor:
            let surfaceIntrinsicHeight = surfaceView.intrinsicContentSize.height
            switch layout.anchoredPosition {
            case .top:
                var ret = surfaceIntrinsicHeight
                if ianchor.referenceGuide == .safeArea {
                    ret += safeAreaInsets.top
                }
                if ianchor.isAbsolute {
                    return ret - ianchor.offset
                } else {
                    return ret - surfaceIntrinsicHeight * ianchor.offset
                }
            case .bottom:
                var ret = bounds.height - surfaceIntrinsicHeight
                if ianchor.referenceGuide == .safeArea {
                    ret -= safeAreaInsets.bottom
                }
                if ianchor.isAbsolute {
                    return ret + ianchor.offset
                } else {
                    return ret + surfaceIntrinsicHeight * ianchor.offset
                }
            }
        case let anchor as FloatingPanelLayoutAnchor:
            switch anchor.referenceGuide {
            case .safeArea:
                switch anchor.referenceEdge {
                case .top:
                    let base = safeAreaBounds.minY
                    if anchor.isAbsolute {
                        return base + anchor.inset
                    }
                    return base + safeAreaBounds.height * anchor.inset
                case .bottom:
                    let base = safeAreaBounds.maxY
                    if anchor.isAbsolute {
                        return base - anchor.inset
                    }
                    return base - (safeAreaBounds.height * anchor.inset)
                default:
                    fatalError("Unsupported edges")
                }
            case .superview:
                switch anchor.referenceEdge {
                case .top:
                    let base = bounds.minY
                    if anchor.isAbsolute {
                        return base + anchor.inset
                    }
                    return base + bounds.height * anchor.inset
                case .bottom:
                    let base = bounds.maxY
                    if anchor.isAbsolute {
                        return base - anchor.inset
                    }
                    return base - (bounds.height * anchor.inset)
                default:
                    fatalError("Unsupported edges")
                }
            }
        default:
            assertionFailure("Unsupported FloatingPanelLayoutAnchoring object")
            return 0.0
        }
    }

    var surfaceEdgeLocation: CGPoint {
        get {
            let displayScale = surfaceView.traitCollection.displayScale
            return CGPoint(x: 0.0,
                           y: displayTrunc(edgeY(surfaceView.frame), by: displayScale))
        }
        set {
            switch layout.anchoredPosition {
            case .top:
                return surfaceView.frame.origin.y = newValue.y - surfaceView.bounds.height
            case .bottom:
                return surfaceView.frame.origin.y = newValue.y
            }
        }
    }

    func surfaceEdgeLocation(for state: FloatingPanelState) -> CGPoint {
        return CGPoint(x: 0.0,
                       y: displayTrunc(positionY(for: state), by: surfaceView.traitCollection.displayScale))
    }

    func isSurfaceDisplayEqual(to state: FloatingPanelState) -> Bool {
        return displayEqual(edgeY(surfaceView.frame), positionY(for: state), by: surfaceView.traitCollection.displayScale)
    }

    init(vc: FloatingPanelController,
         surfaceView: FloatingPanelSurfaceView,
         backdropView: FloatingPanelBackdropView,
         layout: FloatingPanelLayout) {
        self.vc = vc
        self.layout = layout
        self.surfaceView = surfaceView
        self.backdropView = backdropView
    }

    var offsetFromEdgeMost: CGFloat {
        switch layout.anchoredPosition {
        case .top:
            return surfaceView.presentationFrame.maxY - positionY(for: directionalMostState)
        case .bottom:
            return positionY(for: directionalLeastState) - surfaceView.presentationFrame.minY
        }
    }

    func edgeY(_ frame: CGRect) -> CGFloat {
        switch layout.anchoredPosition {
        case .top:
            return frame.maxY
        case .bottom:
            return frame.minY
        }
    }

    func prepareLayout() {
        NSLayoutConstraint.deactivate(fixedConstraints)

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.translatesAutoresizingMaskIntoConstraints = false

        // Fixed constraints of surface and backdrop views
        let surfaceConstraints = layout.prepareLayout?(surfaceView: surfaceView, in: vc.view!) ?? defaultLayout.prepareLayout(surfaceView: surfaceView, in: vc.view!)
        let backdropConstraints = [
            backdropView.topAnchor.constraint(equalTo: vc.view.topAnchor, constant: 0.0),
            backdropView.leftAnchor.constraint(equalTo: vc.view.leftAnchor,constant: 0.0),
            backdropView.rightAnchor.constraint(equalTo: vc.view.rightAnchor, constant: 0.0),
            backdropView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: 0.0),
            ]

        fixedConstraints = surfaceConstraints + backdropConstraints

        NSLayoutConstraint.deactivate(constraint: self.fitToBoundsConstraint)
        self.fitToBoundsConstraint = nil

        if vc.contentMode == .fitToBounds {
            fitToBoundsConstraint = {
                switch layout.anchoredPosition {
                case .top:
                    return surfaceView.topAnchor.constraint(equalTo: vc.view.topAnchor, constant: 0.0)
                case .bottom:
                    return surfaceView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: 0.0)
                }
            }()
        }

        NSLayoutConstraint.deactivate(fullConstraints + halfConstraints + tipConstraints + offConstraints)

        if let fullAnchor = layout.stateAnchors[.full] {
            fullConstraints = fullAnchor.layoutConstraints(vc, for: layout.anchoredPosition)
        }
        if let halfAnchor = layout.stateAnchors[.half] {
            halfConstraints = halfAnchor.layoutConstraints(vc, for: layout.anchoredPosition)
        }
        if let tipAnchors = layout.stateAnchors[.tip] {
            tipConstraints = tipAnchors.layoutConstraints(vc, for: layout.anchoredPosition)
        }
        let hiddenAnchor = layout.stateAnchors[.hidden] ?? (FloatingPanelLayoutAnchor.hidden as FloatingPanelLayoutAnchoring)
        offConstraints = hiddenAnchor.layoutConstraints(vc, for: layout.anchoredPosition)
    }

    func startInteraction(at state: FloatingPanelState, offset: CGPoint = .zero) {
        if let edgeConstraint = self.interactionEdgeConstraint {
            initialConst = edgeConstraint.constant
            return
        }

        tearDownAnimationEdgeConstraint()

        NSLayoutConstraint.deactivate(fullConstraints + halfConstraints + tipConstraints + offConstraints)

        initialConst = edgeY(surfaceView.frame) + offset.y

        let edgeAnchor: NSLayoutYAxisAnchor
        switch layout.anchoredPosition {
        case .top:
            edgeAnchor = surfaceView.bottomAnchor
        case .bottom:
            edgeAnchor = surfaceView.topAnchor
        }

        let edgeConst = edgeAnchor.constraint(equalTo: vc.view.topAnchor, constant: initialConst)

        NSLayoutConstraint.activate([edgeConst])
        self.interactionEdgeConstraint = edgeConst
    }

    func endInteraction(at state: FloatingPanelState) {
        // Don't deactivate `interactiveTopConstraint` here because it leads to
        // unsatisfiable constraints

        if self.interactionEdgeConstraint == nil {
            // Actiavate `interactiveTopConstraint` for `fitToBounds` mode.
            // It goes throught this path when the pan gesture state jumps
            // from .begin to .end.
            startInteraction(at: state)
        }
    }

    func setUpAnimationEdgeConstraint(to state: FloatingPanelState) -> (NSLayoutConstraint, CGFloat) {
        NSLayoutConstraint.deactivate(constraint: animationEdgeConstraint)

        let anchor = layout.stateAnchors[state] ?? FloatingPanelLayoutAnchor.hidden

        NSLayoutConstraint.deactivate(fullConstraints + halfConstraints + tipConstraints + offConstraints)
        NSLayoutConstraint.deactivate(constraint: interactionEdgeConstraint)
        interactionEdgeConstraint = nil

        let animationConstraint: NSLayoutConstraint
        var target = positionY(for: state)
        switch layout.anchoredPosition {
        case .top:
            if anchor.referenceGuide == .safeArea {
                if anchor.referenceEdge == .bottom {
                    let baseHeight = vc.view.bounds.height - safeAreaInsets.bottom
                    target = -(baseHeight - target)
                    animationConstraint = surfaceView.bottomAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.bottomAnchor,
                                                                              constant: -(baseHeight - edgeY(surfaceView.frame)))
                } else {
                    animationConstraint = surfaceView.bottomAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.topAnchor,
                                                                           constant: edgeY(surfaceView.frame) - safeAreaInsets.top)
                    target -= safeAreaInsets.top
                }
            } else {
                animationConstraint = surfaceView.bottomAnchor.constraint(equalTo: vc.view.topAnchor,
                                                                          constant: edgeY(surfaceView.frame))
            }
        case .bottom:
            if anchor.referenceGuide == .safeArea {
                if anchor.referenceEdge == .bottom {
                    let baseHeight = vc.view.bounds.height - safeAreaInsets.bottom
                    target = -(baseHeight - target)
                    animationConstraint = surfaceView.topAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.bottomAnchor,
                                                                           constant: -(baseHeight - edgeY(surfaceView.frame)))
                } else {
                    animationConstraint = surfaceView.topAnchor.constraint(equalTo: vc.fp_safeAreaLayoutGuide.topAnchor,
                                                                           constant: edgeY(surfaceView.frame) - safeAreaInsets.top)
                    target -= safeAreaInsets.top
                }
            } else {
                animationConstraint = surfaceView.topAnchor.constraint(equalTo: vc.view.topAnchor,
                                                                       constant: edgeY(surfaceView.frame))
            }
        }

        NSLayoutConstraint.activate([animationConstraint])
        self.animationEdgeConstraint = animationConstraint
        return (animationConstraint, target)
    }

    private func tearDownAnimationEdgeConstraint() {
        NSLayoutConstraint.deactivate(constraint: animationEdgeConstraint)
        animationEdgeConstraint = nil
    }

    // The method is separated from prepareLayout(to:) for the rotation support
    // It must be called in FloatingPanelController.traitCollectionDidChange(_:)
    func updateHeight() {
        guard let vc = vc else { return }
        NSLayoutConstraint.deactivate(constraint: heightConstraint)
        heightConstraint = nil

        if vc.contentMode == .fitToBounds {
            return
        }

        let anchor = layout.stateAnchors[self.edgeMostState]!
        if anchor is FloatingPanelIntrinsicLayoutAnchor {
            let heightMargin: CGFloat
            switch layout.anchoredPosition {
            case .bottom:
                heightMargin = safeAreaInsets.bottom
            case .top:
                heightMargin = safeAreaInsets.top
            }
            let constant: CGFloat
            switch anchor.referenceGuide {
            case .safeArea:
                constant = surfaceView.intrinsicContentSize.height + heightMargin
            case .superview:
                constant = surfaceView.intrinsicContentSize.height
            }
            heightConstraint = surfaceView.heightAnchor.constraint(equalToConstant: constant)
        } else {
            switch layout.anchoredPosition {
            case .top:
                heightConstraint = surfaceView.heightAnchor.constraint(equalToConstant: positionY(for: self.directionalMostState))
            case .bottom:
                heightConstraint = vc.view.heightAnchor.constraint(equalTo: surfaceView.heightAnchor, constant: positionY(for: self.directionalLeastState))
            }
        }
        NSLayoutConstraint.activate(constraint: heightConstraint)

        surfaceView.bottomOverflow = vc.view.bounds.height
    }

    func updateInteractiveEdgeConstraint(diff: CGFloat, overflow: Bool, with behavior: FloatingPanelBehavior) {
        defer {
            layoutSurfaceIfNeeded() // MUST be called to update `surfaceView.frame`
            log.debug("update edge -- surface edge Y = \(self.edgeY(self.surfaceView.presentationFrame))")
        }

        let minConst: CGFloat = max(positionY(for: directionalLeastState), 0.0) // The top boundary is equal to the related topAnchor.
        let maxConst: CGFloat = min(positionY(for: directionalMostState), surfaceView.superview!.bounds.height)

        var const = initialConst + diff

        // Rubberbanding top buffer
        if behavior.allowsRubberBanding?(for: .top) ?? false, const < minConst {
            let buffer = minConst - const
            const = minConst - rubberbandEffect(for: buffer, base: vc.view.bounds.height)
        }

        // Rubberbanding bottom buffer
        if behavior.allowsRubberBanding?(for: .bottom) ?? false, const > maxConst {
            let buffer = const - maxConst
            const = maxConst + rubberbandEffect(for: buffer, base: vc.view.bounds.height)
        }

        if overflow == false {
            const = min(max(const, minConst), maxConst)
        }

        interactionEdgeConstraint?.constant = const
    }

    // According to @chpwn's tweet: https://twitter.com/chpwn/status/285540192096497664
    // x = distance from the edge
    // c = constant value, UIScrollView uses 0.55
    // d = dimension, either width or height
    private func rubberbandEffect(for buffer: CGFloat, base: CGFloat) -> CGFloat {
        return (1.0 - (1.0 / ((buffer * 0.55 / base) + 1.0))) * base
    }

    func activateLayout(for state: FloatingPanelState, forceLayout: Bool = false) {
        defer {
            if forceLayout {
                layoutSurfaceIfNeeded()
                log.debug("activateLayout for \(state) -- surface.presentation = \(self.surfaceView.presentationFrame) surface.frame = \(self.surfaceView.frame)")
            } else {
                log.debug("activateLayout for \(state)")
            }
        }

        // Must deactivate `interactiveTopConstraint` here
        NSLayoutConstraint.deactivate(constraint: self.interactionEdgeConstraint)
        self.interactionEdgeConstraint = nil

        tearDownAnimationEdgeConstraint()

        NSLayoutConstraint.activate(fixedConstraints)

        if vc.contentMode == .fitToBounds {
            NSLayoutConstraint.activate(constraint: self.fitToBoundsConstraint)
        }

        var state = state

        setBackdropAlpha(of: state)

        if isValid(state) == false {
            state = layout.initialState
        }

        NSLayoutConstraint.deactivate(fullConstraints + halfConstraints + tipConstraints + offConstraints)
        switch state {
        case .full:
            NSLayoutConstraint.activate(fullConstraints)
        case .half:
            NSLayoutConstraint.activate(halfConstraints)
        case .tip:
            NSLayoutConstraint.activate(tipConstraints)
        case .hidden:
            NSLayoutConstraint.activate(offConstraints)
        default:
            break
        }
    }

    func isValid(_ state: FloatingPanelState) -> Bool {
        return activeStates.union([.hidden]).contains(state)
    }

    private func layoutSurfaceIfNeeded() {
        #if !TEST
        guard surfaceView.window != nil else { return }
        #endif
        surfaceView.superview?.layoutIfNeeded()
    }

    private func setBackdropAlpha(of target: FloatingPanelState) {
        if target == .hidden {
            self.backdropView.alpha = 0.0
        } else {
            self.backdropView.alpha = backdropAlpha(for: target)
        }
    }

    func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        return layout.backdropAlpha?(for: state) ?? defaultLayout.backdropAlpha(for: state)
    }

    func checkLayout() {
        // Verify layout configurations
        assert(activeStates.count > 0)
        assert(activeStates.contains(layout.initialState),
               "Does not include an initial state (\(layout.initialState)) in active states (\(activeStates))")
        let statePosOrder = activeStates.sorted(by: { positionY(for: $0) < positionY(for: $1) })
        assert(sortedDirectionalStates == statePosOrder,
               "Check your layout anchors because the state order(\(statePosOrder)) must be (\(sortedDirectionalStates))).")
    }

    func segument(at posY: CGFloat, forward: Bool) -> LayoutSegment {
        /// ----------------------->Y
        /// --> forward                <-- backward
        /// |-------|===o===|-------|  |-------|-------|===o===|
        /// |-------|-------x=======|  |-------|=======x-------|
        /// |-------|-------|===o===|  |-------|===o===|-------|
        /// pos: o/x, seguement: =

        let sortedStates = sortedDirectionalStates

        let upperIndex: Int?
        if forward {
            #if swift(>=4.2)
            upperIndex = sortedStates.firstIndex(where: { posY < positionY(for: $0) })
            #else
            upperIndex = sortedPositions.index(where: { posY < positionY(for: $0) })
            #endif
        } else {
            #if swift(>=4.2)
            upperIndex = sortedStates.firstIndex(where: { posY <= positionY(for: $0) })
            #else
            upperIndex = sortedPositions.index(where: { posY <= positionY(for: $0) })
            #endif
        }

        switch upperIndex {
        case 0:
            return LayoutSegment(lower: nil, upper: sortedStates.first)
        case let upperIndex?:
            return LayoutSegment(lower: sortedStates[upperIndex - 1], upper: sortedStates[upperIndex])
        default:
            return LayoutSegment(lower: sortedStates[sortedStates.endIndex - 1], upper: nil)
        }
    }
}
