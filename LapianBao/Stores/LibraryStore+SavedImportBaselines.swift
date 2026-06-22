//
//  LibraryStore+SavedImportBaselines.swift
//  LapianBao
//
//  Saved collection baseline status helpers.
//

import Foundation

extension LibraryStore {
    nonisolated static var savedImportKnownStatuses: Set<String> {
        ["already_recorded", "downloaded", "duplicate", "ignored"]
    }

    nonisolated static var savedImportPendingProtectedStatuses: Set<String> {
        ["downloaded", "duplicate", "ignored"]
    }

    nonisolated static func savedImportStatusIsKnown(_ status: String?) -> Bool {
        guard let status else { return false }
        return savedImportKnownStatuses.contains(status)
    }

    nonisolated static func savedImportStatusProtectsAgainstPendingOverwrite(_ status: String?) -> Bool {
        guard let status else { return false }
        return savedImportPendingProtectedStatuses.contains(status)
    }

    func instagramSavedBaselineKnownSourceKeys() -> Set<String> {
        guard let url = instagramSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        var keys = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any] else { continue }
            let status = entry["status"] as? String
            guard Self.savedImportStatusIsKnown(status) else { continue }
            if let key = Self.instagramContentKey(rawKey) {
                keys.insert(key)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let key = Self.instagramContentKey(sourceURL) {
                keys.insert(key)
            }
        }
        return keys
    }

    func xiaohongshuSavedBaselineKnownNoteIDs() -> Set<String> {
        guard let url = xiaohongshuSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        var noteIDs = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any] else { continue }
            let status = entry["status"] as? String
            guard Self.savedImportStatusIsKnown(status) else { continue }
            if let noteID = Self.xiaohongshuNoteID(fromRawURLString: rawKey) {
                noteIDs.insert(noteID)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let noteID = Self.xiaohongshuNoteID(fromRawURLString: sourceURL) {
                noteIDs.insert(noteID)
            }
        }
        return noteIDs
    }

    func savedImportCandidateIsIgnored(sourceURLString: String) -> Bool {
        guard let sourceURL = URL(string: sourceURLString) else { return false }
        if Self.isInstagramURL(sourceURL) {
            return instagramSavedBaselineIgnoredSourceKeys().contains(Self.instagramContentKey(sourceURLString) ?? "")
        }
        if Self.platformName(for: sourceURL) == "小红书",
           let noteID = Self.xiaohongshuNoteID(fromRawURLString: sourceURLString) {
            return xiaohongshuSavedBaselineIgnoredNoteIDs().contains(noteID)
        }
        return false
    }

    func instagramSavedBaselineIgnoredSourceKeys() -> Set<String> {
        guard let url = instagramSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        var keys = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any],
                  entry["status"] as? String == "ignored"
            else { continue }
            if let key = Self.instagramContentKey(rawKey) {
                keys.insert(key)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let key = Self.instagramContentKey(sourceURL) {
                keys.insert(key)
            }
        }
        return keys
    }

    func xiaohongshuSavedBaselineIgnoredNoteIDs() -> Set<String> {
        guard let url = xiaohongshuSavedBaselineURL() else { return [] }
        let root = ProjectRepository.readJSONObject(at: url)
        guard let results = root["results"] as? [String: Any] else { return [] }

        var noteIDs = Set<String>()
        for (rawKey, rawValue) in results {
            guard let entry = rawValue as? [String: Any],
                  entry["status"] as? String == "ignored"
            else { continue }
            if let noteID = entry["noteID"] as? String, !noteID.isEmpty {
                noteIDs.insert(noteID)
            }
            if let noteID = Self.xiaohongshuNoteID(fromRawURLString: rawKey) {
                noteIDs.insert(noteID)
            }
            if let sourceURL = entry["sourceURL"] as? String,
               let noteID = Self.xiaohongshuNoteID(fromRawURLString: sourceURL) {
                noteIDs.insert(noteID)
            }
        }
        return noteIDs
    }
}
