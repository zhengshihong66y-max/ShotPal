//
//  FrameAnalysis.swift
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

enum FrameAnalysisState {
    case idle
    case loading
    case loaded(FrameImageAnalysis)
    case failed(String)
}

struct FrameImageAnalysis: Codable {
    var shotSize: String
    var composition: String
    var color: String
}

struct FrameAnalysisSummary: View {
    let analysis: FrameImageAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            analysisRow("景别", value: analysis.shotSize)
            analysisRow("构图", value: analysis.composition)
            analysisRow("色调", value: analysis.color)
        }
        .font(.caption)
        .padding(10)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func analysisRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value.isEmpty ? "不确定" : value)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum LocalFrameAnalyzer {
    private static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")
        ?? URL(fileURLWithPath: "/dev/null")
    private static let model = "qwen3-vl:8b"

    struct RequestBody: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
        let format: String
        let think: Bool
    }

    struct ResponseBody: Decodable {
        let response: String
        let thinking: String?
    }

    static func analyze(imageData: Data) async throws -> FrameImageAnalysis {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: model,
            prompt: prompt,
            images: [imageData.base64EncodedString()],
            stream: false,
            format: "json",
            think: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AnalysisError.serviceUnavailable
        }

        let ollamaResponse = try JSONDecoder().decode(ResponseBody.self, from: data)
        let jsonText = ollamaResponse.response.isEmpty ? (ollamaResponse.thinking ?? "") : ollamaResponse.response
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        return try JSONDecoder().decode(FrameImageAnalysis.self, from: jsonData)
    }

    static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .cannotConnectToHost {
            return "未连接到本机 Ollama。请先启动 Ollama，并安装视觉模型 \(model)。"
        }
        if error is DecodingError {
            return "模型返回格式无法解析，请重试或换用更稳定的视觉模型。"
        }
        if error is AnalysisError {
            return "本机视觉模型暂时不可用，请确认 Ollama 正在运行。"
        }
        return "分析失败：\(error.localizedDescription)"
    }

    private static var prompt: String {
        """
        你是影视拉片助手。请只根据这张画面本身分析三个条目，并返回严格 JSON，不要输出解释。
        不要猜导演、摄影师、作品名、真实镜头焦段、真实拍摄器材或画面外信息。
        景别只能从这些里选择：大远景、远景、全景、中全景、中景、中近景、近景、特写、大特写、不确定。
        构图从这些可见结构里选择 1 到 3 个，用中文顿号连接：中心构图、三分构图、对称构图、框中框、引导线构图、纵深构图、前景遮挡、留白构图、低角度构图、高角度构图、倾斜构图、紧密构图、开放构图、平衡构图、不确定。
        色调用一句中文概括主色、冷暖、明暗、饱和度和对比度；只描述画面可见色彩。
        JSON 格式：
        {
          "shotSize": "中景",
          "composition": "中心构图、纵深构图",
          "color": "暖色调为主，中间调，低饱和，中等对比"
        }
        """
    }

    enum AnalysisError: Error {
        case serviceUnavailable
        case invalidResponse
    }
}

struct RecognizedMusicAsset: Identifiable {
    var videoPath: String
    var videoName: String
    var song: MusicRecognitionItem

    var id: String { "\(videoPath)-\(song.id.uuidString)" }
}

struct MusicTagStrip: View {
    let tags: [String]

    private var visibleTags: [String] {
        Array(tags.prefix(4))
    }

    private var overflowCount: Int {
        max(0, tags.count - visibleTags.count)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleTags, id: \.self) { tag in
                CardInlineTagChip(tag: tag)
            }

            if overflowCount > 0 {
                VideoTagOverflowChip(count: overflowCount)
                    .frame(height: 18, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .clipped()
    }
}
