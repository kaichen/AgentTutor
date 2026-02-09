import Foundation

protocol RemediationAdvising: Sendable {
    func suggest(failure: InstallFailure, hints: [String], apiKey: String, baseURL: String) async -> RemediationAdvice
}

struct OpenAIAdvicePayload: Decodable {
    let summary: String
    let commands: [String]
    let notes: String
}

final class RemediationAdvisor: RemediationAdvising {
    private let session: URLSession
    private let model: String

    init(session: URLSession = .shared, model: String = "gpt-4.1-mini") {
        self.session = session
        self.model = model
    }

    func suggest(failure: InstallFailure, hints: [String], apiKey: String, baseURL: String) async -> RemediationAdvice {
        let fallback = heuristicAdvice(for: failure, hints: hints)
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            return fallback
        }

        do {
            let generated = try await fetchAdviceFromOpenAI(failure: failure, hints: hints, apiKey: normalizedKey, baseURL: baseURL)
            let safeCommands = generated.commands.filter(CommandSafety.isAllowed)
            guard !safeCommands.isEmpty else {
                return RemediationAdvice(
                    summary: fallback.summary,
                    commands: fallback.commands,
                    notes: "AI returned only blocked commands. Showing safe fallback guidance.",
                    source: .heuristics
                )
            }

            return RemediationAdvice(
                summary: generated.summary,
                commands: safeCommands,
                notes: generated.notes,
                source: .openAI
            )
        } catch {
            return RemediationAdvice(
                summary: fallback.summary,
                commands: fallback.commands,
                notes: "AI guidance unavailable: \(error.localizedDescription)",
                source: .heuristics
            )
        }
    }

    private func heuristicAdvice(for failure: InstallFailure, hints: [String]) -> RemediationAdvice {
        let output = failure.output.lowercased()
        if output.contains("not found") && failure.failedCommand.contains("brew") {
            return RemediationAdvice(
                summary: "Homebrew is unavailable in your current shell context.",
                commands: [
                    "eval \"$(/opt/homebrew/bin/brew shellenv)\"",
                    "brew doctor"
                ],
                notes: hints.joined(separator: " "),
                source: .heuristics
            )
        }

        if output.contains("xcode-select") || failure.itemID == "xcode-cli-tools" {
            return RemediationAdvice(
                summary: "Xcode Command Line Tools are not fully installed yet.",
                commands: [
                    "xcode-select --install",
                    "xcode-select -p"
                ],
                notes: hints.joined(separator: " "),
                source: .heuristics
            )
        }

        if failure.itemID == "gh-auth" {
            return RemediationAdvice(
                summary: "GitHub authentication needs to be completed before setup can finish.",
                commands: [
                    "gh auth login --hostname github.com --web --git-protocol https",
                    "gh auth status"
                ],
                notes: hints.joined(separator: " "),
                source: .heuristics
            )
        }

        return RemediationAdvice(
            summary: "The step failed. Use the suggested commands to gather details and retry.",
            commands: [
                failure.failedCommand,
                "echo \"Retry after resolving the error above.\""
            ],
            notes: hints.joined(separator: " "),
            source: .heuristics
        )
    }

    private func fetchAdviceFromOpenAI(failure: InstallFailure, hints: [String], apiKey: String, baseURL: String) async throws -> OpenAIAdvicePayload {
        let systemPrompt = "You are a macOS setup assistant. Return only compact JSON with keys summary,commands,notes. Commands must be safe and minimal."
        let userPrompt = """
        Installation step failed.
        Item: \(failure.itemName)
        Command: \(failure.failedCommand)
        Exit code: \(failure.exitCode)
        Timed out: \(failure.timedOut)
        Output:
        \(failure.output)

        Built-in hints:
        \(hints.joined(separator: "\n"))

        Return JSON only.
        """

        let requestBody: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_output_tokens": 400,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]]
                ],
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": userPrompt]]
                ]
            ]
        ]

        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: "\(endpoint)/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "RemediationAdvisor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]) 
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "RemediationAdvisor", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: payload])
        }

        let text = extractOutputText(from: data)
        let jsonSnippet = extractFirstJSONObject(in: text)
        guard let snippetData = jsonSnippet.data(using: .utf8) else {
            throw NSError(domain: "RemediationAdvisor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid AI response encoding"]) 
        }

        return try JSONDecoder().decode(OpenAIAdvicePayload.self, from: snippetData)
    }

    private func extractOutputText(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }

        if let direct = json["output_text"] as? String, !direct.isEmpty {
            return direct
        }

        if let output = json["output"] as? [[String: Any]] {
            var fragments: [String] = []
            for element in output {
                if let content = element["content"] as? [[String: Any]] {
                    for block in content {
                        if let text = block["text"] as? String {
                            fragments.append(text)
                        }
                    }
                }
            }
            if !fragments.isEmpty {
                return fragments.joined(separator: "\n")
            }
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractFirstJSONObject(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}
