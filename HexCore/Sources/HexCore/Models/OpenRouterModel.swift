import Foundation

/// A model returned by OpenRouter's public model catalog.
public struct OpenRouterModel: Codable, Equatable, Identifiable, Sendable {
	public enum InputModality: String, Codable, Equatable, Sendable {
		case text
		case image
	}

	public struct Architecture: Codable, Equatable, Sendable {
		public let inputModalities: [String]
		public let outputModalities: [String]

		public init(inputModalities: [String], outputModalities: [String] = ["text"]) {
			self.inputModalities = inputModalities
			self.outputModalities = outputModalities
		}

		enum CodingKeys: String, CodingKey {
			case inputModalities = "input_modalities"
			case outputModalities = "output_modalities"
		}
	}

	public struct Pricing: Codable, Equatable, Sendable {
		public let prompt: String
		public let completion: String

		public init(prompt: String, completion: String) {
			self.prompt = prompt
			self.completion = completion
		}

		public var inputPricePerMillionTokens: Decimal? {
			Decimal(string: prompt).map { $0 * Decimal(1_000_000) }
		}
	}

	public struct Reasoning: Codable, Equatable, Sendable {
		public let supportedEfforts: [String]?
		public let defaultEnabled: Bool?
		public let mandatory: Bool?

		public init(
			supportedEfforts: [String]? = nil,
			defaultEnabled: Bool? = nil,
			mandatory: Bool? = nil
		) {
			self.supportedEfforts = supportedEfforts
			self.defaultEnabled = defaultEnabled
			self.mandatory = mandatory
		}

		enum CodingKeys: String, CodingKey {
			case supportedEfforts = "supported_efforts"
			case defaultEnabled = "default_enabled"
			case mandatory
		}
	}

	public let id: String
	public let name: String
	public let pricing: Pricing
	public let contextLength: Int?
	public let architecture: Architecture?
	public let reasoning: Reasoning?

	public init(
		id: String,
		name: String,
		pricing: Pricing,
		contextLength: Int? = nil,
		architecture: Architecture? = nil,
		reasoning: Reasoning? = nil
	) {
		self.id = id
		self.name = name
		self.pricing = pricing
		self.contextLength = contextLength
		self.architecture = architecture
		self.reasoning = reasoning
	}

	public func supportsInput(_ modality: InputModality) -> Bool {
		guard let architecture else {
			// Catalog caches created before modality metadata was added contain only
			// text models, so they remain useful for the default text-model picker.
			return modality == .text
		}
		return architecture.inputModalities.contains(modality.rawValue)
	}

	enum CodingKeys: String, CodingKey {
		case id, name, pricing, architecture, reasoning
		case contextLength = "context_length"
	}
}
