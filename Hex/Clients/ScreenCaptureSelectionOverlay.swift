import AppKit
import os

private enum ScreenCaptureSelectionState {
	private static let lock = OSAllocatedUnfairLock(initialState: false)

	static var isActive: Bool {
		lock.withLock { $0 }
	}

	static func setActive(_ isActive: Bool) {
		lock.withLock { $0 = isActive }
	}
}

private final class ScreenCaptureSelectionWindow: NSPanel {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
}

@MainActor
private final class ScreenCaptureSelectionOverlayController: NSObject, NSWindowDelegate {
	private let window: ScreenCaptureSelectionWindow
	private let backingScaleFactor: CGFloat
	private var continuation: CheckedContinuation<CGRect?, Error>?
	private var keyEventMonitor: Any?

	init(screenFrame: CGRect, backingScaleFactor: CGFloat) {
		self.backingScaleFactor = backingScaleFactor
		window = ScreenCaptureSelectionWindow(
			contentRect: screenFrame,
			styleMask: [.borderless, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		super.init()
		window.delegate = self
		window.level = .screenSaver
		window.backgroundColor = .clear
		window.isOpaque = false
		window.hasShadow = false
		window.hidesOnDeactivate = false
		window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
	}

	func select() async throws -> CGRect? {
		try await withCheckedThrowingContinuation { continuation in
			self.continuation = continuation
			let view = ScreenCaptureSelectionOverlayView(
				frame: CGRect(origin: .zero, size: window.frame.size),
				minimumDragDistance: 20 / backingScaleFactor,
				onComplete: { [weak self] rectangle in self?.complete(with: rectangle) },
				onCancel: { [weak self] in self?.cancel() }
			)
			window.contentView = view
			keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak view] event in
				if event.type == .keyDown, view?.handleKeyDown(event) == true {
					return nil
				}
				if event.type == .keyUp, view?.handleKeyUp(event) == true {
					return nil
				}
				return event
			}
			NSApp.activate(ignoringOtherApps: true)
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(view)
		}
	}

	func windowWillClose(_: Notification) {
		cancel()
	}

	private func complete(with rectangle: CGRect?) {
		finish(.success(rectangle))
	}

	private func cancel() {
		finish(.failure(CancellationError()))
	}

	private func finish(_ result: Result<CGRect?, Error>) {
		guard let continuation else { return }
		self.continuation = nil
		// Clear this before resuming the continuation so a second Escape goes
		// straight back to the recording hotkey path, even if it follows quickly.
		ScreenCaptureSelectionState.setActive(false)
		if let keyEventMonitor {
			NSEvent.removeMonitor(keyEventMonitor)
			self.keyEventMonitor = nil
		}
		window.contentView = nil
		window.orderOut(nil)
		continuation.resume(with: result)
	}
}

@MainActor
enum ScreenCaptureSelectionOverlay {
	nonisolated static var isSelectingRegion: Bool {
		ScreenCaptureSelectionState.isActive
	}

	static func selectRegion(on screenFrame: CGRect, backingScaleFactor: CGFloat) async throws -> CGRect? {
		ScreenCaptureSelectionState.setActive(true)
		defer { ScreenCaptureSelectionState.setActive(false) }
		let controller = ScreenCaptureSelectionOverlayController(
			screenFrame: screenFrame,
			backingScaleFactor: backingScaleFactor
		)
		return try await controller.select()
	}
}

@MainActor
private final class ScreenCaptureSelectionOverlayView: NSView {
	private var selection = ScreenCaptureSelection()
	private let onComplete: (CGRect?) -> Void
	private let onCancel: () -> Void

	init(
		frame: CGRect,
		minimumDragDistance: CGFloat,
		onComplete: @escaping (CGRect?) -> Void,
		onCancel: @escaping () -> Void
	) {
		selection = ScreenCaptureSelection(minimumDragDistance: minimumDragDistance)
		self.onComplete = onComplete
		self.onCancel = onCancel
		super.init(frame: frame)
		wantsLayer = true
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var acceptsFirstResponder: Bool { true }

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .crosshair)
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.black.withAlphaComponent(0.28).setFill()
		bounds.fill()

