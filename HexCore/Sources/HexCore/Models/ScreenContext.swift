import Foundation

/// Determines whether Screen Aware sends the screenshot to the cloud model or relies on
/// local Apple Vision text recognition as its screen context.
public enum ScreenAwareInputSource: String, Codable, CaseIterable, Equatable, Sendable {
	case localOCR
	case image

	public var uploadsScreenshot: Bool { self == .image }
}

/// A cursor-localized display capture used by screen-aware dictation.
public struct ScreenContext: Equatable, Sendable {
	public let imagePNGData: Data
	public let recognizedText: String
	public let pixelWidth: Int
	public let pixelHeight: Int
	public let cursorX: Double
	public let cursorY: Double

	public init(
		imagePNGData: Data,
		recognizedText: String,
		pixelWidth: Int,
		pixelHeight: Int,
		cursorX: Double,
		cursorY: Double
	) {
		self.imagePNGData = imagePNGData
		self.recognizedText = recognizedText
		self.pixelWidth = pixelWidth
		self.pixelHeight = pixelHeight
		self.cursorX = cursorX
		self.cursorY = cursorY
	}
}
