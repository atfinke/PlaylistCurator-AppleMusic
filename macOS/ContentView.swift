//
//  ContentView.swift
//  PlaylistCurator-AppleMusic
//

import SwiftUI

private struct AlbumView: View {
    let image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable()
            } else {
                Rectangle()
                    .fill(.tertiary)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    )
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ActionButton: View {
    let color: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(enabled ? color : Color.gray.opacity(0.4))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
    }
}

struct ContentView: View {

    var manager: MusicAppManager

    var body: some View {
        HStack(spacing: 8) {
            VStack {
                ActionButton(color: Color(red: 100/255, green: 210/255, blue: 110/255),
                             enabled: true) {
                    Task(priority: .userInitiated) { await manager.keepTrack() }
                }
                Spacer()
                ActionButton(color: .red,
                             enabled: manager.isRemovable) {
                    Task(priority: .userInitiated) { await manager.removeTrack() }
                }
            }
            .frame(height: 40)
            .padding(.trailing, 2)

            Button {
                Task(priority: .userInitiated) { await manager.seekToMidpoint() }
            } label: {
                AlbumView(image: manager.nowPlayingTrackImage)
            }
            .buttonStyle(PlainButtonStyle())
            .help(manager.nowPlayingTrackName + " — " + manager.nowPlayingSourceName + "  (tap to skip to 50%)")
        }
        .padding(8)
        .overlay(alignment: .bottom) {
            if case .failed(let msg) = manager.lastActionFlash {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
            }
        }
    }
}
