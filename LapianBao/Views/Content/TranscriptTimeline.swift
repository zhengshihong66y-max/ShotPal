//
//  TranscriptTimeline.swift
//  LapianBao
//
//  Split from ContentView.swift.
//

import SwiftUI
import AVFoundation
import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum TranscriptTimelineStatus: Equatable {
    case idle
    case running(videoPath: String)
    case loaded(videoPath: String, chapters: [TranscriptTimelineChapter])
    case failed(videoPath: String, message: String)
}

struct TranscriptTimelineChapter: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Double
    var end: Double?
    var segmentID: UUID
    var type: String
    var summary: String
    var isModelGenerated: Bool
}

enum LocalTranscriptTimelineAnalyzer {
    private static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")
        ?? URL(fileURLWithPath: "/dev/null")
    private static let model = "qwen3:4b-instruct"

    private struct RequestBody: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let format: String
        let think: Bool
        let options: Options
    }

    private struct Options: Encodable {
        let temperature: Double
        let numCtx: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numCtx = "num_ctx"
        }
    }

    private struct ResponseBody: Decodable {
        let response: String
        let thinking: String?
    }

    private struct TimelineResponse: Decodable {
        let chapters: [TimelineChapterDTO]
    }

    private struct TimelineChapterDTO: Decodable {
        let start: Double
        let end: Double?
        let title: String
        let type: String
        let summary: String
    }

    private struct SourceLine {
        let start: Double
        let end: Double
        let text: String
    }

    static func analyze(videoName: String, videoAuthor: String? = nil, segments: [TranscriptSegment]) async throws -> [TranscriptTimelineChapter] {
        guard let firstSegment = segments.first, let lastSegment = segments.last else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            prompt: prompt(videoName: videoName, videoAuthor: videoAuthor, sourceLines: sourceLines(from: segments)),
            stream: false,
            format: "json",
            think: false,
            options: Options(temperature: 0.2, numCtx: 8192)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AnalysisError.serviceUnavailable
        }

        let ollamaResponse = try JSONDecoder().decode(ResponseBody.self, from: data)
        let rawText = ollamaResponse.response.isEmpty ? (ollamaResponse.thinking ?? "") : ollamaResponse.response
        guard let jsonData = extractJSON(from: rawText).data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(TimelineResponse.self, from: jsonData)
        let chapters = decoded.chapters
            .compactMap { dto in
                chapter(from: dto, segments: segments, minStart: firstSegment.start, maxEnd: lastSegment.end)
            }
            .sorted { $0.start < $1.start }

        guard !chapters.isEmpty else { throw AnalysisError.invalidResponse }
        return Array(chapters.prefix(12))
    }

    static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .cannotConnectToHost {
            return "未连接到本机 Ollama。请先启动 Ollama，并安装文本模型 \(model)。"
        }
        if error is DecodingError {
            return "模型返回的时间线格式无法解析，请重试一次。"
        }
        if error is AnalysisError {
            return "本机文本模型暂时不可用，请确认 Ollama 正在运行。"
        }
        return "生成失败：\(error.localizedDescription)"
    }

    private static func prompt(videoName: String, videoAuthor: String?, sourceLines: [SourceLine]) -> String {
        let transcript = sourceLines.map {
            "[\(clockText($0.start))-\(clockText($0.end))] \($0.text)"
        }.joined(separator: "\n")
        let authorLine = videoAuthor
            .map { "视频作者：\($0)\n" }
            ?? ""

        return """
        你是剪辑师和口播稿结构分析助手。请根据带时间戳的口播转录稿，为视频《\(videoName)》生成内容时间线。
        \(authorLine)视频作者只作为来源上下文，不要把作者名当作转录稿内容。
        只使用转录稿信息，不要猜画面、导演、摄影或外部资料。
        输出 4 到 12 个章节；如果内容很短，可以输出更少。
        每章 start 和 end 必须落在转录稿时间范围内，单位为秒；title 不超过 12 个中文字符；summary 不超过 45 个中文字符。
        type 只能从这些里选择：开场、铺垫、观点、案例、解释、转折、情绪点、金句、总结、行动提示。
        只返回严格 JSON，不要 Markdown，不要解释。
        JSON 格式：
        {"chapters":[{"start":0.0,"end":12.3,"title":"核心标题","type":"观点","summary":"这一段在说什么"}]}

        转录稿：
        \(transcript)
        """
    }

    private static func sourceLines(from segments: [TranscriptSegment]) -> [SourceLine] {
        var lines: [SourceLine] = []
        var currentStart: Double?
        var currentEnd: Double = 0
        var currentText = ""

        func appendCurrent() {
            guard let start = currentStart else { return }
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            lines.append(SourceLine(start: start, end: currentEnd, text: trimmed))
        }

        for segment in segments {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if currentStart == nil {
                currentStart = segment.start
                currentEnd = segment.end
            }

            let start = currentStart ?? segment.start
            let wouldBeLong = currentText.count + text.count > 280
            let wouldBeWide = segment.end - start > 35
            if !currentText.isEmpty, wouldBeLong || wouldBeWide {
                appendCurrent()
                currentStart = segment.start
                currentEnd = segment.end
                currentText = text
            } else {
                currentEnd = max(currentEnd, segment.end)
                currentText = currentText.isEmpty ? text : "\(currentText) \(text)"
            }
        }
        appendCurrent()

        guard lines.count > 220 else { return lines }
        let stride = Double(lines.count) / 220.0
        return (0 ..< 220).map { index in
            lines[min(Int(Double(index) * stride), lines.count - 1)]
        }
    }

    private static func chapter(
        from dto: TimelineChapterDTO,
        segments: [TranscriptSegment],
        minStart: Double,
        maxEnd: Double
    ) -> TranscriptTimelineChapter? {
        let start = min(max(dto.start, minStart), maxEnd)
        guard let nearest = nearestSegment(in: segments, to: start) else { return nil }
        let rawEnd = dto.end ?? nearest.end
        let end = min(max(rawEnd, start), maxEnd)

        return TranscriptTimelineChapter(
            title: clean(dto.title, fallback: "内容段落", maxLength: 12),
            start: start,
            end: end,
            segmentID: nearest.id,
            type: clean(dto.type, fallback: "观点", maxLength: 6),
            summary: clean(dto.summary, fallback: nearest.text, maxLength: 45),
            isModelGenerated: true
        )
    }

    private static func nearestSegment(in segments: [TranscriptSegment], to time: Double) -> TranscriptSegment? {
        segments.min { lhs, rhs in
            abs(lhs.start - time) < abs(rhs.start - time)
        }
    }

    private static func clean(_ value: String, fallback: String, maxLength: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        return String(text.prefix(maxLength))
    }

    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start ... end])
    }

    enum AnalysisError: Error {
        case serviceUnavailable
        case invalidResponse
    }
}
