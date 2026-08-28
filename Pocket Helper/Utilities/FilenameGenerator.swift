import Foundation

struct FilenameGenerator {
    static let maximumStemLength = 120

    static func stem(
        originalFilename: String,
        kind: MediaKind,
        rule: FilenameRule,
        suffix: String,
        template: String,
        counter: Int,
        date: Date
    ) -> String {
        let original = URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"
        let day = dateFormatter.string(from: date)
        dateFormatter.dateFormat = "HHmmss"
        let time = dateFormatter.string(from: date)

        let raw: String
        switch rule {
        case .originalWithSuffix:
            raw = original + suffix
        case .automaticCounter:
            raw = String(format: "PH_%06d", counter)
        case .customTemplate:
            raw = template
                .replacingOccurrences(of: "{original}", with: original)
                .replacingOccurrences(of: "{date}", with: day)
                .replacingOccurrences(of: "{time}", with: time)
                .replacingOccurrences(of: "{counter}", with: String(format: "%06d", counter))
                .replacingOccurrences(of: "{media}", with: kind.rawValue)
        }
        return sanitize(raw)
    }

    static func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let components = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        let joined = components.joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let result = joined.isEmpty ? "Pocket_Helper" : joined
        return String(result.prefix(maximumStemLength))
    }

    static func filenames(stem: String, kind: MediaKind) -> (primary: String, paired: String?) {
        switch kind {
        case .photo:
            return ("\(stem).HEIC", nil)
        case .video:
            return ("\(stem).mov", nil)
        case .livePhoto:
            return ("\(stem).HEIC", "\(stem).mov")
        }
    }
}
