import Foundation

struct TextTransformer: ContentTransforming {
    func transform(_ text: String, using transformation: TextTransformation) throws -> String {
        switch transformation {
        case .plain: return text
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .capitalize: return text.capitalized
        case .collapseSpaces:
            return text
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .spacesToUnderscores:
            return text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
        case .urlEncode:
            guard let result = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { throw NabiraError.invalidTransformation }
            return result
        case .urlDecode:
            guard let result = text.removingPercentEncoding else { throw NabiraError.invalidTransformation }
            return result
        case .jsonPretty, .jsonMinify:
            guard let data = text.data(using: .utf8) else { throw NabiraError.invalidTransformation }
            let object = try JSONSerialization.jsonObject(with: data)
            let options: JSONSerialization.WritingOptions = transformation == .jsonPretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: options), as: UTF8.self)
        }
    }
}
