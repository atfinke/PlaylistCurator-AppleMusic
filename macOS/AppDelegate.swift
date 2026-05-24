//
//  AppDelegate.swift
//  PlaylistCurator-AppleMusic
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        // Bootstrap the AppKit run loop ourselves; @NSApplicationMain is gone
        // in Swift 6, and we need NSApplicationMain (the function) to load
        // Main.storyboard which wires in FloatingWindowController.
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
