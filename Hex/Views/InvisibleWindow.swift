//
//  InvisibleWindow.swift
//  Hex
//
//  Created by Kit Langton on 1/24/25.
//

import AppKit
import SwiftUI

/// This allows us to render SwiftUI views anywhere on the screen, without dealing with the awkward
/// rendering issues that come with normal MacOS windows. Essentially, we create one giant invisible
/// window that covers the entire screen, and render our SwiftUI views into it.
///
/// I'm pretty sure this is what CleanShot X and other apps do to render their floating widgets.
/// But if there's a better way to do this, I'd love to know!
class InvisibleWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  private var currentScreen: NSScreen?
  private var mouseMonitor: Any?

  init() {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let styleMask: NSWindow.StyleMask = [.fullSizeContentView, .borderless, .utilityWindow, .nonactivatingPanel]

    super.init(contentRect: screen.frame,
               styleMask: styleMask,
               backing: .buffered,
               defer: false)

    level = .statusBar
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    ignoresMouseEvents = true
    hidesOnDeactivate = false // Prevent hiding when app loses focus
    canHide = false
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]

    // Set initial frame
    updateToScreenWithMouse()

    // Start observing screen changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenDidChange),
      name: NSWindow.didChangeScreenNotification,
      object: nil
    )

    // Also observe screen parameters for resolution changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )

    // Monitor mouse movements to detect screen boundary crossings
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
      self?.checkForScreenChange()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    if let monitor = mouseMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  private func updateToScreenWithMouse() {
    let mouseLocation = NSEvent.mouseLocation
    guard let screenWithMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
    currentScreen = screenWithMouse
    setFrame(screenWithMouse.frame, display: true)
  }

  private func checkForScreenChange() {
    let mouseLocation = NSEvent.mouseLocation
    guard let newScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
    
    // Only update if screen actually changed
    if newScreen !== currentScreen {
      currentScreen = newScreen
      setFrame(newScreen.frame, display: true)
    }
  }

  @objc private func screenDidChange(_: Notification) {
    updateToScreenWithMouse()
  }
}

extension InvisibleWindow: NSWindowDelegate {
  static func fromView<V: View>(_ view: V) -> InvisibleWindow {
    let window = InvisibleWindow()
    window.contentView = NSHostingView(rootView: view)
    window.delegate = window
    return window
  }
}

/// A tightly-scoped transparent panel used to make the otherwise click-through
/// transcription indicator interactive without swallowing unrelated desktop clicks.
final class PillInteractionPanel: NSPanel {
  init(onTap: @escaping () -> Void) {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    level = .statusBar + 1
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    hidesOnDeactivate = false
    canHide = false
    collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .stationary, .ignoresCycle]
    contentView = NSHostingView(rootView: PillInteractionView(onTap: onTap))
    orderOut(nil)
  }

  func update(frame: NSRect?) {
    guard let frame, frame.width > 0, frame.height > 0 else {
      orderOut(nil)
      return
    }

    setFrame(frame, display: true)
    orderFrontRegardless()
  }
}

private struct PillInteractionView: View {
  let onTap: () -> Void

  var body: some View {
    Color.clear
      .contentShape(Rectangle())
      .onTapGesture(perform: onTap)
      .accessibilityLabel("Open History")
  }
}
