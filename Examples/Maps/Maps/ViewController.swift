//  Copyright © 2018 Shin Yamamoto. All rights reserved.

import UIKit
import MapKit
import FloatingPanel

class ViewController: UIViewController, MKMapViewDelegate {
    lazy var fpc = FloatingPanelController()
    lazy var fpcDelegate: FloatingPanelControllerDelegate = (traitCollection.userInterfaceIdiom == .pad) ? PadPanelDelegate(owner: self) : PhonePanelDelegate(owner: self)
    lazy var searchVC = storyboard?.instantiateViewController(withIdentifier: "SearchPanel") as! SearchPanelViewController

    @IBOutlet weak var mapView: MKMapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        fpc.contentMode = .fitToBounds
        fpc.delegate = fpcDelegate

        // Set a content view controller
        fpc.set(contentViewController: searchVC)
        fpc.track(scrollView: searchVC.tableView)

        setupMapView()

        switch traitCollection.userInterfaceIdiom {
        case .pad:
            layoutPanelForPad()
        default:
            layoutPanelForPhone()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Must be here
        searchVC.searchBar.delegate = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        teardownMapView()
    }

    func setupMapView() {
        let center = CLLocationCoordinate2D(latitude: 37.623198015869235,
                                            longitude: -122.43066818432008)
        let span = MKCoordinateSpan(latitudeDelta: 0.4425100023575723,
                                    longitudeDelta: 0.28543697435880233)
        let region = MKCoordinateRegion(center: center, span: span)
        mapView.region = region
        mapView.showsCompass = true
        mapView.showsUserLocation = true
        mapView.delegate = self
    }

    func teardownMapView() {
        // Prevent a crash
        mapView.delegate = nil
        mapView = nil
    }

    func layoutPanelForPad() {
        view.addSubview(fpc.view)
        addChild(fpc)

        fpc.behavior = SearchPaneliPadBehavior()

        fpc.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        fpc.view.layer.cornerRadius = 10.0
        fpc.view.frame = view.bounds // Needed for a correct safe area configuration
        fpc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fpc.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8.0),
            fpc.view.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 8.0),
            fpc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0.0),
            fpc.view.widthAnchor.constraint(equalToConstant: 375),
        ])
        fpc.show(animated: false) { [weak self] in
            guard let self = self else { return }
            self.didMove(toParent: self)
        }

        fpc.surfaceView.grabbableAreaSize = CGSize(width: fpc.surfaceView.bounds.width,
                                                   height: 44.0)
        appearanceForPad()
    }

    func layoutPanelForPhone() {
        fpc.addPanel(toParent: self, animated: true)
    }

    func appearanceForPad() {
        fpc.view.clipsToBounds = false
        let appearance = FloatingPanelSurfaceAppearance()
        appearance.cornerRadius = 8.0
        let shadow = FloatingPanelSurfaceAppearance.Shadow()
        shadow.color = UIColor.black
        shadow.offset = CGSize(width: 0, height: 16)
        shadow.radius = 16
        shadow.spread = 8
        appearance.shadows = [shadow]
        appearance.backgroundColor = .clear
        fpc.surfaceView.appearance = appearance
    }
}

// MARK: UISearchBarDelegate

extension ViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        searchBar.showsCancelButton  = false
        searchVC.hideHeader(animated: true)
        fpc.move(to: .half, animated: true)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.showsCancelButton = true
        searchVC.showHeader(animated: true)
        searchVC.tableView.alpha = 1.0
        fpc.move(to: .full, animated: true)
    }
}

// MARK: - iPhone

class PhonePanelDelegate: NSObject, FloatingPanelControllerDelegate {
    unowned let owner: ViewController

    init(owner: ViewController) {
        self.owner = owner
    }

