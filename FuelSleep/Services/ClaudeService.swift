import Foundation
import UIKit

typealias JSON = [String: Any]

// MARK: - Results

struct MealAnalysis: Codable {
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: String   // "low" | "medium" | "high"
    var notes: String
}

struct CoachAdvice: Codable {
    var headline: String
    var tips: [String]
}

// MARK: - Models and pricing

enum AIModel {
    static let key = "ai.model"
    static let defaultID = "claude-sonnet-5-5"

    struct Option: Identifiable {
        let id: String
        let label: String
    }

    static let options: [Option] = [
        Option(id: "claude-sonnet-5-5", label: "Sonnet 5.5 (more accurate)"),
        Option(id: "claude-haiku-5-5", label: "Haiku 5.5 (cheapest)")
    ]

    /// US dollars per million tokens (input, output). Check the pricing page if these change.
    static func price(for id: String) -> (input: Double, output: Double) {
        switch id {
        case "claude-haiku-5-5": return (0.10, 0.50)
        case "claude-sonnet-5-5": return (2.00, 10.00)
        default: return (2.00, 10.00)
        }
    }
}

/// Keeps a running estimate of what you've spent, shown in Settings.
enum UsageTracker {
    static let spendKey = "ai.spendUSD"
    static let callsKey = "ai.calls"

    static func record(model: String, inputTokens: Int, outputTokens: Int) {
        let p = AIModel.price(for: model)
        let cost = (Double(inputTokens) * p.input + Double(outputTokens) * p.output) / 1_000_000
        let d = UserDefaults.standard
        d.set(d.double(forKey: spendKey) + cost, forKey: spendKey)
        d.set(d.integer(forKey: callsKey) + 1, forKey: callsKey)
    }

    static func reset() {
        UserDefaults.standard.set(0.0, forKey: spendKey)
        UserDefaults.standard.set(0, forKey: callsKey)
    }
}

enum ClaudeError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Claude API key in Settings first."
        case .http(let code, let message): return "Claude API error \(code): \(message)"
        case .badResponse: return "Claude sent back something unexpected. Try again."
        }
    }
}

// MARK: - Service

/// Talks to the Claude Messages API. Each call uses structured outputs (a JSON schema),
/// so the app always gets numbers it can parse.
struct ClaudeService {
    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func fromSettings() throws -> ClaudeService {
        guard let key = Keychain.apiKey else { throw ClaudeError.missingKey }
        let model = UserDefaults.standard.string(forKey: AIModel.key) ?? AIModel.defaultID
        return ClaudeService(apiKey: key, model: model)
    }

    // MARK: Meal photo → macros

    func analyzeMeal(image: UIImage, hint: String) async throws -> MealAnalysis {
        guard let jpeg = image.preparedForUpload() else { throw ClaudeError.badResponse }

        var text = "Estimate the nutrition of the meal in this photo."
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += " Extra details from me: \(trimmed)"
        }

