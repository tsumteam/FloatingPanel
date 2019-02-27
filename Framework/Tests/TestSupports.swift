//
//  Created by Shin Yamamoto on 2019/06/27.
//  Copyright © 2019 scenee. All rights reserved.
//

import Foundation
@testable import FloatingPanel

func waitRunLoop(secs: TimeInterval = 0) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: secs))
}

extension FloatingPanelController {
    func showForTest() {
        loadViewIfNeeded()
        view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        show(animated: false, completion: nil)
    }
}

class FloatingPanelTestDelegate: FloatingPanelControllerDelegate {
    var position: FloatingPanelState = .hidden
    func floatingPanelDidChangePosition(_ vc: FloatingPanelController) {
        position = vc.state
    }
}

class FloatingPanelTestLayout: FloatingPanelLayout {
    var initialState: FloatingPanelState {
        return .half
    }
    var position: FloatingPanelPosition {
        return .bottom
    }
    var referenceGuide: FloatingPanelLayoutReferenceGuide {
        return .superview
    }
    var layoutAnchors: [FloatingPanelState : FloatingPanelLayoutAnchoring] {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 20.0, edge: .top, referenceGuide: referenceGuide),
            .half: FloatingPanelLayoutAnchor(absoluteInset: 250.0, edge: .bottom, referenceGuide: referenceGuide),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 60.0, edge: .bottom, referenceGuide: referenceGuide),
        ]
    }
}

class FloatingPanelTop2BottomTestLayout: FloatingPanelLayout {
    var initialState: FloatingPanelState {
        return .half
    }
    var position: FloatingPanelPosition {
        return .top
    }
    var referenceGuide: FloatingPanelLayoutReferenceGuide {
        return .superview
    }
    var layoutAnchors: [FloatingPanelState : FloatingPanelLayoutAnchoring] {
        return [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 0.0, edge: .bottom, referenceGuide: referenceGuide),
            .half: FloatingPanelLayoutAnchor(absoluteInset: 250.0, edge: .top, referenceGuide: referenceGuide),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 60.0, edge: .top, referenceGuide: referenceGuide),
        ]
    }
}