    func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        switch newCollection.verticalSizeClass {
        case .compact:
            let appearance = vc.surfaceView.appearance
            appearance.borderWidth = 1.0 / owner.traitCollection.displayScale
            appearance.borderColor = UIColor.black.withAlphaComponent(0.2)
            vc.surfaceView.appearance = appearance
            return SearchPanelLandscapeLayout()
        default:
            let appearance = vc.surfaceView.appearance
            appearance.borderWidth = 0.0
            appearance.borderColor = nil
            vc.surfaceView.appearance = appearance
            return FloatingPanelBottomLayout()
        }
    }

    func floatingPanelDidMove(_ vc: FloatingPanelController) {
        debugPrint("surfaceEdgeLocation: ", vc.surfaceEdgeLocation)
        let loc = vc.surfaceEdgeLocation

        if vc.isDecelerating == false {
            let minY = vc.surfaceEdgeLocation(for: .full).y - 6.0
            let maxY = vc.surfaceEdgeLocation(for: .tip).y + 6.0
            vc.surfaceEdgeLocation = CGPoint(x: loc.x, y: min(max(loc.y, minY), maxY))
        }

        let tipY = vc.surfaceEdgeLocation(for: .tip).y
        if loc.y > tipY - 44.0 {
            let progress = max(0.0, min((tipY  - loc.y) / 44.0, 1.0))
            owner.searchVC.tableView.alpha = progress
        } else {
            owner.searchVC.tableView.alpha = 1.0
        }
        debugPrint("NearbyState : ",vc.nearbyState)
    }

    func floatingPanelWillBeginDragging(_ vc: FloatingPanelController) {
        if vc.state == .full {
            owner.searchVC.searchBar.showsCancelButton = false
            owner.searchVC.searchBar.resignFirstResponder()
        }
    }

    func floatingPanelWillEndDragging(_ vc: FloatingPanelController, withVelocity velocity: CGPoint, targetState: UnsafeMutablePointer<FloatingPanelState>) {
        if targetState.pointee != .full {
            owner.searchVC.hideHeader(animated: true)
        }
    }
}

class SearchPanelLandscapeLayout: FloatingPanelLayout {
    let anchorPosition: FloatingPanelPosition  = .bottom
    let initialState: FloatingPanelState = .tip
    var stateAnchors: [FloatingPanelState : FloatingPanelLayoutAnchoring] {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 16.0, edge: .top, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 69.0, edge: .bottom, referenceGuide: .safeArea),
        ]
    }
    func prepareLayout(surfaceView: UIView, in view: UIView) -> [NSLayoutConstraint] {
        if #available(iOS 11.0, *) {
            return [
                surfaceView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 8.0),
                surfaceView.widthAnchor.constraint(equalToConstant: 291),
            ]
        } else {
            return [
                surfaceView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 8.0),
                surfaceView.widthAnchor.constraint(equalToConstant: 291),
            ]
        }
    }
}

// MARK: - iPad

class PadPanelDelegate: NSObject, FloatingPanelControllerDelegate {
    class PadBottomLayout: FloatingPanelBottomLayout {
        override func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
            return 0.0
        }
    }

    unowned let owner: ViewController

    init(owner: ViewController) {
        self.owner = owner
    }

    func floatingPanel(_ vc: FloatingPanelController, layoutFor size: CGSize) -> FloatingPanelLayout {
        let isLandscape: Bool = {
            if #available(iOS 13.0, *) {
                return vc.view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
            } else {
                return UIApplication.shared.statusBarOrientation.isLandscape
            }
        }()
        if isLandscape {
            return SearchPaneliPadLayout()
        } else {
            return PadBottomLayout()
        }
    }

    func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        SearchPaneliPadLayout()
    }
}

class SearchPaneliPadLayout: FloatingPanelLayout {
    let anchorPosition: FloatingPanelPosition  = .top
    let initialState: FloatingPanelState = .tip
    var stateAnchors: [FloatingPanelState : FloatingPanelLayoutAnchoring] {
        return [
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 80.0, edge: .top, referenceGuide: .superview),
            .half: FloatingPanelLayoutAnchor(absoluteInset: 200.0, edge: .top, referenceGuide: .superview),
            .full: FloatingPanelLayoutAnchor(absoluteInset: 60.0, edge: .bottom, referenceGuide: .superview),
        ]
    }
    func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        return 0.0
    }
}

class SearchPaneliPadBehavior: FloatingPanelBehavior {
    var springDecelerationRate: CGFloat {
        return UIScrollView.DecelerationRate.fast.rawValue - 0.003
    }
    var springResponseTime: CGFloat {
        return 0.3
    }
    var momentumProjectionRate: CGFloat {
        return UIScrollView.DecelerationRate.fast.rawValue
    }
    func shouldProjectMomentum(_ fpc: FloatingPanelController, to proposedTargetPosition: FloatingPanelState) -> Bool {
        return true
    }
}
