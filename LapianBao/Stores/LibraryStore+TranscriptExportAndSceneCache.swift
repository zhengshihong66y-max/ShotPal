//
//  LibraryStore+TranscriptExportAndSceneCache.swift
//  LapianBao
//
//  Split from LibraryStore.swift.
//

import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

extension LibraryStore {
    @discardableResult
    func exportTranscriptMarkdown(video: VideoItem) -> Bool {
        guard let libraryURL else { return false }
        let path = video.url.path
        if let existingJob = transcriptExportJobs[path], !existingJob.isFailed { return true }
        transcriptExportJobs.removeValue(forKey: path)
        let segments = transcriptSegmentsByVideoPath[path, default: []]
        guard !segments.isEmpty else { return false }
        let folder = Self.exportFolder(in: libraryURL, named: Self.transcriptExportFolderName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let url = Self.uniqueExportURL(
            in: folder,
            baseName: "\(Self.safeFileStem(video.name))_脚本",
            preferredExtension: "md"
        )
        let sceneCutTimes = sceneCutsByVideoPath[path, default: []].map(\.time)
        let duration = durationByVideoPath[path]
        let videoName = video.name
        let videoFileName = video.url.lastPathComponent

        transcriptExportJobs[path] = TranscriptExportJob(
            videoPath: path,
            videoName: videoName,
            progress: 0.04
        )

        Task { [weak self] in
            self?.updateTranscriptExportProgress(path: path, progress: 0.16)
            let md = await Task.detached(priority: .utility) {
                Self.transcriptExportMarkdown(
                    videoName: videoName,
                    videoFileName: videoFileName,
                    segments: segments,
                    sceneCutTimes: sceneCutTimes,
                    duration: duration
                )
            }.value

            self?.updateTranscriptExportProgress(path: path, progress: 0.78)
            let didWrite = await Task.detached(priority: .utility) {
                (try? md.write(to: url, atomically: true, encoding: .utf8)) != nil
            }.value
            guard didWrite else {
                self?.failTranscriptExport(path: path, message: "无法写入字幕 Markdown")
                return
            }

            let startTime = segments.map(\.start).min() ?? 0
            let endTime = segments.map(\.end).max() ?? startTime
            let export = TranscriptExportItem(
                videoPath: path,
                videoName: videoName,
                filePath: url.path,
                segmentCount: segments.count,
                startTime: startTime,
                endTime: endTime
            )

            if let index = self?.transcriptExports.firstIndex(where: { $0.videoPath == path }) {
                self?.transcriptExports[index] = export
            } else {
                self?.transcriptExports.append(export)
            }
            self?.saveProjectData()
            self?.updateTranscriptExportProgress(path: path, progress: 1.0)
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.transcriptExportJobs.removeValue(forKey: path)
        }

        return true
    }

    func updateTranscriptExportProgress(path: String, progress: Double) {
        guard var job = transcriptExportJobs[path] else { return }
        guard !job.isFailed else { return }
        job.progress = Self.normalizedProgress(progress)
        transcriptExportJobs[path] = job
    }

    func failTranscriptExport(path: String, message: String) {
        guard var job = transcriptExportJobs[path] else { return }
        job.progress = 1
        job.errorMessage = message
        transcriptExportJobs[path] = job

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { [weak self] in
                if self?.transcriptExportJobs[path]?.errorMessage == message {
                    self?.transcriptExportJobs.removeValue(forKey: path)
                }
            }
        }
    }

    @discardableResult
    func deleteTranscriptExport(_ export: TranscriptExportItem) -> Bool {
        guard trashLibraryFileIfPresent(URL(fileURLWithPath: export.filePath), context: "transcript export") else {
            return false
        }

        transcriptExportJobs.removeValue(forKey: export.videoPath)
        let originalCount = transcriptExports.count
        transcriptExports.removeAll { $0.id == export.id || $0.filePath == export.filePath }
        guard transcriptExports.count != originalCount else { return true }
        saveProjectData()
        return true
    }

