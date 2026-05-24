//
//  MusicAppManager.swift
//  PlaylistCurator-AppleMusic
//

import AppKit
import SwiftUI

@MainActor
@Observable
final class MusicAppManager {

    // MARK: - Published state -

    /// Current track display name. "-" when nothing playing.
    var nowPlayingTrackName: String = "-"
    /// Current source (playlist) name. "-" when none.
    var nowPlayingSourceName: String = "-"
    /// Album art as a SwiftUI Image. nil if unavailable.
    var nowPlayingTrackImage: Image?
    /// True iff the current source is a mutable user playlist (remove enabled).
    var isRemovable: Bool = false
    /// Last action's status — drives a brief error toast.
    var lastActionFlash: ActionFlash?

    enum ActionFlash: Equatable, Sendable {
        case kept
        case removed
        case seeked
        case failed(String)
    }

    // MARK: - Private state -

    private let bridge: any MusicAppBridging
    private var observer: NowPlayingObserver?
    private var currentSnapshot: NowPlaying?
    private var isBusy = false

    // MARK: - Init -

    init(bridge: (any MusicAppBridging)? = nil) {
        self.bridge = bridge ?? MusicAppBridge()
        Task { await self.refresh() }
        observer = NowPlayingObserver { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - User actions -

    func keepTrack() async {
        await guarded {
            do {
                try self.bridge.nextTrack()
                self.lastActionFlash = .kept
            } catch {
                self.lastActionFlash = .failed(error.localizedDescription)
            }
        }
    }

    func removeTrack() async {
        guard let snap = currentSnapshot else { return }
        guard snap.isMutablePlaylist, !snap.playlistPersistentID.isEmpty else {
            lastActionFlash = .failed("Not playing from a user playlist")
            return
        }
        await guarded {
            // Advance FIRST so Music.app retains a valid current-track reference;
            // deleting the actively-playing track invalidates the player state.
            do {
                try self.bridge.nextTrack()
            } catch {
                self.lastActionFlash = .failed("Skip failed: \(error.localizedDescription)")
                return
            }
            do {
                try self.bridge.deleteTrack(
                    databaseID: snap.trackDatabaseID,
                    fromPlaylistPersistentID: snap.playlistPersistentID
                )
                self.lastActionFlash = .removed
            } catch {
                self.lastActionFlash = .failed(error.localizedDescription)
            }
        }
    }

    func seekToMidpoint() async {
        await guarded {
            do {
                try self.bridge.seek(toFraction: 0.5)
                self.lastActionFlash = .seeked
            } catch {
                self.lastActionFlash = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - State sync -

    func refresh() async {
        do {
            let snap = try bridge.fetchNowPlaying()
            apply(snap)
        } catch {
            lastActionFlash = .failed(error.localizedDescription)
        }
    }

    private func apply(_ snap: NowPlaying?) {
        currentSnapshot = snap
        guard let snap else {
            nowPlayingTrackName = "-"
            nowPlayingSourceName = "-"
            nowPlayingTrackImage = nil
            isRemovable = false
            return
        }
        nowPlayingTrackName = snap.trackName.isEmpty ? "-" : snap.trackName
        nowPlayingSourceName = snap.sourceName.isEmpty ? "-" : snap.sourceName
        isRemovable = snap.isMutablePlaylist && !snap.playlistPersistentID.isEmpty
        if let data = snap.artworkData, let image = NSImage(data: data) {
            nowPlayingTrackImage = Image(nsImage: image)
        } else {
            nowPlayingTrackImage = nil
        }
    }

    /// Serialises user actions so a rapid double-click doesn't fire twice.
    private func guarded(_ body: @MainActor () async -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await body()
    }
}
