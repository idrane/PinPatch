import Foundation

enum PPTitleNormalizer {
    private static let preserveSuffixPattern = #"(?i)\b(?:(?:room|floor|stage|apartment)\s*\d+|\d+\s*(?:room|floor|stage|apartment))\b"#
    private static let uuidPattern = #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"#
    private static let orderPattern = #"(?i)\border\s*(?:number|no\.?|id)?\s*[:#-]?\s*[\p{L}\p{N}-]{3,}"#
    private static let idPattern = #"(?i)\bid\s*(?:[:#-]|\s)\s*[A-Z0-9-]{2,}\b"#
    private static let datePattern = #"\b(?:19|20)\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b"#
    private static let timePattern = #"\b(?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?\b"#

    static func normalize(_ title: String?) -> String? {
        guard let title else { return nil }
        var value = title.precomposedStringWithCanonicalMapping
        let (protected, preserved) = protectMatches(in: value, pattern: preserveSuffixPattern)
        value = protected
        value = replace(value, pattern: uuidPattern, with: "{uuid}")
        value = replace(value, pattern: orderPattern, with: "{order}")
        value = replace(value, pattern: idPattern, with: "{id}")
        value = replace(value, pattern: datePattern, with: "{date}")
        value = replace(value, pattern: timePattern, with: "{time}")
        for (placeholder, token) in preserved {
            value = value.replacingOccurrences(of: placeholder, with: token)
        }
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func replace(_ value: String, pattern: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func protectMatches(in value: String, pattern: String) -> (String, [(String, String)]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (value, []) }
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        let mutable = NSMutableString(string: value)
        var replacements: [(String, String)] = []
        for (index, match) in matches.enumerated().reversed() {
            let placeholder = "⟦pinpatch-preserve-\(index)⟧"
            replacements.append((placeholder, mutable.substring(with: match.range)))
            mutable.replaceCharacters(in: match.range, with: placeholder)
        }
        return (mutable as String, replacements)
    }
}