    @discardableResult
    func exportStoryboardDocument(video: VideoItem) -> Bool {
        guard let libraryURL else { return false }
        let path = video.url.path
        loadCachedSceneCuts(for: video)
        guard let cuts = sceneCutsByVideoPath[path], !cuts.isEmpty else {
            detectSceneCuts(for: video)
            return false
        }

        let folder = Self.exportFolder(in: libraryURL, named: Self.storyboardExportFolderName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let outputURL = Self.uniqueExportURL(
            in: folder,
            baseName: "\(Self.safeFileStem(video.name))_分镜表",
            preferredExtension: "docx"
        )
        let orderedCuts = cuts.sorted { $0.time < $1.time }
        let duration = storyboardExportDuration(
            videoPath: path,
            cuts: orderedCuts,
            segments: transcriptSegmentsByVideoPath[path, default: []]
        )
        let shots = storyboardExportShots(
            video: video,
            cuts: orderedCuts,
            duration: duration,
            segments: transcriptSegmentsByVideoPath[path, default: []],
            musics: musicsByVideoPath[path, default: []]
        )

        Task.detached(priority: .utility) {
            do {
                try Self.writeStoryboardDocx(
                    shots: shots,
                    duration: duration,
                    outputURL: outputURL
                )
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                NSLog("LapianBao storyboard export failed: %@ %@", outputURL.path, String(describing: error))
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        return true
    }

    func storyboardExportDuration(videoPath: String, cuts: [SceneCut], segments: [TranscriptSegment]) -> Double {
        let metadataDuration = durationByVideoPath[videoPath].flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 0
        let subtitleEnd = segments.map(\.end).max() ?? 0
        let cutEnd = cuts.map(\.time).max() ?? 0
        return max(metadataDuration, subtitleEnd, cutEnd)
    }

    func storyboardExportShots(
        video: VideoItem,
        cuts: [SceneCut],
        duration: Double,
        segments: [TranscriptSegment],
        musics: [MusicRecognitionItem]
    ) -> [StoryboardExportShot] {
        let finalEnd = max(duration, cuts.last?.time ?? 0)
        return cuts.enumerated().map { index, cut in
            let start = max(0, cut.time)
            let end: Double
            if cuts.indices.contains(index + 1) {
                end = max(start, cuts[index + 1].time)
            } else {
                end = max(finalEnd, start)
            }
            let subtitles = segments
                .filter { Self.transcriptSegment($0, overlapsSceneStart: start, end: end) }
                .map { Self.singleLineMarkdownText($0.text) }
                .filter { !$0.isEmpty }
            let image = displaySceneCutImage(for: video, cut: cut) ?? cut.thumbnailImage
            return StoryboardExportShot(
                index: index + 1,
                start: start,
                end: end,
                script: subtitles.joined(separator: " "),
                music: Self.storyboardMusicLabel(start: start, end: end, videoDuration: duration, musics: musics),
                imageData: Self.sceneCacheThumbnailData(from: image)
            )
        }
    }

    nonisolated struct StoryboardExportShot: Sendable {
        var index: Int
        var start: Double
        var end: Double
        var script: String
        var music: String
        var imageData: Data?
    }

    nonisolated static func storyboardMusicLabel(
        start: Double,
        end: Double,
        videoDuration: Double,
        musics: [MusicRecognitionItem]
    ) -> String {
        let labels = musics.compactMap { music -> String? in
            let musicStart = max(0, music.detectedAt)
            let musicEnd: Double
            if music.duration.isFinite && music.duration > 0 {
                musicEnd = min(max(videoDuration, end), musicStart + music.duration)
            } else {
                musicEnd = max(videoDuration, end)
            }
            guard max(0, min(end, musicEnd) - max(start, musicStart)) > 0.01 else { return nil }
            let title = music.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = music.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !artist.isEmpty else { return nil }
            return artist.isEmpty ? title : "\(title) - \(artist)"
        }

        var seen = Set<String>()
        let unique = labels.filter { seen.insert($0).inserted }
        return unique.joined(separator: "；")
    }

    nonisolated static func writeStoryboardDocx(
        shots: [StoryboardExportShot],
        duration: Double,
        outputURL: URL
    ) throws {
        let fileManager = FileManager.default
        let packageURL = fileManager.temporaryDirectory
            .appendingPathComponent("LapianBaoStoryboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: packageURL) }

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appendingPathComponent("_rels", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appendingPathComponent("word/_rels", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appendingPathComponent("word/media", isDirectory: true), withIntermediateDirectories: true)

        for shot in shots {
            guard let imageData = shot.imageData else { continue }
            let imageURL = packageURL
                .appendingPathComponent("word/media", isDirectory: true)
                .appendingPathComponent("shot-\(String(format: "%03d", shot.index)).jpg")
            try imageData.write(to: imageURL, options: .atomic)
        }

        try storyboardContentTypesXML.write(
            to: packageURL.appendingPathComponent("[Content_Types].xml"),
            atomically: true,
            encoding: .utf8
        )
        try storyboardPackageRelationshipsXML.write(
            to: packageURL.appendingPathComponent("_rels/.rels"),
            atomically: true,
            encoding: .utf8
        )
        try storyboardDocumentRelationshipsXML(shots: shots).write(
            to: packageURL.appendingPathComponent("word/_rels/document.xml.rels"),
            atomically: true,
            encoding: .utf8
        )
        try storyboardDocumentXML(shots: shots, duration: duration).write(
            to: packageURL.appendingPathComponent("word/document.xml"),
            atomically: true,
            encoding: .utf8
        )

        try? fileManager.removeItem(at: outputURL)
        let result = ExternalProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--sequesterRsrc", packageURL.path, outputURL.path],
            qualityOfService: .utility,
            timeout: 20
        )
        guard result.succeeded, fileManager.fileExists(atPath: outputURL.path) else {
            throw NSError(
                domain: "LapianBao.StoryboardExport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: result.errorText.isEmpty ? "无法生成分镜表 Word 文件" : result.errorText]
            )
        }
    }

    nonisolated static var storyboardContentTypesXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="jpg" ContentType="image/jpeg"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
    }

    nonisolated static var storyboardPackageRelationshipsXML: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
    }

    nonisolated static func storyboardDocumentRelationshipsXML(shots: [StoryboardExportShot]) -> String {
        let relationships = shots
            .filter { $0.imageData != nil }
            .map {
                """
                  <Relationship Id="rId\($0.index)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/shot-\(String(format: "%03d", $0.index)).jpg"/>
                """
            }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(relationships)
        </Relationships>
        """
    }

    nonisolated static func storyboardDocumentXML(shots: [StoryboardExportShot], duration: Double) -> String {
        let columns = [605, 2664, 1613, 893, 1080, 5544, 2333, 1152]
        let headers = ["镜号", "画面", "起止时间", "长度", "景别", "对应脚本/字幕", "音乐/声音", "备注"]
        let grid = columns.map { #"      <w:gridCol w:w="\#($0)"/>"# }.joined(separator: "\n")
        let headerCells = zip(headers, columns).map { title, width in
            storyboardTableCell(
                width: width,
                fill: "EDF2F7",
                content: storyboardParagraph(title, size: 14, bold: true, color: "5F6B7A", alignment: "center")
            )
        }.joined()
        let shotRows = shots.map { shot in
            let cells = [
                storyboardTableCell(width: columns[0], content: storyboardParagraph(String(format: "%02d", shot.index), size: 15, bold: true, alignment: "center")),
                storyboardTableCell(width: columns[1], fill: "F8FAFC", content: shot.imageData == nil ? storyboardParagraph("", size: 14) : storyboardImageParagraph(relationshipID: "rId\(shot.index)")),
                storyboardTableCell(width: columns[2], content: storyboardParagraph("\(storyboardClockText(shot.start))\n-\n\(storyboardClockText(shot.end))", size: 13, alignment: "center")),
                storyboardTableCell(width: columns[3], content: storyboardParagraph(String(format: "%.2fs", max(0, shot.end - shot.start)), size: 14, alignment: "center")),
                storyboardTableCell(width: columns[4], content: storyboardParagraph("", size: 14)),
                storyboardTableCell(width: columns[5], content: storyboardParagraph(shot.script, size: 14)),
                storyboardTableCell(width: columns[6], content: storyboardParagraph(shot.music, size: 14)),
                storyboardTableCell(width: columns[7], content: storyboardParagraph("", size: 14))
            ].joined()
            return """
              <w:tr>
                <w:trPr><w:cantSplit/><w:trHeight w:val="1642" w:hRule="atLeast"/></w:trPr>
            \(cells)
              </w:tr>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
            \(storyboardParagraph("分镜填写版", size: 32, bold: true, spacingAfter: 100))
            <w:tbl>
              <w:tblPr>
                <w:tblW w:w="15884" w:type="dxa"/>
                <w:tblLayout w:type="fixed"/>
                <w:tblBorders>
                  <w:top w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                  <w:left w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                  <w:bottom w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                  <w:right w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                  <w:insideH w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                  <w:insideV w:val="single" w:sz="6" w:space="0" w:color="C9D1DB"/>
                </w:tblBorders>
              </w:tblPr>
              <w:tblGrid>
        \(grid)
              </w:tblGrid>
              <w:tr>
                <w:trPr><w:cantSplit/><w:trHeight w:val="403" w:hRule="atLeast"/></w:trPr>
                \(storyboardTableCell(width: 7942, fill: "EDF2F7", content: storyboardParagraph("总时长：\(storyboardClockText(duration))", size: 15, bold: true, color: "5F6B7A", alignment: "center"), gridSpan: 4))
                \(storyboardTableCell(width: 7942, fill: "EDF2F7", content: storyboardParagraph("总分镜数：\(shots.count)", size: 15, bold: true, color: "5F6B7A", alignment: "center"), gridSpan: 4))
              </w:tr>
              <w:tr>
                <w:trPr><w:tblHeader/><w:cantSplit/><w:trHeight w:val="461" w:hRule="atLeast"/></w:trPr>
        \(headerCells)
              </w:tr>
        \(shotRows)
            </w:tbl>
            <w:sectPr>
              <w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>
              <w:pgMar w:top="518" w:right="475" w:bottom="461" w:left="475" w:header="288" w:footer="259" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    nonisolated static func storyboardTableCell(width: Int, fill: String? = nil, content: String, gridSpan: Int? = nil) -> String {
        let fillXML = fill.map { #"<w:shd w:fill="\#($0)"/>"# } ?? ""
        let spanXML = gridSpan.map { #"<w:gridSpan w:val="\#($0)"/>"# } ?? ""
        return """
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="\(width)" w:type="dxa"/>
                \(spanXML)
                \(fillXML)
                <w:tcMar>
                  <w:top w:w="70" w:type="dxa"/>
                  <w:start w:w="80" w:type="dxa"/>
                  <w:bottom w:w="70" w:type="dxa"/>
                  <w:end w:w="80" w:type="dxa"/>
                </w:tcMar>
                <w:vAlign w:val="center"/>
              </w:tcPr>
              \(content)
            </w:tc>
        """
    }

    nonisolated static func storyboardParagraph(
        _ text: String,
        size: Int,
        bold: Bool = false,
        color: String = "111827",
        alignment: String = "left",
        spacingAfter: Int = 0
    ) -> String {
        let runs = storyboardTextRuns(text, size: size, bold: bold, color: color)
        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="\(alignment)"/>
            <w:spacing w:before="0" w:after="\(spacingAfter)"/>
          </w:pPr>
          \(runs)
        </w:p>
        """
    }

    nonisolated static func storyboardTextRuns(_ text: String, size: Int, bold: Bool, color: String) -> String {
        let parts = text.components(separatedBy: .newlines)
        guard !parts.isEmpty else {
            return storyboardRun("", size: size, bold: bold, color: color)
        }
        return parts.enumerated().map { index, part in
            let prefix = index == 0 ? "" : "<w:br/>"
            return storyboardRun(part, size: size, bold: bold, color: color, prefix: prefix)
        }.joined()
    }

    nonisolated static func storyboardRun(
        _ text: String,
        size: Int,
        bold: Bool,
        color: String,
        prefix: String = ""
    ) -> String {
        let boldXML = bold ? "<w:b/>" : ""
        return """
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="PingFang SC"/>
            \(boldXML)
            <w:color w:val="\(color)"/>
            <w:sz w:val="\(size)"/>
          </w:rPr>
          \(prefix)<w:t xml:space="preserve">\(xmlEscaped(text))</w:t>
        </w:r>
        """
    }

    nonisolated static func storyboardImageParagraph(relationshipID: String) -> String {
        """
        <w:p>
          <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="0"/></w:pPr>
          <w:r>
            <w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0">
                <wp:extent cx="1600200" cy="900000"/>
                <wp:docPr id="1" name="Shot"/>
                <a:graphic>
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic>
                      <pic:nvPicPr>
                        <pic:cNvPr id="0" name="shot.jpg"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relationshipID)"/>
                        <a:stretch><a:fillRect/></a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="1600200" cy="900000"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        """
    }

    nonisolated static func storyboardClockText(_ seconds: Double) -> String {
        let safeSeconds = max(0, seconds)
        let total = Int(safeSeconds.rounded(.down))
        let minutes = (total % 3600) / 60
        let hours = total / 3600
        let wholeSeconds = total % 60
        let fraction = Int(((safeSeconds - Double(total)) * 100).rounded())
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%02d", hours, minutes, wholeSeconds, fraction)
        }
        return String(format: "%02d:%02d.%02d", minutes, wholeSeconds, fraction)
    }

    nonisolated static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    nonisolated static func transcriptExportMarkdown(
        videoName: String,
        videoFileName: String,
        segments: [TranscriptSegment],
        sceneCutTimes: [Double],
        duration: Double?
    ) -> String {
        let orderedSegments = segments.sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        let sceneBlocks = transcriptSceneBlocks(
            segments: orderedSegments,
            sceneCutTimes: sceneCutTimes,
            duration: duration
        )
        let sceneBody = sceneBlocks.map { transcriptSceneMarkdown($0) }.joined(separator: "\n\n")
        let transcriptBody = orderedSegments
            .map { "- [\(clockText($0.start)) - \(clockText($0.end))] \(singleLineMarkdownText($0.text))" }
            .joined(separator: "\n")
        let sceneSource = sceneCutTimes.isEmpty ? "未检测到分镜切点，使用整条时间线作为单个分镜。" : "使用场景识别切点划分分镜。"

        return """
        # \(videoName)

        ## AI 分镜字幕索引

        - 视频文件：\(videoFileName)
        - 分镜数：\(sceneBlocks.count)
        - 字幕段数：\(orderedSegments.count)
        - 时间格式：HH:MM:SS 或 MM:SS
        - 分镜来源：\(sceneSource)

        \(sceneBody)

        ## 原脚本

        \(transcriptBody)
        """
    }

    nonisolated static func transcriptSceneBlocks(
        segments: [TranscriptSegment],
        sceneCutTimes: [Double],
        duration: Double?
    ) -> [TranscriptSceneBlock] {
        let maxSegmentEnd = segments.map { max($0.start, $0.end) }.max() ?? 0
        let validDuration = duration.map { $0.isFinite && $0 > 0 ? $0 : 0 } ?? 0
        let timelineEnd = max(validDuration, maxSegmentEnd)
        let cutTimes = stableSceneCutTimes(from: sceneCutTimes)
            .filter { $0 > 0 && (timelineEnd <= 0 || $0 < timelineEnd) }
        let finalEnd = max(timelineEnd, cutTimes.last ?? 0, maxSegmentEnd)
        let boundaries = ([0] + cutTimes + [finalEnd]).filter { $0.isFinite }
        let ranges = zip(boundaries.dropLast(), boundaries.dropFirst()).filter { $0.1 >= $0.0 }

        let blocks = ranges.enumerated().map { offset, range in
            let start = range.0
            let end = max(range.1, start)
            let subtitles = segments.filter { transcriptSegment($0, overlapsSceneStart: start, end: end) }
            return TranscriptSceneBlock(index: offset + 1, start: start, end: end, subtitles: subtitles)
        }

        if !blocks.isEmpty { return blocks }
        return [
            TranscriptSceneBlock(
                index: 1,
                start: 0,
                end: max(maxSegmentEnd, 0),
                subtitles: segments
            )
        ]
    }

    nonisolated static func transcriptSegment(_ segment: TranscriptSegment, overlapsSceneStart start: Double, end: Double) -> Bool {
        let segmentStart = max(0, segment.start)
        let segmentEnd = max(segmentStart, segment.end)
        guard end > start else {
            return segmentStart >= start
        }
        return segmentStart < end && segmentEnd > start
    }

    nonisolated static func transcriptSceneMarkdown(_ block: TranscriptSceneBlock) -> String {
        let subtitles = block.subtitles
            .map { "- [\(clockText($0.start)) - \(clockText($0.end))] \(singleLineMarkdownText($0.text))" }
            .joined(separator: "\n")
        let subtitleBody = subtitles.isEmpty ? "- 无对应字幕" : subtitles
        return """
        ### 分镜 \(block.index) [\(clockText(block.start)) - \(clockText(block.end))]

        - scene_index: \(block.index)
        - scene_start: \(clockText(block.start))
        - scene_end: \(clockText(block.end))
        - subtitle_count: \(block.subtitles.count)

        \(subtitleBody)
        """
    }

    nonisolated static func singleLineMarkdownText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func sceneIndex(for video: VideoItem, at time: Double) -> Int? {
        guard let cuts = sceneCutsByVideoPath[video.url.path], !cuts.isEmpty else { return nil }
        return cuts.lastIndex { $0.time <= time }
    }

    func sceneCutCacheURL() -> URL? {
        libraryURL.map(ProjectRepository.sceneCutsURL)
    }

    func loadSceneCutCache() {
        guard
            let url = sceneCutCacheURL(),
            let cache = ProjectRepository.readJSON(SceneCutCacheFile.self, from: url)
        else {
            sceneCutCache = [:]
            return
        }

        sceneCutCache = cache.entries
    }

    func saveSceneCutCache() {
        guard let url = sceneCutCacheURL() else { return }

        let cache = SceneCutCacheFile(
            detectorVersion: Self.sceneDetectorVersion,
            entries: sceneCutCache
        )

        do {
            try ProjectRepository.writeJSON(cache, to: url, encoder: ProjectRepository.prettySortedEncoder)
        } catch {
            return
        }
    }

    func validCachedSceneCutEntry(for video: VideoItem) -> SceneCutCacheEntry? {
        sceneCutCacheEntry(for: video, migrateRelocatedEntry: false)
    }

    func sceneCutCacheEntry(for video: VideoItem, migrateRelocatedEntry: Bool) -> SceneCutCacheEntry? {
        let key = relativeVideoPath(for: video.url)
        guard let signature = videoFileSignature(for: video.url) else { return nil }

        if let entry = sceneCutCache[key],
           sceneCutCacheEntry(entry, matches: signature, expectedRelativePath: key) {
            if migrateRelocatedEntry,
               entry.detectorVersion != Self.sceneDetectorVersion {
                var currentEntry = entry
                currentEntry.detectorVersion = Self.sceneDetectorVersion
                sceneCutCache[key] = currentEntry
                saveSceneCutCache()
                return currentEntry
            }
            return entry
        }

        guard let relocatedEntry = relocatedSceneCutCacheEntry(
            for: video,
            currentRelativePath: key,
            signature: signature
        ) else { return nil }

        if migrateRelocatedEntry {
            sceneCutCache[key] = relocatedEntry
            saveSceneCutCache()
            PerformanceDiagnostics.mark(
                "scene cache relocated from previous library path",
                path: video.url.path
            )
        }

        return relocatedEntry
    }

    func sceneCutCacheEntry(
        _ entry: SceneCutCacheEntry,
        matches signature: (fileSize: Int64, modificationTime: Double),
        expectedRelativePath: String? = nil
    ) -> Bool {
        guard
            Self.sceneDetectorCacheCompatibleVersions.contains(entry.detectorVersion),
            expectedRelativePath.map({ entry.relativePath == $0 }) ?? true
        else { return false }

        guard
            entry.fileSize == signature.fileSize,
            abs(entry.modificationTime - signature.modificationTime) < 1.0
        else { return false }

        return true
    }

    func relocatedSceneCutCacheEntry(
        for video: VideoItem,
        currentRelativePath: String,
        signature: (fileSize: Int64, modificationTime: Double)
    ) -> SceneCutCacheEntry? {
        let currentFileName = video.url.lastPathComponent
        let matches = sceneCutCache.compactMap { sourceKey, entry -> SceneCutCacheEntry? in
            guard sourceKey != currentRelativePath else { return nil }
            guard URL(fileURLWithPath: entry.relativePath).lastPathComponent == currentFileName else { return nil }
            guard sceneCutCacheEntry(entry, matches: signature) else { return nil }
            return entry
        }
        guard matches.count == 1, var entry = matches.first else { return nil }

        entry.relativePath = currentRelativePath
        entry.detectorVersion = Self.sceneDetectorVersion
        entry.videoID = stableVideoID(for: currentRelativePath)
        entry.sceneIDs = entry.cutTimes.indices.map { sceneID(for: currentRelativePath, index: $0) }
        return entry
    }

    func hasSceneRecognitionResult(for video: VideoItem) -> Bool {
        sceneCutsByVideoPath[video.url.path] != nil || validCachedSceneCutEntry(for: video) != nil
    }

    func sceneRecognitionCutCount(for video: VideoItem) -> Int? {
        if let cuts = sceneCutsByVideoPath[video.url.path] {
            return cuts.count
        }
        return validCachedSceneCutEntry(for: video).map { Self.stableSceneCutTimes(from: $0.cutTimes).count }
    }

    func storeSceneCutCache(for video: VideoItem, cuts: [SceneCut]) {
        guard let signature = videoFileSignature(for: video.url) else { return }

        let relativePath = relativeVideoPath(for: video.url)
        let orderedCuts = cuts.sorted { $0.time < $1.time }
        let cutTimes = orderedCuts
            .map { round($0.time * 1000) / 1000 }
        let thumbnailData = sceneCutCacheThumbnailData(from: orderedCuts)

        sceneCutCache[relativePath] = SceneCutCacheEntry(
            detectorVersion: Self.sceneDetectorVersion,
            videoID: stableVideoID(for: relativePath),
            relativePath: relativePath,
            fileSize: signature.fileSize,
            modificationTime: signature.modificationTime,
            duration: durationByVideoPath[video.url.path],
            cutTimes: cutTimes,
            thumbnailData: thumbnailData,
            sceneIDs: cutTimes.indices.map { sceneID(for: relativePath, index: $0) },
            generatedAt: Date()
        )
        saveSceneCutCache()
    }

    func sceneCutCacheThumbnailData(from cuts: [SceneCut]) -> [Data]? {
        guard !cuts.isEmpty else { return [] }
        var thumbnails: [Data] = []
        thumbnails.reserveCapacity(cuts.count)

        for cut in cuts {
            guard !cut.isPlaceholder,
                  let data = Self.sceneCacheThumbnailData(from: cut.thumbnailImage)
            else { return nil }
            thumbnails.append(data)
        }

        return thumbnails
    }

    nonisolated static func sceneCacheThumbnailData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }

    func videoFileSignature(for url: URL) -> (fileSize: Int64, modificationTime: Double)? {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let fileSize = values.fileSize,
            let modificationDate = values.contentModificationDate
        else { return nil }

        return (Int64(fileSize), modificationDate.timeIntervalSince1970)
    }

    func relativeVideoPath(for url: URL) -> String {
        guard let libraryURL else { return url.lastPathComponent }

        let libraryPath = libraryURL.standardizedFileURL.path
        let videoPath = url.standardizedFileURL.path
        let prefix = libraryPath.hasSuffix("/") ? libraryPath : libraryPath + "/"
        guard videoPath.hasPrefix(prefix) else { return url.lastPathComponent }

        return String(videoPath.dropFirst(prefix.count))
    }

    func stableVideoID(for relativePath: String) -> String {
        "video-\(Self.fnv1a64(relativePath))"
    }

    func sceneID(for relativePath: String, index: Int) -> String {
        "\(stableVideoID(for: relativePath))-scene-\(String(format: "%04d", index + 1))"
    }

}
