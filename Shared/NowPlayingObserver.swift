//
//  NowPlayingObserver.swift
//  PlaylistCurator-AppleMusic
//
//  Subscribes to Music.app's playerInfo distributed notification — fired
//  on every play/pause/track-change. No polling needed.
//

import Foundation

final class NowPlayingObserver: @unchecked Sendable {
    // NSObjectProtocol from DistributedNotificationCenter isn't Sendable, but
    // the token is opaque and only used for removeObserver in deinit. @unchecked
    // is the conventional escape hatch for foundation tokens like this.

    static let notificationName = Notification.Name("com.apple.Music.playerInfo")

    private let token: NSObjectProtocol

    init(handler: @Sendable @escaping () -> Void) {
        token = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(token)
    }
}
