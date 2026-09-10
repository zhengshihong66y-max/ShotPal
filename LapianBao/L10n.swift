import Foundation

/// Presentation strings follow macOS's preferred app language. Persisted values stay unchanged.
nonisolated enum L10n {
    nonisolated struct Message: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]

        init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []

            init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            mutating func appendLiteral(_ literal: String) { key += literal }

            mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(arguments.count)}"
                arguments.append(String(describing: value))
            }
        }
    }

    static func text(_ message: Message) -> String {
        render(key(message.key), arguments: message.arguments)
    }

    /// Use only for known presentation keys, never arbitrary user text.
    static func key(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// One-pass substitution preserves braces in user data and avoids printf interpretation.
    static func render(_ template: String, arguments: [String]) -> String {
        var result = ""
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]),
               arguments.indices.contains(index) {
                result += arguments[index]
                cursor = template.index(after: end)
            } else {
                result.append(template[cursor])
                cursor = template.index(after: cursor)
            }
        }
        return result
    }
}

extension L10n {
    /// The bundled workers have a stable Chinese text protocol. Translate known messages
    /// at the UI boundary, leaving the worker protocol and unknown diagnostic details intact.
    nonisolated static func workerMessage(_ message: String) -> String {
        let partial = "部分片段识别失败，已保留识别出的歌曲。"
        if message.hasPrefix(partial) {
            return key(partial) + workerMessage(String(message.dropFirst(partial.count)))
        }
        let exact = key(message)
        if exact != message { return exact }
        for entry in workerPatterns {
            let range = NSRange(message.startIndex..., in: message)
            guard let match = entry.regex.firstMatch(in: message, range: range) else { continue }
            let arguments = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: message) else { return nil }
                return String(message[range])
            }
            return render(key(entry.key), arguments: arguments)
        }
        return message
    }

    nonisolated private static let workerPatterns: [(key: String, regex: NSRegularExpression)] = [
        "音乐识别服务请求失败（{0}），请检查网络后重试",
        "文件不存在：{0}",
        "音频过短：当前约 {0} 秒",
        "共 {0} 段"
    ].compactMap { key in
        let pattern = "^" + key.components(separatedBy: "{0}")
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "(.*?)") + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (key, regex)
    }
}
