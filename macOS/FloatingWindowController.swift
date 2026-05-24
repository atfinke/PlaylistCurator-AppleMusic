//
//  FloatingWindowController.swift
//  PlaylistCurator-AppleMusic
//

import Cocoa
import SwiftUI

class FloatingWindowController: NSWindowController {

    // MARK: - Properties -

    let manager = MusicAppManager()

    // MARK: - View Life Cycle -

    override func windowDidLoad() {
        super.windowDidLoad()

        guard let window = window, let contentView = window.contentView else { fatalError() }

        window.level = .floating
        window.titleVisibility = .hidden
        window.styleMask.remove(.titled)
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.collectionBehavior = .canJoinAllSpaces

        let hostingView = NSHostingView(rootView: ContentView(manager: manager))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView = NSVisualEffectView()
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.addSubview(hostingView)
        visualEffectView.wantsLayer = true
        visualEffectView.state = .active
        visualEffectView.layer?.cornerRadius = 10.0

        window.contentView?.addSubview(visualEffectView)

        let constraints = [
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 94),
            contentView.widthAnchor.constraint(equalToConstant: 120)
        ]
        NSLayoutConstraint.activate(constraints)
    }
}
