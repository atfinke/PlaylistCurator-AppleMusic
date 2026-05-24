//
//  MusicAppBridge.swift
//  PlaylistCurator-AppleMusic
//
//  Talks to Apple Music.app via NSAppleScript. Main-actor isolated because
//  NSAppleScript is not documented as thread-safe and Music.app's scripting
//  surface is brittle when invoked off-main.
//

import AppKit
import Foundation

/// Snapshot of Music.app's playback state at a moment in time.
struct NowPlaying: Equatable, Sendable {
    var trackName: String
    var artistName: String
    var albumName: String
    /// Track's persistent ID (16-char hex), unique within the library.
    var trackPersistentID: String
    /// Database ID — numeric, used to address specific tracks within a playlist.
    var trackDatabaseID: Int
    /// Track duration in seconds.
    var durationSeconds: Double
    /// Name of the current source (playlist) Music.app is playing from.
    var sourceName: String
    /// Persistent ID of the source playlist. Empty if source isn't a real user playlist.
    var playlistPersistentID: String
    /// True iff source is a real, mutable user playlist (not Library / smart / radio).
    var isMutablePlaylist: Bool
    /// Artwork bytes (PNG/JPEG). nil if unavailable.
    var artworkData: Data?
}

@MainActor
protocol MusicAppBridging: AnyObject {
    func fetchNowPlaying() throws -> NowPlaying?
    func deleteTrack(databaseID: Int, fromPlaylistPersistentID playlistPersistentID: String) throws
    func nextTrack() throws
    func seek(toFraction fraction: Double) throws
}

enum MusicAppBridgeError: LocalizedError {
    case musicNotRunning
    case scriptFailed(String)
    case unexpectedResult

    var errorDescription: String? {
        switch self {
        case .musicNotRunning:
            return "Apple Music isn't running. Open Music and play something."
        case .scriptFailed(let detail):
            return "Music script failed: \(detail)"
        case .unexpectedResult:
            return "Music returned an unexpected result."
        }
    }
}

/// Concrete bridge using NSAppleScript. Pre-compiles the hot-path scripts at
/// init; dynamic scripts (per-track ops) compile on each call.
@MainActor
final class MusicAppBridge: MusicAppBridging {

    private let nowPlayingScript: NSAppleScript
    private let nextTrackScript: NSAppleScript

    init() {
        self.nowPlayingScript = Self.compile(Self.nowPlayingSource)
        self.nextTrackScript = Self.compile(Self.nextTrackSource)
    }

    // MARK: - Public API -

    func fetchNowPlaying() throws -> NowPlaying? {
        let result = try run(nowPlayingScript)
        guard let raw = result.stringValue, !raw.isEmpty else { return nil }
        return parseNowPlaying(raw)
    }

    func deleteTrack(databaseID: Int, fromPlaylistPersistentID playlistPersistentID: String) throws {
        let source = Self.deleteSource(databaseID: databaseID, playlistPersistentID: playlistPersistentID)
        try runExpectingTrue(source)
    }

    func nextTrack() throws {
        _ = try run(nextTrackScript)
    }

    func seek(toFraction fraction: Double) throws {
        let source = Self.seekSource(fraction: fraction)
        try runExpectingTrue(source)
    }

    // MARK: - Script runners -

    @discardableResult
    private func run(_ script: NSAppleScript) throws -> NSAppleEventDescriptor {
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err {
            throw MusicAppBridgeError.scriptFailed(String(describing: err))
        }
        return result
    }

    private func runExpectingTrue(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw MusicAppBridgeError.scriptFailed("failed to construct NSAppleScript")
        }
        let result = try run(script)
        guard result.stringValue == "1" else {
            throw MusicAppBridgeError.unexpectedResult
        }
    }

    private static func compile(_ source: String) -> NSAppleScript {
        guard let script = NSAppleScript(source: source) else {
            fatalError("Failed to construct NSAppleScript")
        }
        var err: NSDictionary?
        script.compileAndReturnError(&err)
        if let err {
            fatalError("Failed to compile AppleScript: \(err)")
        }
        return script
    }

    // MARK: - Script sources -

    private static let nowPlayingSource = #"""
    on safeGet(theProperty, fallback)
        try
            return theProperty as string
        on error
            return fallback
        end try
    end safeGet

    tell application "Music"
        if not running then return ""
        try
            set t to current track
        on error
            return ""
        end try
        set src to ""
        set srcPID to ""
        set isMutable to false
        try
            set cp to current playlist
            set src to name of cp
            try
                set srcPID to persistent ID of cp
            end try
            try
                if (special kind of cp) is none and (smart of cp) is false then
                    set isMutable to true
                end if
            end try
        end try
        set trName to my safeGet(name of t, "")
        set trArt to my safeGet(artist of t, "")
        set trAlb to my safeGet(album of t, "")
        set trPID to my safeGet(persistent ID of t, "")
        set trDBID to database ID of t
        set trDur to duration of t
        set artPath to ""
        try
            set artworkList to artworks of t
            if (count of artworkList) > 0 then
                set firstArt to item 1 of artworkList
                set rawArtworkData to raw data of firstArt
                set tmpPath to (POSIX path of (path to temporary items)) & "pcm_artwork_" & trPID
                set fh to open for access POSIX file tmpPath with write permission
                set eof of fh to 0
                write rawArtworkData to fh
                close access fh
                set artPath to tmpPath
            end if
        end try
        set TAB to ASCII character 9
        return trName & TAB & trArt & TAB & trAlb & TAB & trPID & TAB & trDBID & TAB & trDur & TAB & src & TAB & srcPID & TAB & (isMutable as string) & TAB & artPath
    end tell
    """#

    private static let nextTrackSource = #"""
    tell application "Music"
        if not running then return "0"
        try
            next track
            return "1"
        on error
            return "0"
        end try
    end tell
    """#

    private static func seekSource(fraction: Double) -> String {
        let clamped = max(0.0, min(1.0, fraction))
        return """
        tell application "Music"
            if not running then return "0"
            try
                set t to current track
                set dur to duration of t
                set player position to dur * \(clamped)
                return "1"
            on error
                return "0"
            end try
        end tell
        """
    }

    private static func deleteSource(databaseID: Int, playlistPersistentID: String) -> String {
        return """
        tell application "Music"
            set pl to first user playlist whose persistent ID is "\(escape(playlistPersistentID))"
            set candidates to (every track of pl whose database ID is \(databaseID))
            if (count of candidates) is 0 then return "0"
            delete (item 1 of candidates)
            return "1"
        end tell
        """
    }

    /// Persistent IDs are hex (no quotes or backslashes), but escape defensively.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Parse -

    private func parseNowPlaying(_ raw: String) -> NowPlaying? {
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 10 else { return nil }
        var artwork: Data?
        let artPath = parts[9]
        if !artPath.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: artPath)) {
            artwork = data
            try? FileManager.default.removeItem(atPath: artPath)
        }
        return NowPlaying(
            trackName: parts[0],
            artistName: parts[1],
            albumName: parts[2],
            trackPersistentID: parts[3],
            trackDatabaseID: Int(parts[4]) ?? 0,
            durationSeconds: Double(parts[5]) ?? 0,
            sourceName: parts[6],
            playlistPersistentID: parts[7],
            isMutablePlaylist: parts[8] == "true",
            artworkData: artwork
        )
    }
}