        let imageBlock: JSON = [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString()
                ]
        ]
        let content: [JSON] = [imageBlock, ["type": "text", "text": text]]

        let system = """
        You are a nutritionist estimating macros from food photos. Identify each item, \
        estimate its portion in grams using plate size and cutlery as scale, then add up \
        realistic totals. Include likely cooking oil and sauces. If the photo is not food, \
        set every number to 0, confidence to low, and say so in notes.
        """

        return try await callJSON(system: system,
                                  content: content,
                                  schema: Self.mealSchema,
                                  maxTokens: 800)
    }

    // MARK: Meal description → macros

    /// "2 eggs, 2 slices of toast with butter, flat white" → name and macros.
    func analyzeText(_ description: String) async throws -> MealAnalysis {
        let system = """
        You are a nutritionist estimating macros from a short description of what someone \
        ate. Work out each item and its amount; where an amount isn't given, assume a typical \
        UK portion. Add up realistic totals, including butter, oil, sauces and milk in drinks \
        when they're implied. Give the meal a short, natural name. If the text isn't about \
        food, set every number to 0, confidence to low, and say so in notes.
        """
        let content: [JSON] = [["type": "text", "text": "What I ate: \(description)"]]
        return try await callJSON(system: system,
                                  content: content,
                                  schema: Self.mealSchema,
                                  maxTokens: 600)
    }

    /// The JSON shape Claude must reply with for meal estimates (photo or text).
    private static let mealSchema: JSON = {
        let properties: JSON = [
            "name": ["type": "string", "description": "Short meal name, e.g. 'Chicken, rice and broccoli'"],
            "calories": ["type": "number", "description": "Total kcal for the whole meal"],
            "protein": ["type": "number", "description": "Grams of protein"],
            "carbs": ["type": "number", "description": "Grams of carbohydrate"],
            "fat": ["type": "number", "description": "Grams of fat"],
            "confidence": ["type": "string", "enum": ["low", "medium", "high"]] as JSON,
            "notes": ["type": "string", "description": "One sentence: the portion sizes you assumed and anything hard to judge (oil, sauces, hidden ingredients)."]
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["name", "calories", "protein", "carbs", "fat", "confidence", "notes"],
            "additionalProperties": false
        ]
    }()

    // MARK: Daily coaching

    func dailyAdvice(summary: String, tone: String? = nil) async throws -> CoachAdvice {
        let tipsProperty: JSON = [
            "type": "array",
            "items": ["type": "string"],
            "description": "2 to 4 specific, practical tips with real foods and amounts."
        ]
        let adviceProperties: JSON = [
            "headline": ["type": "string", "description": "One short sentence: the single most important thing today."],
            "tips": tipsProperty
        ]
        let schema: JSON = [
            "type": "object",
            "properties": adviceProperties,
            "required": ["headline", "tips"],
            "additionalProperties": false
        ]

        var system = """
        You are a friendly, practical sports nutrition and sleep coach for someone who trains \
        at the gym. Use only the data given. Be specific: name foods and rough amounts \
        (UK supermarket foods are fine), and tie advice to the time of day, today's training \
        and last night's sleep. Don't lecture or repeat the numbers back. You are not a doctor; \
        if something looks medically worrying, suggest seeing a GP.
        """
        if let tone { system += " " + tone }

        let content: [JSON] = [["type": "text", "text": summary]]

        return try await callJSON(system: system,
                                  content: content,
                                  schema: schema,
                                  maxTokens: 1000)
    }

    // MARK: Weekly review

    func weeklyReview(summary: String, tone: String? = nil) async throws -> WeeklyReview {
        func list(_ description: String) -> JSON {
            ["type": "array", "items": ["type": "string"], "description": description]
        }
        let properties: JSON = [
            "headline": ["type": "string", "description": "One sentence summing up the week."],
            "wentWell": list("2 or 3 specific things that went well, each citing the data (days, numbers)."),
            "focus": ["type": "string", "description": "The single most important thing to fix next week, and why, citing the data."],
            "plan": list("2 or 3 concrete actions for next week with real foods, amounts or times.")
        ]
        let schema: JSON = [
            "type": "object",
            "properties": properties,
            "required": ["headline", "wentWell", "focus", "plan"],
            "additionalProperties": false
        ]

        var system = """
        You are a practical sports nutrition and sleep coach reviewing someone's week of \
        gym training, sleep and eating. Use only the data given and point to specific days \
        and numbers. Look for patterns, e.g. low carbs on training days, protein falling \
        short on particular days, short sleep before or after hard sessions, days with no \
        meals logged. Be encouraging but honest, and keep every item short (one or two \
        sentences). Use UK foods. You are not a doctor; suggest a GP for anything that \
        looks medically worrying. If the week is still in progress, review it so far.
        """
        if let tone { system += " " + tone }

        let content: [JSON] = [["type": "text", "text": summary]]
        var review: WeeklyReview = try await callJSON(system: system,
                                                      content: content,
                                                      schema: schema,
                                                      maxTokens: 1500)
        review.generatedAt = .now
        return review
    }

    // MARK: Core request

    private func callJSON<T: Decodable>(system: String,
                                        content: [JSON],
                                        schema: JSON,
                                        maxTokens: Int) async throws -> T {
        // Structured outputs: Claude's reply is guaranteed to match `schema`.
        let format: JSON = ["type": "json_schema", "schema": schema]
        let message: JSON = ["role": "user", "content": content]
        let body: JSON = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "output_config": ["format": format] as JSON,
            "messages": [message]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON

        guard http.statusCode == 200 else {
            let error = json?["error"] as? JSON
            let message = error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.http(http.statusCode, message)
        }

        if let usage = json?["usage"] as? JSON {
            UsageTracker.record(model: model,
                                inputTokens: usage["input_tokens"] as? Int ?? 0,
                                outputTokens: usage["output_tokens"] as? Int ?? 0)
        }

        guard let blocks = json?["content"] as? [JSON],
              let textBlock = blocks.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw ClaudeError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: textData)
    }
}

// MARK: - Image prep

extension UIImage {
    /// Shrinks to at most 1024px on the long edge and compresses, which keeps uploads fast
    /// and the token cost of each photo low.
    func preparedForUpload(maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
