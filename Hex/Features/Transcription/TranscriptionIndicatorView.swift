//
//  TranscriptionIndicatorView.swift
//  Hex
//

import AppKit
import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

private let indicatorOverlayCoordinateSpace = "transcriptionIndicatorOverlay"

private struct IndicatorFramePreferenceKey: PreferenceKey {
	static var defaultValue: CGRect?

	static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
		value = nextValue()
	}
}

struct TranscriptionIndicatorView: View {
	@ObserveInjection var inject

	enum Status: Equatable {
		case hidden
		case optionKeyPressed
		case recording
		case screenAware
		case transcribing
		case refining
		case prewarming
		case error(String)

		var showsWaveform: Bool {
			switch self {
			case .recording, .screenAware: true
			default: false
			}
		}

		var showsProcessing: Bool {
			switch self {
			case .transcribing, .refining, .prewarming: true
			default: false
			}
		}
	}

	private struct Metrics {
		let height: CGFloat
		let waveformWidth: CGFloat

		init(size: IndicatorSize) {
			switch size {
			case .compact:
				height = 22
				waveformWidth = 76
			case .regular:
				height = 28
				waveformWidth = 116
			case .large:
				height = 34
				waveformWidth = 164
			}
		}
	}

	var status: Status
	var meter: Meter
	var size: IndicatorSize

	@State private var waveformSamples: [CGFloat] = []

	private var metrics: Metrics { .init(size: size) }
	private var isHidden: Bool { status == .hidden }
	private var isScreenAware: Bool { status == .screenAware }

	private var indicatorWidth: CGFloat {
		switch status {
		case .hidden, .optionKeyPressed:
			metrics.height
		case .recording:
			metrics.waveformWidth + 20
		case .screenAware:
			// The added room reveals older waveform samples instead of resetting them.
			metrics.waveformWidth + 58
		case .transcribing, .refining, .prewarming:
			// Loading is a continuation of recording, so retain the recording pill's width.
			metrics.waveformWidth + 20
		case .error:
			300
		}
	}

	private var waveformWidth: CGFloat {
		metrics.waveformWidth + (isScreenAware ? 24 : 0)
	}

	private var accessibilityLabel: String {
		switch status {
		case .hidden: "Dictation inactive"
		case .optionKeyPressed: "Dictation hotkey pressed"
		case .recording: "Recording"
		case .screenAware: "Screen aware recording"
		case .transcribing: "Transcribing"
		case .refining: "Refining"
		case .prewarming: "Model prewarming"
		case let .error(message): "Error: \(message)"
		}
	}

	var body: some View {
		RoundedRectangle(cornerRadius: metrics.height * 0.28, style: .continuous)
			.fill(backgroundColor)
			.overlay {
				RoundedRectangle(cornerRadius: metrics.height * 0.28, style: .continuous)
					.stroke(strokeColor, lineWidth: 1)
			}
			.overlay {
				content
			}
			.frame(width: indicatorWidth, height: metrics.height)
			.opacity(isHidden ? 0 : 1)
			.scaleEffect(isHidden ? 0.8 : 1)
			.animation(.snappy(duration: 0.22), value: status)
			.animation(.snappy(duration: 0.22), value: size)
			.accessibilityLabel(accessibilityLabel)
			.accessibilityHidden(isHidden)
			.background {
				GeometryReader { proxy in
					Color.clear.preference(
						key: IndicatorFramePreferenceKey.self,
						value: isHidden ? nil : proxy.frame(in: .named(indicatorOverlayCoordinateSpace))
					)
				}
			}
			.onAppear {
				appendMeterSample(meter)
			}
			.onChange(of: meter) { _, meter in
				appendMeterSample(meter)
			}
			.onChange(of: status) { oldStatus, newStatus in
				if oldStatus.showsWaveform && !newStatus.showsWaveform {
					waveformSamples.removeAll(keepingCapacity: true)
				}
			}
			.enableInjection()
	}

	@ViewBuilder
	private var content: some View {
		if status.showsWaveform {
			HStack(spacing: isScreenAware ? 6 : 0) {
				if isScreenAware {
					Image(systemName: "rectangle.inset.filled")
						.font(.system(size: metrics.height * 0.42, weight: .semibold))
						.foregroundStyle(.white)
						.help("Screen aware")
				}

				PillWaveform(samples: waveformSamples)
					.frame(width: waveformWidth, height: metrics.height - 8)
			}
			.padding(.horizontal, 10)
		} else if status == .refining {
			LoadingWave(label: "Refining", width: metrics.waveformWidth, height: metrics.height)
		} else if status.showsProcessing {
			LoadingWave(label: "Processing", width: metrics.waveformWidth, height: metrics.height)
		} else if case let .error(message) = status {
			Label(message, systemImage: "exclamationmark.triangle.fill")
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(.white)
				.lineLimit(2)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 10)
		}
	}

	private var backgroundColor: Color {
		isHidden ? .clear : Color(nsColor: mixedNSColor(.systemRed, with: .black, by: 0.42))
	}

	private var strokeColor: Color {
		isHidden ? .clear : .white.opacity(0.28)
	}

	private func appendMeterSample(_ meter: Meter) {
		guard status.showsWaveform else { return }
		// Typical spoken audio spends most of its time well below the peak meter
		// range. Boost and curve that lower range so normal speech remains legible.
		let boostedLevel = min(max(max(meter.averagePower, meter.peakPower * 0.88) * 7.5, 0), 1)
		let sample = CGFloat(pow(boostedLevel, 0.55))
		waveformSamples.append(sample)
		if waveformSamples.count > 240 {
			waveformSamples.removeFirst(waveformSamples.count - 240)
		}
	}

	private func mixedNSColor(_ color: NSColor, with otherColor: NSColor, by fraction: Double) -> NSColor {
		color.blended(withFraction: min(max(fraction, 0), 1), of: otherColor) ?? color
	}
}

