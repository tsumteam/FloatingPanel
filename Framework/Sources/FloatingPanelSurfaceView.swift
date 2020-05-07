//
//  Created by Shin Yamamoto on 2018/09/26.
//  Copyright © 2018 Shin Yamamoto. All rights reserved.
//

import UIKit

@objcMembers
public class FloatingPanelSurfaceAppearance: NSObject {
    @objc(FloatingPanelSurfaceAppearanceShadow)
    public class Shadow: NSObject {
        /// A Boolean indicating whether the surface shadow is displayed.
        @objc
        public var hidden: Bool = false

        /// The color of the surface shadow.
        @objc
        public var color: UIColor = .black

        /// The offset (in points) of the surface shadow.
        @objc
        public var offset: CGSize = CGSize(width: 0.0, height: 1.0)

        /// The opacity of the surface shadow.
        @objc
        public var opacity: Float = 0.2

        /// The blur radius (in points) used to render the surface shadow.
        @objc
        public var radius: CGFloat = 3

        /// TODO: doc comment
        @objc
        public var spread: CGFloat = 0

    }
    /// The background color.
    public var backgroundColor: UIColor? = {
        if #available(iOS 13, *) {
            return UIColor.systemBackground
        } else {
            return UIColor.white
        }
    }()

    /// The radius to use when drawing top rounded corners.
    ///
    /// `self.contentView` is masked with the top rounded corners automatically on iOS 11 and later.
    /// On iOS 10, they are not automatically masked because of a UIVisualEffectView issue. See https://forums.developer.apple.com/thread/50854
    public var cornerRadius: CGFloat = 0.0

    public var shadows: [Shadow] = [Shadow()]

    /// The width of the surface border.
    public var borderColor: UIColor?

    /// The color of the surface border.
    public var borderWidth: CGFloat = 0.0
}

/// A view that presents a surface interface in a floating panel.
@objcMembers
public class FloatingPanelSurfaceView: UIView {
    /// A FloatingPanelGrabberView object displayed at the top of the surface view.
    ///
    /// To use a custom grabber handle, hide this and then add the custom one
    /// to the surface view at appropriate coordinates.
    public let grabber: FloatingPanelGrabberView = FloatingPanelGrabberView()

    /// Offset of the grabber handle from the interactive edge.
    public var grabberPaddingFromEdge: CGFloat = 6.0 { didSet {
        setNeedsUpdateConstraints()
    } }

    /// The height of the grabber bar area
    public var topGrabberBarHeight: CGFloat {
        return grabberPaddingFromEdge * 2 + grabberHandleHeight
    }

    /// Grabber view width and height
    public var grabberHandleWidth: CGFloat = 36.0 { didSet {
        setNeedsUpdateConstraints()
    } }
    public var grabberHandleHeight: CGFloat = 5.0 { didSet {
        setNeedsUpdateConstraints()
    } }

    /// A root view of a content view controller
    public weak var contentView: UIView!

    /// The content insets specifying the insets around the content view.
    public var contentPadding: UIEdgeInsets = .zero {
        didSet {
            // Needs update constraints
            self.setNeedsUpdateConstraints()
        }
    }

    var bottomOverflow: CGFloat = 0.0 // Must not call setNeedsLayout()

    public override var backgroundColor: UIColor? {
        get { return appearance.backgroundColor }
        set { appearance.backgroundColor = newValue; setNeedsLayout() }
    }

    public var appearance = FloatingPanelSurfaceAppearance() { didSet {
        shadowLayers = appearance.shadows.map { _ in CAShapeLayer() }
        setNeedsLayout()
    }}

    /// The margins to use when laying out the container view wrapping content.
    public var contentMargins: UIEdgeInsets = .zero { didSet {
        setNeedsUpdateConstraints()
    } }

    /// The view presents an actual surface shape.
    ///
    /// It renders the background color, border line and top rounded corners,
    /// specified by other properties. The reason why they're not be applied to
    /// a content view directly is because it avoids any side-effects to the
    /// content view.
    public let containerView: UIView = UIView()

    @available(*, unavailable, renamed: "containerView")
    public var backgroundView: UIView!

