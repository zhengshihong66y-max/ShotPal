//
//  MusicTagging.swift
//  LapianBao
//
//  Music genre normalization and fallback inference.
//

import Foundation

extension MusicRecognitionItem {
    nonisolated static var defaultMusicGenreTag: String { "Soundtrack" }
    nonisolated static var fallbackMusicTag: String { "未分类" }
    nonisolated static var featuredMusicTag: String { "精选" }

    nonisolated static func cleanedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    nonisolated static func cleanedGenreTags(
        _ tags: [String],
        title: String = "",
        artist: String = ""
    ) -> [String] {
        let titleKey = canonicalMusicGenreKey(title)
        let artistKey = canonicalMusicGenreKey(artist)
        let artistParts = artist
            .components(separatedBy: CharacterSet(charactersIn: ",，/、·&+;；"))
            .map(canonicalMusicGenreKey)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let genre = canonicalMusicGenreTag(tag) else { return nil }
            let key = canonicalMusicGenreKey(genre)
            guard !key.isEmpty else { return nil }
            guard key != titleKey, key != artistKey else { return nil }
            guard !artistParts.contains(key) else { return nil }
            guard !isFallbackMusicTag(genre) else { return nil }
            guard seen.insert(key).inserted else { return nil }
            return genre
        }
        .sorted()
    }

    nonisolated static func cleanedMusicTags(
        _ tags: [String],
        title: String = "",
        artist: String = ""
    ) -> [String] {
        let titleKey = canonicalMusicGenreKey(title)
        let artistKey = canonicalMusicGenreKey(artist)
        let artistParts = artist
            .components(separatedBy: CharacterSet(charactersIn: ",，/、·&+;；"))
            .map(canonicalMusicGenreKey)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let cleanedTags: [String] = tags.compactMap { rawTag in
            let trimmed = rawTag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
            guard URL(string: trimmed)?.scheme == nil else { return nil }

            let tag = canonicalMusicGenreTag(trimmed) ?? trimmed
            let key = canonicalMusicGenreKey(tag)
            guard !key.isEmpty else { return nil }
            guard key != titleKey, key != artistKey else { return nil }
            guard !artistParts.contains(key) else { return nil }
            guard isFeaturedMusicTag(tag) || !isNonGenreMusicTag(tag) else { return nil }
            guard seen.insert(key).inserted else { return nil }
            return tag
        }
        .sorted()

        let recognizedTags = cleanedTags.filter {
            !isFallbackMusicTag($0)
        }
        let genreTags = recognizedTags.filter {
            !isFeaturedMusicTag($0) && !isNonGenreMusicTag($0)
        }
        guard genreTags.isEmpty else { return recognizedTags }
        return (inferredMusicGenreTags(title: title, artist: artist, seedTags: tags) + recognizedTags)
            .deduplicatedMusicGenreTags()
            .sorted()
    }

    nonisolated static func isFallbackMusicTag(_ tag: String) -> Bool {
        let key = canonicalMusicGenreKey(tag)
        if key == canonicalMusicGenreKey(fallbackMusicTag) {
            return true
        }
        if key == canonicalMusicGenreKey(defaultMusicGenreTag) {
            return true
        }

        switch key {
        case "unknown",
            "unknown genre",
            "uncategorized",
            "unclassified",
            "未知",
            "未知流派",
            "未识别",
            "未识别流派",
            "未分类音乐",
            "无标签":
            return true
        default:
            return false
        }
    }

    nonisolated static func hasOnlyFallbackMusicTag(_ tags: [String]) -> Bool {
        let tagKeys = tags
            .filter { !isFeaturedMusicTag($0) }
            .map(canonicalMusicGenreKey)
            .filter { !$0.isEmpty }
        return !tagKeys.isEmpty && tagKeys.allSatisfy {
            isFallbackMusicTag($0)
        }
    }

    nonisolated static func hasOnlyDefaultMusicGenreTag(_ tags: [String]) -> Bool {
        let tagKeys = tags
            .filter { !isFeaturedMusicTag($0) }
            .map(canonicalMusicGenreKey)
            .filter { !$0.isEmpty }
        return tagKeys.count == 1 && tagKeys[0] == canonicalMusicGenreKey(defaultMusicGenreTag)
    }

    nonisolated static func isFeaturedMusicTag(_ tag: String) -> Bool {
        canonicalMusicGenreKey(tag) == canonicalMusicGenreKey(featuredMusicTag)
    }

    nonisolated static func isNonGenreMusicTag(_ tag: String) -> Bool {
        switch canonicalMusicGenreKey(tag) {
        case "export",
            "exported",
            "导出",
            "download",
            "downloads",
            "downloaded",
            "import",
            "imports",
            "music",
            "音乐",
            "song",
            "songs",
            "audio",
            "音频",
            "sound",
            "sound effect",
            "sound effects",
            "sfx",
            "original",
            "原曲",
            "instrumental",
            "accompaniment",
            "karaoke",
            "backing track",
            "伴奏":
            return true
        default:
            return false
        }
    }

    nonisolated static func canonicalMusicGenreTag(_ tag: String) -> String? {
        let key = canonicalMusicGenreKey(tag)
        let aliases: [String: String] = [
            "adult alternative": "Alternative",
            "alternative rock": "Alternative",
            "alternative": "Alternative",
            "ambient": "Ambient",
            "new age": "Ambient",
            "big band": "Jazz",
            "blues": "Blues",
            "cantopop": "Cantopop",
            "christian&gospel": "Christian & Gospel",
            "christian & gospel": "Christian & Gospel",
            "classical": "Classical",
            "classical crossover": "Classical",
            "country": "Country",
            "dance": "Dance",
            "disco": "Dance",
            "dubstep": "Electronic",
            "edm": "Electronic",
            "easy listening": "Ambient",
            "electronic": "Electronic",
            "electronica": "Electronic",
            "electropop": "Electronic",
            "house": "Electronic",
            "techno": "Electronic",
            "trance": "Electronic",
            "folk": "Folk",
            "hard rock": "Hard Rock",
            "heavy metal": "Metal",
            "hip hop": "Hip-Hop/Rap",
            "hip-hop": "Hip-Hop/Rap",
            "hip-hop/rap": "Hip-Hop/Rap",
            "hip-hop / rap": "Hip-Hop/Rap",
            "chinese hip-hop": "Hip-Hop/Rap",
            "rap": "Hip-Hop/Rap",
            "indie": "Indie",
            "indie pop": "Indie",
            "indie rock": "Indie",
            "j-pop": "J-Pop",
            "jazz": "Jazz",
            "k-pop": "K-Pop",
            "latin": "Latin",
            "latino": "Latin",
            "lo fi": "Lo-Fi",
            "lo-fi": "Lo-Fi",
            "lofi": "Lo-Fi",
            "mando pop": "Mandopop",
            "mandopop": "Mandopop",
            "metal": "Metal",
            "adult contemporary": "Pop",
            "pop": "Pop",
            "popular": "Pop",
            "punk": "Punk",
            "r&b/soul": "R&B/Soul",
            "r&b / soul": "R&B/Soul",
            "reggae": "Reggae",
            "classic rock": "Rock",
            "pop/rock": "Rock",
            "pop / rock": "Rock",
            "rock": "Rock",
            "rock & roll": "Rock",
            "rock&roll": "Rock",
            "rock and roll": "Rock",
            "score": "Soundtrack",
            "soundtrack": "Soundtrack",
            "ost": "Soundtrack",
            "film score": "Soundtrack",
            "anime": "Soundtrack",
            "background music": "Soundtrack",
            "bgm": "Soundtrack",
            "canto pop": "Cantopop",
            "电影": "Soundtrack",
            "电影原声": "Soundtrack",
            "动漫": "Soundtrack",
            "电子游戏": "Soundtrack",
            "古典": "Classical",
            "国语": "Mandopop",
            "国语流行": "Mandopop",
            "华语": "Mandopop",
            "华语流行": "Mandopop",
            "爵士": "Jazz",
            "蓝调": "Blues",
            "拉丁": "Latin",
            "流行": "Pop",
            "民谣": "Folk",
            "配乐": "Soundtrack",
            "朋克": "Punk",
            "雷鬼": "Reggae",
            "轻音乐": "Ambient",
            "世界音乐": "World",
            "说唱": "Hip-Hop/Rap",
            "嘻哈": "Hip-Hop/Rap",
            "乡村": "Country",
            "影视原声": "Soundtrack",
            "原声": "Soundtrack",
            "粤语": "Cantopop",
            "粤语流行": "Cantopop",
            "摇滚": "Rock",
            "硬摇滚": "Hard Rock",
            "重金属": "Metal",
            "电子": "Electronic",
            "电子乐": "Electronic",
            "电音": "Electronic",
            "舞曲": "Dance",
            "韩流": "K-Pop",
            "日系": "J-Pop",
            "singer/songwriter": "Singer/Songwriter",
            "singer / songwriter": "Singer/Songwriter",
            "soul": "R&B/Soul",
            "funk": "R&B/Soul",
            "world": "World",
            "arabic": "World"
        ]
        return aliases[key]
    }

    nonisolated static func inferredMusicGenreTags(
        title: String,
        artist: String = "",
        seedTags: [String] = []
    ) -> [String] {
        let searchableText = ([title, artist] + seedTags)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let key = canonicalMusicGenreKey(searchableText)

        let rules: [(genre: String, keywords: [String])] = [
            ("Hip-Hop/Rap", ["hip hop", "hip-hop", "rap", "trap", "drill", "phonk", "说唱", "嘻哈"]),
            ("Electronic", ["electronic", "electronica", "edm", "house", "techno", "trance", "dubstep", "synthwave", "future bass", "电子", "电子乐", "电音"]),
            ("Lo-Fi", ["lofi", "lo-fi", "lo fi"]),
            ("R&B/Soul", ["r&b", "soul", "funk", "节奏布鲁斯", "灵魂"]),
            ("Hard Rock", ["hard rock", "硬摇滚"]),
            ("Rock", ["rock", "摇滚"]),
            ("Metal", ["metal", "heavy metal", "金属", "重金属"]),
            ("Punk", ["punk", "朋克"]),
            ("Jazz", ["jazz", "爵士"]),
            ("Blues", ["blues", "蓝调"]),
            ("Classical", ["classical", "orchestra", "orchestral", "symphony", "piano", "古典", "钢琴", "交响"]),
            ("Ambient", ["ambient", "new age", "meditation", "relaxing", "calm", "氛围", "冥想", "轻音乐", "疗愈"]),
            ("Folk", ["folk", "acoustic", "民谣"]),
            ("Country", ["country", "乡村"]),
            ("Latin", ["latin", "latino", "拉丁"]),
            ("Reggae", ["reggae", "雷鬼"]),
            ("K-Pop", ["k-pop", "kpop", "韩流"]),
            ("J-Pop", ["j-pop", "jpop", "日系"]),
            ("Cantopop", ["cantopop", "canto pop", "粤语", "粤语流行"]),
            ("Mandopop", ["mandopop", "mando pop", "华语", "国语", "中文流行", "华语流行", "国语流行"]),
            ("Dance", ["dance", "disco", "舞曲"]),
            ("Pop", ["pop", "popular", "流行"])
        ]

        for rule in rules where rule.keywords.contains(where: { musicText(key, containsKeyword: $0) }) {
            return [rule.genre]
        }

        return []
    }

    private nonisolated static func musicText(_ textKey: String, containsKeyword rawKeyword: String) -> Bool {
        let keyword = canonicalMusicGenreKey(rawKeyword)
        guard !textKey.isEmpty, !keyword.isEmpty else { return false }

        let isPlainASCIIToken = keyword.range(
            of: #"^[a-z0-9]+$"#,
            options: .regularExpression
        ) != nil
        guard isPlainASCIIToken else {
            return textKey.contains(keyword)
        }

        let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = #"(^|[^a-z0-9])"# + escapedKeyword + #"([^a-z0-9]|$)"#
        return textKey.range(of: pattern, options: .regularExpression) != nil
    }

    nonisolated static func canonicalMusicGenreKey(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: #"\s*&\s*"#, with: "&", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    nonisolated var displayTags: [String] {
        Self.cleanedMusicTags(tags, title: title, artist: artist)
    }
}

private extension Array where Element == String {
    nonisolated func deduplicatedMusicGenreTags() -> [String] {
        var seen = Set<String>()
        return compactMap { tag in
            let key = MusicRecognitionItem.canonicalMusicGenreKey(tag)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return tag
        }
    }
}
