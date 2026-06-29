//
//  LibraryStore+Annotations.swift
//  LapianBao
//

import Foundation

extension LibraryStore {
    @discardableResult
    func addAnnotation(video: VideoItem, time: Double, text: String, kind: AnnotationItem.Kind = .frame) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        annotations.append(AnnotationItem(
            videoPath: video.url.path,
            videoName: video.name,
            time: max(0, time),
            kind: kind,
            text: trimmed
        ))
        saveProjectData()
        return true
    }

    @discardableResult
    func updateAnnotation(_ annotation: AnnotationItem, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = annotations.firstIndex(where: { $0.id == annotation.id })
        else { return false }
        annotations[index].text = trimmed
        annotations[index].updatedAt = Date()
        saveProjectData()
        return true
    }

    func deleteAnnotation(_ annotation: AnnotationItem) {
        annotations.removeAll { $0.id == annotation.id }
        saveProjectData()
    }
}
