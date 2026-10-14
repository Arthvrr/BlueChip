import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    var role: String // "user" ou "model"
    var text: String
}

class GeminiService {
    static let shared = GeminiService()
    
    // La fonction mise à jour qui accepte 'systemPrompt'
    func generateChatResponse(systemPrompt: String, messages: [ChatMessage], apiKey: String) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "Gemini", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key is empty."])
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=\(cleanKey)") else {
            throw URLError(.badURL)
        }
        
        // Formatage des messages de chat
        let contents = messages.map { msg -> [String: Any] in
            return [
                "role": msg.role,
                "parts": [["text": msg.text]]
            ]
        }
        
        // Construction du payload avec les "System Instructions"
        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.2
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Lecture d'erreur
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = json["error"] as? [String: Any],
               let message = errorDict["message"] as? String {
                throw NSError(domain: "Gemini", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "Gemini", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error: \(httpResponse.statusCode)"])
        }
        
        // Décodage
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        
        return text ?? "No response generated."
    }
}

