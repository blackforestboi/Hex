import ComposableArchitecture
import Inject
import Sparkle
import AppKit
import SwiftUI

@main
struct HexApp: App {
	static let appStore = Store(initialState: AppFeature.State()) {
		AppFeature()
	}

	@NSApplicationDelegateAdaptor(HexAppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra {
            MenuBarCopyLastTranscriptButton()
            MenuBarRefineSelectedTextButton()

            Button("History") {
                appDelegate.presentHistoryView()
            }

            Button("Settings…") {
                appDelegate.presentSettingsView()
            }.keyboardShortcut(",")

            CheckForUpdatesView()
			
			Divider()
			
			Button("Quit Octo") {
				NSApplication.shared.terminate(nil)
			}.keyboardShortcut("q")
		} label: {
			Image("OctoMenuBarIcon")
				.resizable()
				.renderingMode(.template)
				.scaledToFit()
				.frame(width: 18, height: 18)
		}
		.commands {
			CommandGroup(after: .appInfo) {
				CheckForUpdatesView()

				Button("Settings…") {
					appDelegate.presentSettingsView()
				}.keyboardShortcut(",")
			}

			CommandGroup(replacing: .help) {}
		}
	}
}
