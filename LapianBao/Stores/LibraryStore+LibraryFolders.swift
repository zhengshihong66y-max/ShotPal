//
//  LibraryStore+LibraryFolders.swift
//  LapianBao
//
//  Folder names and path helpers for user-selected libraries.
//

import Foundation

extension LibraryStore {
    nonisolated static var exportRootFolderName: String { "LapianBaoExports" }
    nonisolated static var videoFolderName: String { "拉片宝视频下载" }
    nonisolated static var imageExportFolderName: String { "拉片宝图片导出" }
    nonisolated static var soundEffectExportFolderName: String { "拉片宝音频导出" }
    nonisolated static var transcriptExportFolderName: String { "拉片宝脚本导出" }
    nonisolated static var storyboardExportFolderName: String { "拉片宝分镜表导出" }
    nonisolated static var musicExportFolderName: String { "拉片宝音乐下载" }
    nonisolated static var nonRecognizedMusicPackageFolderName: String { "非识别音乐打包" }

    nonisolated static var legacyVideoFolderName: String { "视频" }
    nonisolated static var legacyImageExportFolderName: String { "图片" }
    nonisolated static var legacyAudioExportFolderName: String { "音频" }
    nonisolated static var legacySoundEffectExportFolderName: String { "音效" }
    nonisolated static var legacyTranscriptExportFolderName: String { "字幕" }
    nonisolated static var legacyMusicExportFolderName: String { "音乐" }

    nonisolated static func exportFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static func legacyExportFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL
            .appendingPathComponent(exportRootFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static func mediaFolder(in libraryURL: URL, named folderName: String) -> URL {
        libraryURL.appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated static func ensureMediaFolders(in libraryURL: URL) {
        for folderName in [videoFolderName, musicExportFolderName, soundEffectExportFolderName, imageExportFolderName, transcriptExportFolderName, storyboardExportFolderName] {
            try? FileManager.default.createDirectory(
                at: mediaFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }

    nonisolated static func ensureExportFolders(in libraryURL: URL) {
        for folderName in [imageExportFolderName, soundEffectExportFolderName, transcriptExportFolderName, storyboardExportFolderName, musicExportFolderName, videoFolderName] {
            try? FileManager.default.createDirectory(
                at: exportFolder(in: libraryURL, named: folderName),
                withIntermediateDirectories: true
            )
        }
    }
}