private struct PillWaveform: View {
	let samples: [CGFloat]

	var body: some View {
		Canvas { context, size in
			let barWidth: CGFloat = 3
			let gap: CGFloat = 2
			let capacity = max(1, Int((size.width + gap) / (barWidth + gap)))
			let visibleSamples = samples.suffix(capacity)
			let values = visibleSamples.isEmpty ? Array(repeating: CGFloat(0.04), count: min(capacity, 8)) : Array(visibleSamples)
			let startX = size.width - CGFloat(values.count) * (barWidth + gap) + gap

			for (index, sample) in values.enumerated() {
				let normalized = max(sample, 0.06)
				let barHeight = max(3, normalized * size.height)
				let rect = CGRect(
					x: startX + CGFloat(index) * (barWidth + gap),
					y: (size.height - barHeight) / 2,
					width: barWidth,
					height: barHeight
				)
				context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(.white.opacity(0.92)))
			}
		}
		.accessibilityHidden(true)
	}
}

private struct LoadingWave: View {
	let label: String
	let width: CGFloat
	let height: CGFloat

	var body: some View {
		HStack(spacing: 8) {
			TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
				Canvas { context, size in
					// The absolute timeline phase prevents a loader restart when the
					// underlying work transitions from transcription to refinement.
					let phase = timeline.date.timeIntervalSinceReferenceDate * 6
					let amplitude = max(2, size.height * 0.22)
					let angularFrequency = (CGFloat.pi * 2 * 1.4) / max(size.width, 1)
					var path = Path()

					for x in stride(from: CGFloat.zero, through: size.width, by: 1) {
						let y = size.height / 2 - sin(x * angularFrequency + phase) * amplitude
						if x == 0 {
							path.move(to: .init(x: x, y: y))
						} else {
							path.addLine(to: .init(x: x, y: y))
						}
					}

					context.stroke(path, with: .color(.white.opacity(0.92)), lineWidth: 1.5)
				}
			}
			.frame(width: min(width * 0.35, 44), height: height)

			Text(label)
				.font(.system(size: max(10, height * 0.38), weight: .semibold))
				.foregroundStyle(.white)
		}
		.frame(width: width + 20, height: height)
		.accessibilityHidden(true)
	}
}

// MARK: - View

struct TranscriptionIndicatorOverlayView: View {
	@Bindable var store: StoreOf<TranscriptionFeature>
	@ObserveInjection var inject
	@Shared(.hexSettings) var hexSettings: HexSettings
	let onPillFrameChange: (CGRect?) -> Void

	var status: TranscriptionIndicatorView.Status {
		if let error = store.error {
			return .error(error)
		} else if store.isScreenAwareModeActive {
			return .screenAware
		} else if store.isRefining || (store.isTranscribing && store.forcedRefinementMode != nil) {
			return .refining
		} else if store.isTranscribing {
			return .transcribing
		} else if store.isRecording {
			return .recording
		} else if store.isPrewarming {
			return .prewarming
		} else {
			return .hidden
		}
	}

	private var alignment: Alignment {
		switch hexSettings.indicatorLocation {
		case .topLeading: .topLeading
		case .topCenter: .top
		case .topTrailing: .topTrailing
		case .bottomLeading: .bottomLeading
		case .bottomCenter: .bottom
		case .bottomTrailing: .bottomTrailing
		}
	}

	var body: some View {
		let indicatorStatus = status
		ZStack(alignment: alignment) {
			Color.clear
			TranscriptionIndicatorView(
				status: indicatorStatus,
				meter: indicatorStatus.showsWaveform ? store.meter : .init(averagePower: 0, peakPower: 0),
				size: hexSettings.indicatorSize
			)
			.padding(.horizontal, 24)
			.padding(.vertical, 18)
		}
		.coordinateSpace(name: indicatorOverlayCoordinateSpace)
		.onPreferenceChange(IndicatorFramePreferenceKey.self, perform: onPillFrameChange)
		.onDisappear { onPillFrameChange(nil) }
		.task {
			await store.send(.task).finish()
		}
		.enableInjection()
	}
}

#Preview("Transcription Indicator") {
	VStack(spacing: 16) {
		TranscriptionIndicatorView(status: .recording, meter: .init(averagePower: 0.5, peakPower: 0.75), size: .regular)
		TranscriptionIndicatorView(status: .screenAware, meter: .init(averagePower: 0.5, peakPower: 0.75), size: .regular)
		TranscriptionIndicatorView(status: .transcribing, meter: .init(averagePower: 0, peakPower: 0), size: .regular)
	}
	.padding(40)
	.background(.black)
}