    var position: FloatingPanelPosition = .bottom {
        didSet {
            guard position != oldValue else { return }
            NSLayoutConstraint.deactivate([containerViewEdgeConstraint,
                                           grabberHandleEdgePaddingConstraint])
            switch position {
            case .top:
                containerViewEdgeConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentMargins.bottom)
                grabberHandleEdgePaddingConstraint = grabber.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -grabberPaddingFromEdge)
            case .bottom:
                containerViewEdgeConstraint = containerView.topAnchor.constraint(equalTo: topAnchor, constant: contentMargins.top)
                grabberHandleEdgePaddingConstraint = grabber.topAnchor.constraint(equalTo: topAnchor, constant: grabberPaddingFromEdge)
            }
            NSLayoutConstraint.activate([containerViewEdgeConstraint,
                                         grabberHandleEdgePaddingConstraint])
        }
    }

    var grabberAreaFrame: CGRect {
        switch position {
        case .top:
            let height = topGrabberBarHeight * 2
            return CGRect(x: bounds.minX,
                          y: bounds.maxY - height,
                          width: bounds.width,
                          height: height)
        case .bottom:
            return CGRect(x: bounds.minX,
                          y: bounds.minY,
                          width: bounds.width,
                          height: topGrabberBarHeight * 2)
        }
    }

    private lazy var containerViewEdgeConstraint = containerView.topAnchor.constraint(equalTo: topAnchor, constant: contentMargins.top)
    private lazy var containerViewHeightConstraint = containerView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 1.0)
    private lazy var containerViewLeftConstraint = containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0.0)
    private lazy var containerViewRightConstraint = containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0.0)

    /// The content view top constraint
    private var contentViewTopConstraint: NSLayoutConstraint?
    /// The content view left constraint
    private var contentViewLeftConstraint: NSLayoutConstraint?
    /// The content right constraint
    private var contentViewRightConstraint: NSLayoutConstraint?
    /// The content height constraint
    private var contentViewHeightConstraint: NSLayoutConstraint?

    private lazy var grabberHandleWidthConstraint = grabber.widthAnchor.constraint(equalToConstant: grabberHandleWidth)
    private lazy var grabberHandleHeightConstraint = grabber.heightAnchor.constraint(equalToConstant: grabberHandleHeight)
    private lazy var grabberHandleEdgePaddingConstraint = grabber.topAnchor.constraint(equalTo: topAnchor, constant: grabberPaddingFromEdge)

    private var shadowLayers: [CALayer] = [] {
        willSet {
            for shadowLayer in shadowLayers {
                shadowLayer.removeFromSuperlayer()
            }
        }
        didSet {
            for shadowLayer in shadowLayers {
                layer.insertSublayer(shadowLayer, at: 0)
            }
        }
    }

    public override class var requiresConstraintBasedLayout: Bool { return true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubViews()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        addSubViews()
    }

    private func addSubViews() {
        super.backgroundColor = .clear
        self.clipsToBounds = false

        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            containerViewEdgeConstraint,
            containerViewLeftConstraint,
            containerViewRightConstraint,
            containerViewHeightConstraint,
        ])

        addSubview(grabber)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grabberHandleWidthConstraint,
            grabberHandleHeightConstraint,
            grabberHandleEdgePaddingConstraint,
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])

        shadowLayers = appearance.shadows.map { _ in CALayer() }
    }

    public override func updateConstraints() {
        switch position {
        case .top:
            containerViewEdgeConstraint.constant = contentMargins.bottom
            containerViewHeightConstraint.constant = (contentMargins.top == 0) ? bottomOverflow : -(contentMargins.top + contentMargins.bottom)
        case .bottom:
            containerViewEdgeConstraint.constant = contentMargins.top
            containerViewHeightConstraint.constant = (contentMargins.bottom == 0) ? bottomOverflow : -(contentMargins.top + contentMargins.bottom)
        }
        containerViewLeftConstraint.constant = contentMargins.left
        containerViewRightConstraint.constant = -contentMargins.right

        contentViewTopConstraint?.constant = contentMargins.top + contentPadding.top
        contentViewLeftConstraint?.constant = contentMargins.left + contentPadding.left
        contentViewRightConstraint?.constant = contentMargins.right + contentPadding.right
        contentViewHeightConstraint?.constant = -(contentMargins.top + contentMargins.bottom + contentPadding.top + contentPadding.bottom)

        switch position {
        case .top:
            grabberHandleEdgePaddingConstraint.constant = -grabberPaddingFromEdge
        case .bottom:
            grabberHandleEdgePaddingConstraint.constant = grabberPaddingFromEdge
        }
        grabberHandleWidthConstraint.constant = grabberHandleWidth
        grabberHandleHeightConstraint.constant = grabberHandleHeight

        super.updateConstraints()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        log.debug("surface view frame = \(frame)")

        containerView.backgroundColor = appearance.backgroundColor

        updateShadow()
        updateCornerRadius()
        updateBorder()
    }

    public override var intrinsicContentSize: CGSize {
        let fittingSize = UIView.layoutFittingCompressedSize
        let contentSize = contentView?.systemLayoutSizeFitting(fittingSize) ?? .zero
        return CGSize(width: contentMargins.horizontalInset + contentPadding.horizontalInset + contentSize.width,
                      height: contentMargins.verticalInset + contentPadding.verticalInset + contentSize.height)
    }

    private func updateShadow() {
        for (i, shadow) in appearance.shadows.enumerated() {
            let shadowLayer = shadowLayers[i]

            shadowLayer.backgroundColor = UIColor.clear.cgColor
            shadowLayer.frame = layer.bounds

            let spread = shadow.spread
            let shadowPath = UIBezierPath(roundedRect: containerView.frame.insetBy(dx: -spread,
                                                                                   dy: -spread),
                                          byRoundingCorners: [.allCorners],
                                          cornerRadii: CGSize(width: appearance.cornerRadius, height: 0))
            shadowLayer.shadowPath = shadowPath.cgPath
            shadowLayer.shadowColor = shadow.color.cgColor
            shadowLayer.shadowOffset = shadow.offset
            // A shadow.radius value isn't manipulated by a scale(i.e. the display scale). It should be applied to the value by itself.
            shadowLayer.shadowRadius = shadow.radius
            shadowLayer.shadowOpacity = shadow.opacity

            let mask = CAShapeLayer()
            let path = UIBezierPath(roundedRect: containerView.frame,
                                    byRoundingCorners: [.allCorners],
                                    cornerRadii: CGSize(width: appearance.cornerRadius, height: 0))
            let size = window?.bounds.size ?? CGSize(width: 1000.0, height: 1000.0)
            path.append(UIBezierPath(rect: layer.bounds.insetBy(dx: -size.width,
                                                                dy: -size.height)))
            mask.fillRule = .evenOdd
            mask.path = path.cgPath
            if #available(iOSApplicationExtension 13.0, *) {
                mask.cornerCurve = containerView.layer.cornerCurve
            }
            shadowLayer.mask = mask
        }
    }

    private func updateCornerRadius() {
        containerView.layer.cornerRadius = appearance.cornerRadius
        guard containerView.layer.cornerRadius != 0.0 else {
            containerView.layer.masksToBounds = false
            return
        }
        containerView.layer.masksToBounds = true
        guard contentMargins.bottom == 0 else { return }
        if #available(iOS 11, *) {
            // Don't use `contentView.clipToBounds` because it prevents content view from expanding the height of a subview of it
            // for the bottom overflow like Auto Layout settings of UIVisualEffectView in Main.storyboard of Example/Maps.
            // Because the bottom of contentView must be fit to the bottom of a screen to work the `safeLayoutGuide` of a content VC.
            switch position {
            case .top:
                contentView?.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .bottom:
                contentView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            }
        } else {
            // Can't use `containerView.layer.mask` because of a UIVisualEffectView issue in iOS 10, https://forums.developer.apple.com/thread/50854
            // Instead, a user should display rounding corners appropriately.
        }
    }

    private func updateBorder() {
        containerView.layer.borderColor = appearance.borderColor?.cgColor
        containerView.layer.borderWidth = appearance.borderWidth
    }

    func set(contentView: UIView) {
        containerView.addSubview(contentView)
        self.contentView = contentView
        /* contentView.frame = bounds */ // MUST NOT: Because the top safe area inset of a content VC will be incorrect.
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let topConstraint = contentView.topAnchor.constraint(equalTo: topAnchor, constant: contentMargins.top + contentPadding.top)
        let leftConstraint = contentView.leftAnchor.constraint(equalTo: leftAnchor, constant: contentMargins.left + contentPadding.left)
        let rightConstraint = rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: contentMargins.right + contentPadding.right)
        let heightPadding = contentMargins.top + contentMargins.bottom + contentPadding.top + contentPadding.bottom
        let heightConstraint = contentView.heightAnchor.constraint(equalTo: heightAnchor, constant: -heightPadding)
        NSLayoutConstraint.activate([
            topConstraint,
            leftConstraint,
            rightConstraint,
            heightConstraint,
        ])
        self.contentViewTopConstraint = topConstraint
        self.contentViewLeftConstraint = leftConstraint
        self.contentViewRightConstraint = rightConstraint
        self.contentViewHeightConstraint = heightConstraint
    }
}
