//
//  Models.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

struct FileNode: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    init(id: UUID = UUID(), url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = id
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    var name: String { url.lastPathComponent }
}

typealias ArticleID = UUID

struct Article: Codable, Equatable, Identifiable {
    var id: ArticleID = UUID()
    var duration: Int?
    var previewImageURL: String?
    var description: String?
    var prepareDate: String?
    var creationDate: String?
    var height: Int?
    var title: String?
    var type: String?
    var width: Int?
    var resolution: String?
    var version: String?
    var authors: [String] = []
    var bitrate: Int?
    var url: String?
    var uploadDate: String?
    var content: [ArticleContent] = []
    var correctedAt: String?

    /// 矫正/校对状态（与 AppViewModel.ReviewState.rawValue 对应：notStarted/inProgress/completed）
    var reviewState: String?

    /// 上次矫正时间，ISO8601 字符串（例如 2025-10-02T12:34:56Z）
    var reviewedAt: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case previewImageURL
        case description
        case prepareDate
        case creationDate
        case height
        case title
        case type = "__type"
        case width
        case resolution
        case version = "__version"
        case authors
        case bitrate
        case url
        case uploadDate
        case content
        case correctedAt
        case reviewState
        case reviewedAt
    }

    init(duration: Int? = nil,
         previewImageURL: String? = nil,
         description: String? = nil,
         prepareDate: String? = nil,
         creationDate: String? = nil,
         height: Int? = nil,
         title: String? = nil,
         type: String? = nil,
         width: Int? = nil,
         resolution: String? = nil,
         version: String? = nil,
         authors: [String] = [],
         bitrate: Int? = nil,
         url: String? = nil,
         uploadDate: String? = nil,
         content: [ArticleContent] = [],
         correctedAt: String? = nil,
         reviewState: String? = nil,
         reviewedAt: String? = nil) {
        self.duration = duration
        self.previewImageURL = previewImageURL
        self.description = description
        self.prepareDate = prepareDate
        self.creationDate = creationDate
        self.height = height
        self.title = title
        self.type = type
        self.width = width
        self.resolution = resolution
        self.version = version
        self.authors = authors
        self.bitrate = bitrate
        self.url = url
        self.uploadDate = uploadDate
        self.content = content
        self.correctedAt = correctedAt
        self.reviewState = reviewState
        self.reviewedAt = reviewedAt
    }
}

struct ArticleContent: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var timestample: String
    var text: String
    /// Optional important flag; encoded only when true so legacy files stay unchanged.
    var important: Bool?

    init(id: UUID = UUID(), timestample: String, text: String, important: Bool? = nil) {
        self.id = id
        self.timestample = timestample
        self.text = text
        self.important = important
    }

    enum CodingKeys: String, CodingKey {
        case timestample
        case text
        case important
    }
}

struct ValidationIssue: Identifiable, Hashable {
    enum Severity: String {
        case warning
        case error
    }

    let id = UUID()
    let message: String
    let severity: Severity
    let suggestion: String?
}

struct TypoCorrection: Identifiable, Codable, Equatable {
    var id: UUID
    var source: String
    var replacement: String

    init(id: UUID = UUID(), source: String, replacement: String) {
        self.id = id
        self.source = source
        self.replacement = replacement
    }
}