		if let rectangle = selection.rectangle {
			let context = NSGraphicsContext.current?.cgContext
			context?.saveGState()
			context?.setBlendMode(.clear)
			context?.fill(rectangle)
			context?.restoreGState()

			NSColor.white.withAlphaComponent(0.9).setStroke()
			NSBezierPath(rect: rectangle).stroke()

			if !selection.isMoving {
				drawMoveHint(above: rectangle)
			}
		}
	}

	private func drawMoveHint(above rectangle: CGRect) {
		let keyLabel = "Space"
		let trailingLabel = "to move"
		let keyFont = NSFont.systemFont(ofSize: 11, weight: .medium)
		let textFont = NSFont.systemFont(ofSize: 12, weight: .medium)
		let keyTextSize = keyLabel.size(withAttributes: [.font: keyFont])
		let trailingTextSize = trailingLabel.size(withAttributes: [.font: textFont])
		let keyInsets = CGSize(width: 7, height: 3)
		let keySize = CGSize(
			width: keyTextSize.width + (keyInsets.width * 2),
			height: keyTextSize.height + (keyInsets.height * 2)
		)
		let spacing: CGFloat = 5
		let hintSize = CGSize(
			width: keySize.width + spacing + trailingTextSize.width,
			height: max(keySize.height, trailingTextSize.height)
		)

		let horizontalPadding: CGFloat = 8
		let verticalPadding: CGFloat = 8
		let preferredOrigin = CGPoint(x: rectangle.minX, y: rectangle.maxY + verticalPadding)
		let x = min(max(preferredOrigin.x, horizontalPadding), bounds.maxX - hintSize.width - horizontalPadding)
		let y: CGFloat
		if preferredOrigin.y + hintSize.height <= bounds.maxY - verticalPadding {
			y = preferredOrigin.y
		} else {
			y = max(bounds.minY + verticalPadding, rectangle.minY - hintSize.height - verticalPadding)
		}

		let keyRect = CGRect(origin: CGPoint(x: x, y: y), size: keySize)
		let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: 4, yRadius: 4)
		NSColor.black.withAlphaComponent(0.72).setFill()
		keyPath.fill()
		NSColor.white.withAlphaComponent(0.45).setStroke()
		keyPath.lineWidth = 1
		keyPath.stroke()

		let keyTextOrigin = CGPoint(
			x: keyRect.midX - (keyTextSize.width / 2),
			y: keyRect.midY - (keyTextSize.height / 2)
		)
		keyLabel.draw(at: keyTextOrigin, withAttributes: [
			.font: keyFont,
			.foregroundColor: NSColor.white
		])
		trailingLabel.draw(
			at: CGPoint(x: keyRect.maxX + spacing, y: y + (hintSize.height - trailingTextSize.height) / 2),
			withAttributes: [
				.font: textFont,
				.foregroundColor: NSColor.white
			]
		)
	}

	override func mouseDown(with event: NSEvent) {
		selection.begin(at: convert(event.locationInWindow, from: nil))
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		selection.drag(to: convert(event.locationInWindow, from: nil))
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		onComplete(selection.finish(at: convert(event.locationInWindow, from: nil)))
	}

	override func keyDown(with event: NSEvent) {
		if handleKeyDown(event) {
			return
		}
		super.keyDown(with: event)
	}

	override func keyUp(with event: NSEvent) {
		if handleKeyUp(event) {
			return
		}
		super.keyUp(with: event)
	}

	@discardableResult
	func handleKeyDown(_ event: NSEvent) -> Bool {
		if isSpace(event) {
			guard !event.isARepeat else { return true }
			selection.beginMoving(at: convertMouseLocation())
			needsDisplay = true
			return true
		}
		if event.keyCode == 53 {
			if selection.reset() {
				needsDisplay = true
			} else {
				onCancel()
			}
			return true
		}
		return false
	}

	@discardableResult
	func handleKeyUp(_ event: NSEvent) -> Bool {
		guard isSpace(event) else { return false }
		selection.endMoving()
		needsDisplay = true
		return true
	}

	private func convertMouseLocation() -> CGPoint {
		convert(window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? .zero, from: nil)
	}

	private func isSpace(_ event: NSEvent) -> Bool {
		event.keyCode == 49 || event.charactersIgnoringModifiers == " "
	}
}
