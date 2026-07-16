import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

/// Settings for the optional, downstream transcript-refinement stage.
struct RefinementSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var geminiAPIKey = ""
	@State private var openRouterAPIKey = ""
	@State private var isShowingOpenRouterModelPicker = false
	@State private var isShowingScreenAwareModelPicker = false

	var body: some View {
		Section {
			let refinedHotkey = store.hexSettings.refinedHotkey ?? .init(key: nil, modifiers: [])
			let refinedKey = store.isSettingRefinedHotKey ? nil : refinedHotkey.key
			let refinedModifiers = store.isSettingRefinedHotKey ? store.currentRefinedModifiers : refinedHotkey.modifiers

			VStack(alignment: .leading, spacing: 8) {
				Label("Refinement Instructions", systemImage: "sparkles")
					.font(.headline)
				TextEditor(text: $store.hexSettings.refinementInstructions)
					.font(.body)
					.multilineTextAlignment(.leading)
					.frame(maxWidth: .infinity, minHeight: 130, maxHeight: 180, alignment: .topLeading)
					.padding(8)
					.background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
				Text("For example: “Return exactly three bullet points: one English, one French, and one German.”")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			Label {
				Picker("Provider", selection: $store.hexSettings.refinementProvider) {
					Text("Apple Intelligence").tag(RefinementProvider.apple)
					Text("Gemini Flash").tag(RefinementProvider.gemini)
					Text("OpenRouter").tag(RefinementProvider.openRouter)
				}
			} icon: {
				Image(systemName: "cpu")
			}

				if store.hexSettings.refinementProvider == .apple {
					if #unavailable(macOS 26.0) {
						Text("Apple Intelligence refinement requires macOS 26 or later. Until then, Hex keeps the processed transcript unchanged.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}

				if store.hexSettings.refinementProvider == .gemini {
					SecureField("Gemini API Key", text: $geminiAPIKey)
						.onSubmit(persistGeminiAPIKey)
					Text("Stored securely in Keychain. Without a key, Hex pastes the processed transcript unchanged.")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("Gemini sends the completed, locally transformed transcript text to Google. Audio is never sent.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

					if store.hexSettings.refinementProvider == .openRouter {
					SecureField("OpenRouter API Key", text: $openRouterAPIKey)
						.onSubmit(persistOpenRouterAPIKey)
					Button {
						persistOpenRouterAPIKey()
						isShowingOpenRouterModelPicker = true
					} label: {
						LabeledContent("Default Model") {
							Text(store.hexSettings.openRouterModelID ?? "Select a model")
								.foregroundStyle(store.hexSettings.openRouterModelID == nil ? .secondary : .primary)
						}
					}
					.disabled(openRouterAPIKey.isEmpty)
					Text("Your key is stored securely in Keychain. Choose any text model from the cached OpenRouter catalog.")
						.font(.caption)
						.foregroundStyle(.secondary)
						Text("OpenRouter sends the completed, locally transformed transcript text to the selected model. Audio is never sent.")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					VStack(alignment: .leading, spacing: 8) {
						HStack {
							Label("Screen-aware Dictation", systemImage: "rectangle.and.text.magnifyingglass")
								.font(.headline)
							Spacer()
							Toggle("Enable Screen-aware Dictation", isOn: $store.hexSettings.screenAwareDictationEnabled)
								.labelsHidden()
								.disabled(openRouterAPIKey.isEmpty)
						}
						Text("Long-press the refinement hotkey to capture the display under the cursor as Screen-aware mode activates. With double-tap lock enabled, release the second tap for regular refinement or keep holding it for Screen-aware mode. The original screenshot and its local text are retained in History either way.")
							.font(.caption)
							.foregroundStyle(.secondary)
						Picker("Analysis source", selection: $store.hexSettings.screenAwareInputSource) {
							Text("Local Apple Vision OCR").tag(ScreenAwareInputSource.localOCR)
							Text("Upload screenshot").tag(ScreenAwareInputSource.image)
						}
						.pickerStyle(.radioGroup)
						.disabled(openRouterAPIKey.isEmpty || !store.hexSettings.screenAwareDictationEnabled)
						Text(screenAwareSourceDescription)
							.font(.caption)
							.foregroundStyle(.secondary)
						if store.hexSettings.refinementProvider != .openRouter {
							SecureField("OpenRouter API Key", text: $openRouterAPIKey)
								.onSubmit(persistOpenRouterAPIKey)
						}
						if store.hexSettings.screenAwareInputSource.uploadsScreenshot {
							Button {
								persistOpenRouterAPIKey()
								isShowingScreenAwareModelPicker = true
							} label: {
								LabeledContent("Fallback Image Model") {
									Text(store.hexSettings.screenAwareOpenRouterModelID ?? "Select a model")
										.foregroundStyle(store.hexSettings.screenAwareOpenRouterModelID == nil ? .secondary : .primary)
								}
							}
							.disabled(openRouterAPIKey.isEmpty || !store.hexSettings.screenAwareDictationEnabled)
							Text("Used only when the selected refinement model cannot accept image input.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						if openRouterAPIKey.isEmpty {
							Text("Add an OpenRouter API key to choose an image model and enable this feature.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
			VStack(alignment: .leading, spacing: 14) {
				RefinedHotKeyIntroduction(
					hasConflict: store.hexSettings.refinedHotkey?.conflicts(with: store.hexSettings.hotkey) ?? false
				)

				HStack {
					Spacer()
					HotKeyView(modifiers: refinedModifiers, key: refinedKey, isActive: store.isSettingRefinedHotKey)
					Spacer()
				}
				.contentShape(Rectangle())
				.onTapGesture { store.send(.startSettingRefinedHotKey) }
			}
			.listRowSeparator(.hidden)

			if !store.isSettingRefinedHotKey, refinedHotkey.key == nil, !refinedHotkey.modifiers.isEmpty {
				ModifierSideControls(modifiers: refinedHotkey.modifiers) { kind, side in
					store.send(.setRefinedModifierSide(kind, side))
				}
				.listRowSeparator(.hidden, edges: .top)
			}

			Label {
				Toggle("Enable double-tap lock", isOn: $store.hexSettings.refinedDoubleTapLockEnabled)
			} icon: {
				Image(systemName: "hand.tap")
			}

			if store.hexSettings.refinedDoubleTapLockEnabled {
				Label {
					Toggle("Use double-tap only", isOn: $store.hexSettings.refinedUseDoubleTapOnly)
				} icon: {
					Image(systemName: "hand.tap.fill")
				}
			}

			if refinedHotkey.key == nil, !(store.hexSettings.refinedDoubleTapLockEnabled && store.hexSettings.refinedUseDoubleTapOnly) {
				Label {
					Slider(value: $store.hexSettings.refinedMinimumKeyTime, in: 0 ... 2, step: 0.1) {
						Text("Ignore below \(store.hexSettings.refinedMinimumKeyTime, specifier: "%.1f")s")
					}
				} icon: {
					Image(systemName: "clock")
				}
			}

			Label {
				Toggle("Include selected text", isOn: $store.hexSettings.includeSelectedTextInRefinement)
			} icon: {
				Image(systemName: "text.cursor")
			}
		} header: {
			Text("Transcription Refinement")
		} footer: {
			Text("Rewrite or clean up your transcriptions and/or selected text with custom prompts")
		}
		.task {
			geminiAPIKey = GeminiAPIKeyStore.read() ?? ""
			openRouterAPIKey = OpenRouterAPIKeyStore.read() ?? ""
		}
		.onChange(of: store.hexSettings.refinementProvider) { oldProvider, _ in
			if oldProvider == .gemini { persistGeminiAPIKey() }
			if oldProvider == .openRouter { persistOpenRouterAPIKey() }
		}
		.onChange(of: openRouterAPIKey) { _, key in
			// Clearing the field explicitly opts out of the saved Keychain credential.
			if key.isEmpty { persistOpenRouterAPIKey() }
		}
		.onDisappear {
			persistGeminiAPIKey()
			persistOpenRouterAPIKey()
		}
			.sheet(isPresented: $isShowingOpenRouterModelPicker) {
				OpenRouterModelPickerView(
					selectedModelID: $store.hexSettings.openRouterModelID,
					apiKey: openRouterAPIKey,
					requiredInputModality: .text
				)
			}
			.sheet(isPresented: $isShowingScreenAwareModelPicker) {
				OpenRouterModelPickerView(
					selectedModelID: $store.hexSettings.screenAwareOpenRouterModelID,
					apiKey: openRouterAPIKey,
					requiredInputModality: .image
				)
			}
		.enableInjection()
	}

	private func persistGeminiAPIKey() {
		persistAPIKey(geminiAPIKey, providerName: "Gemini", save: GeminiAPIKeyStore.save, delete: GeminiAPIKeyStore.delete)
	}

	private func persistOpenRouterAPIKey() {
		persistAPIKey(openRouterAPIKey, providerName: "OpenRouter", save: OpenRouterAPIKeyStore.save, delete: OpenRouterAPIKeyStore.delete)
	}

	private var screenAwareSourceDescription: String {
		switch store.hexSettings.screenAwareInputSource {
		case .localOCR:
			"Fastest and most private: Apple Vision extracts text on your Mac, then Hex uses your selected refinement model with that text and your spoken request. Best for documents, email, and other text-based screens."
		case .image:
			"Best for layout, charts, icons, imagery, or other visual details: Hex sends a compressed analysis copy of the screenshot to OpenRouter. The PNG captured by Hex stays local in History."
		}
	}

	private func persistAPIKey(
		_ key: String,
		providerName: String,
		save: (String) throws -> Void,
		delete: () throws -> Void
	) {
		do {
			if key.isEmpty {
				try delete()
			} else {
				try save(key)
			}
		} catch {
			HexLog.settings.error("Could not save \(providerName, privacy: .public) API key: \(error.localizedDescription, privacy: .private)")
		}
	}
}

private struct RefinedHotKeyIntroduction: View {
	let hasConflict: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label("Refined Transcription Hotkey", systemImage: "keyboard")
				.font(.headline)
			Text("Records normally, then always runs refinement using the instructions above.")
				.font(.caption)
				.foregroundStyle(.secondary)
			if hasConflict {
				Text("Choose a non-overlapping shortcut. A modifier-only shortcut cannot share a prefix with the regular shortcut.")
					.font(.caption)
					.foregroundStyle(.orange)
			}
		}
	}
}
