//
//  AppViewModel.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var rootURL: URL
    @Published private(set) var fileTree: [FileNode] = []
    @Published var selectedNodeID: FileNode.ID? {
        didSet { loadSelectedArticle() }
    }
    @Published var articleDocument: ArticleDocument?
    @Published var loadError: String?
    @Published var searchText: String = ""
    @Published var contentFontSize: Double = 20
    @Published var reviewStates: [URL: ReviewState] = [:]
    @Published var validationIssues: [ValidationIssue] = []
    @Published var lastReplacementCount: Int?
    @Published private(set) var typoCorrections: [TypoCorrection] = []

    private static let lastRootBookmarkKey = "LastSelectedRootBookmarkData"
    private static let lastRootPathKey = "LastSelectedRootPath"
    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private var securityScopedRootURL: URL?
    private let typoCorrectionsURL: URL
    private var isLoadingTypoCorrections = false

    deinit {
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
    }

    init(defaultRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.rootURL = defaultRoot
        self.typoCorrectionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".subtitle_correct_typos.json", isDirectory: false)
        loadTypoCorrections()
        configureInitialRoot(fallback: defaultRoot)
        refreshTree()
    }

    private func configureInitialRoot(fallback: URL) {
        if let restoredURL = restorePersistedRootURL() {
            if prepareRootAccess(for: restoredURL) {
                rootURL = restoredURL
                persistRootBookmark(for: restoredURL) // Refresh stale bookmarks when necessary
                loadError = nil
                return
            } else {
                loadError = "无法访问上次使用的目录，请重新选择。"
                clearPersistedRoot()
            }
        }

        if !prepareRootAccess(for: fallback) {
            loadError = "无法访问默认目录，请选择其他文件夹。"
        }
    }

    private func restorePersistedRootURL() -> URL? {
        if let bookmarkData = userDefaults.data(forKey: Self.lastRootBookmarkKey) {
            var isStale = false
            do {
                let resolved = try URL(resolvingBookmarkData: bookmarkData,
                                       options: [.withSecurityScope],
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale)
                if fileManager.fileExists(atPath: resolved.path) {
                    return resolved
                } else {
                    clearPersistedRoot()
                }
            } catch {
                print("[RootBookmark] Failed to resolve bookmark: \(error)")
                clearPersistedRoot()
            }
        }

        if let storedPath = userDefaults.string(forKey: Self.lastRootPathKey) {
            let url = URL(fileURLWithPath: storedPath, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            } else {
                clearPersistedRoot()
            }
        }

        return nil
    }

    @discardableResult
    private func prepareRootAccess(for url: URL) -> Bool {
        securityScopedRootURL = nil
        if url.startAccessingSecurityScopedResource() {
            securityScopedRootURL = url
            return true
        }
        if fileManager.isReadableFile(atPath: url.path) {
            return true
        }
        return false
    }

    private func persistRootBookmark(for url: URL) {
        guard url.isFileURL else { return }

        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            userDefaults.set(data, forKey: Self.lastRootBookmarkKey)
        } catch {
            print("[RootBookmark] Failed to store bookmark: \(error)")
            userDefaults.removeObject(forKey: Self.lastRootBookmarkKey)
        }

        userDefaults.set(url.path, forKey: Self.lastRootPathKey)
    }

    private func clearPersistedRoot() {
        userDefaults.removeObject(forKey: Self.lastRootBookmarkKey)
        userDefaults.removeObject(forKey: Self.lastRootPathKey)
    }

    func refreshTree() {
        Task { @MainActor in
            let tree = buildTree(for: rootURL)
            fileTree = tree
            if let articleURL = articleDocument?.url, let node = node(for: articleURL, within: tree) {
                selectedNodeID = node.id
            } else if selectedNodeID == nil, let first = firstFileNode(in: tree) {
                selectedNodeID = first.id
            }
        }
    }

    func selectFolder(at url: URL) {
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
        securityScopedRootURL = nil

        guard prepareRootAccess(for: url) else {
            loadError = "无法访问所选文件夹，请检查权限。"
            clearPersistedRoot()
            return
        }
        rootURL = url
        persistRootBookmark(for: url)
        loadError = nil
        lastReplacementCount = nil
        refreshTree()
    }

    func saveChanges() {
        guard let document = articleDocument else { return }
        do {
            // 将当前 ReviewState 写入文档模型
            let state = reviewStates[document.url] ?? .notStarted
            document.article.reviewState = state.rawValue
            // 记录矫正时间（ISO8601）
            let iso = ISO8601DateFormatter()
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            document.article.reviewedAt = iso.string(from: Date())

            try document.save()

            // 如果之前是未开始，保存后至少标记为进行中（与 UI 状态保持一致）
            if state == .notStarted {
                reviewStates[document.url] = .inProgress
            }
        } catch {
            loadError = "保存失败：\(error.localizedDescription)"
        }
    }

    func markReviewed(_ state: ReviewState) {
        guard let url = articleDocument?.url else { return }
        reviewStates[url] = state
        articleDocument?.article.reviewState = state.rawValue
        let iso = ISO8601DateFormatter(); iso.timeZone = TimeZone(secondsFromGMT: 0)
        articleDocument?.article.reviewedAt = iso.string(from: Date())
    }

    func runValidation() {
        guard let document = articleDocument else {
            validationIssues = []
            return
        }

        let article = document.article
        var issues: [ValidationIssue] = []

        let timestampPattern = try? NSRegularExpression(pattern: "^\\d{2}:\\d{2}:\\d{2}$")
        var previousComponents: DateComponents?

        let calendar = Calendar(identifier: .gregorian)

        for entry in article.content {
            if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ValidationIssue(message: "时间 \(entry.timestample) 的文本为空", severity: .error, suggestion: "填写字幕文本"))
            }

            if timestampPattern?.firstMatch(in: entry.timestample, options: [], range: NSRange(location: 0, length: entry.timestample.count)) == nil {
                issues.append(ValidationIssue(message: "\(entry.timestample) 不是有效的时间戳", severity: .error, suggestion: "使用 00:00:00 格式"))
            }

            if let previous = previousComponents,
               let previousDate = calendar.date(from: previous),
               let current = components(from: entry.timestample),
               let currentDate = calendar.date(from: current) {
                if currentDate < previousDate {
                    issues.append(ValidationIssue(message: "时间 \(entry.timestample) 早于上一条字幕", severity: .warning, suggestion: "检查排序"))
                }
            }

            previousComponents = components(from: entry.timestample)
        }

        if (article.duration != nil) {
            issues.append(ValidationIssue(message: "缺少 duration 字段", severity: .warning, suggestion: "补充视频时长"))
        }
        if (article.title?.isEmpty ?? true) {
            issues.append(ValidationIssue(message: "缺少标题", severity: .warning, suggestion: "填写 title"))
        }
        if (article.url?.isEmpty ?? true) {
            issues.append(ValidationIssue(message: "缺少视频 URL", severity: .warning, suggestion: "填写 url"))
        }

        validationIssues = issues
    }

    private func loadSelectedArticle() {
        guard let selectedID = selectedNodeID, let node = node(for: selectedID, within: fileTree), !node.isDirectory else {
            articleDocument = nil
            return
        }

        do {
            let data = try Data(contentsOf: node.url)
            let decoder = JSONDecoder()
            let article = try decoder.decode(Article.self, from: data)
            articleDocument = ArticleDocument(article: article, url: node.url)
            // 从文件中恢复已保存的 reviewState（如果存在）
            if let savedState = article.reviewState, let parsed = ReviewState(rawValue: savedState) {
                reviewStates[node.url] = parsed
            }
            loadError = nil
            validationIssues = []
            lastReplacementCount = nil
        } catch let DecodingError.keyNotFound(key, context) {
            articleDocument = nil
            let path = (context.codingPath.map { $0.stringValue }).joined(separator: ".")
            loadError = "无法加载 JSON：缺少必需字段 ‘\(key.stringValue)’。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.typeMismatch(type, context) {
            articleDocument = nil
            let path = (context.codingPath.map { $0.stringValue }).joined(separator: ".")
            loadError = "无法加载 JSON：字段类型不匹配（期望 \(type)）。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.valueNotFound(type, context) {
            articleDocument = nil
            let path = (context.codingPath.map { $0.stringValue }).joined(separator: ".")
            loadError = "无法加载 JSON：必需值缺失（\(type)）。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.dataCorrupted(context) {
            articleDocument = nil
            loadError = "无法加载 JSON：数据损坏。\(context.debugDescription)"
            lastReplacementCount = nil
        } catch {
            articleDocument = nil
            loadError = "无法加载 JSON：\(error.localizedDescription)"
            lastReplacementCount = nil
        }
    }

    private func buildTree(for root: URL) -> [FileNode] {
        guard let node = makeNode(for: root) else { return [] }
        if node.isDirectory {
            return node.children ?? []
        } else {
            return [node]
        }
    }

    private func makeNode(for url: URL) -> FileNode? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            guard let childrenURLs = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return nil
            }
            var childNodes: [FileNode] = []
            for child in childrenURLs.sorted(by: fileSort) {
                if let node = makeNode(for: child) {
                    childNodes.append(node)
                }
            }
            if childNodes.isEmpty {
                return nil
            }
            return FileNode(url: url, isDirectory: true, children: childNodes)
        } else if url.pathExtension.lowercased() == "json" {
            return FileNode(url: url, isDirectory: false)
        } else {
            return nil
        }
    }

    private func fileSort(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if lhsIsDir != rhsIsDir {
            return lhsIsDir && !rhsIsDir
        }
        return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
    }

    private func node(for url: URL, within nodes: [FileNode]) -> FileNode? {
        for candidate in nodes {
            if candidate.url == url {
                return candidate
            }
            if let child = node(for: url, within: candidate.children ?? []) {
                return child
            }
        }
        return nil
    }

    private func node(for id: FileNode.ID, within nodes: [FileNode]) -> FileNode? {
        for candidate in nodes {
            if candidate.id == id {
                return candidate
            }
            if let child = node(for: id, within: candidate.children ?? []) {
                return child
            }
        }
        return nil
    }

    private func firstFileNode(in nodes: [FileNode]) -> FileNode? {
        for candidate in nodes {
            if candidate.isDirectory {
                if let child = firstFileNode(in: candidate.children ?? []) {
                    return child
                }
            } else {
                return candidate
            }
        }
        return nil
    }

    var selectedNode: FileNode? {
        guard let id = selectedNodeID else { return nil }
        return node(for: id, within: fileTree)
    }

    private func components(from timestamp: String) -> DateComponents? {
        let parts = timestamp.split(separator: ":")
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components
    }

    func updateTypoCorrections(with newCorrections: [TypoCorrection]) {
        let sanitized = sanitizeTypoCorrections(newCorrections)
        isLoadingTypoCorrections = true
        typoCorrections = sanitized
        isLoadingTypoCorrections = false
        saveTypoCorrections()
        lastReplacementCount = nil
    }

    func replaceTyposInContent() {
        guard let document = articleDocument else {
            lastReplacementCount = nil
            return
        }
        let corrections = typoCorrections
        guard !corrections.isEmpty else {
            lastReplacementCount = 0
            return
        }

        var workingArticle = document.article
        var totalReplacements = 0

        for index in workingArticle.content.indices {
            var text = workingArticle.content[index].text
            for correction in corrections {
                let target = correction.source
                guard !target.isEmpty else { continue }
                let segments = text.components(separatedBy: target)
                if segments.count > 1 {
                    totalReplacements += segments.count - 1
                    text = segments.joined(separator: correction.replacement)
                }
            }
            workingArticle.content[index].text = text
        }

        document.article = workingArticle
        lastReplacementCount = totalReplacements
    }

    func resetTypoCorrections() {
        updateTypoCorrections(with: [])
    }

    func addTypoCorrection(source: String, replacement: String) {
        var current = typoCorrections
        current.append(TypoCorrection(source: source, replacement: replacement))
        updateTypoCorrections(with: current)
    }

    var typoCorrectionsFilePath: String {
        typoCorrectionsURL.path
    }

    private func loadTypoCorrections() {
        isLoadingTypoCorrections = true
        defer { isLoadingTypoCorrections = false }

        let fm = FileManager.default
        if !fm.fileExists(atPath: typoCorrectionsURL.path) {
            do {
                try Data("[]".utf8).write(to: typoCorrectionsURL, options: [.atomic])
            } catch {
                print("[TypoCorrections] Failed to create storage: \(error)")
            }
            typoCorrections = []
            return
        }

        do {
            let data = try Data(contentsOf: typoCorrectionsURL)
            guard !data.isEmpty else {
                typoCorrections = []
                return
            }
            let decoded = try JSONDecoder().decode([TypoCorrection].self, from: data)
            typoCorrections = sanitizeTypoCorrections(decoded)
        } catch {
            print("[TypoCorrections] Failed to load: \(error)")
            typoCorrections = []
        }
    }

    private func saveTypoCorrections() {
        guard !isLoadingTypoCorrections else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(typoCorrections)
            try data.write(to: typoCorrectionsURL, options: [.atomic])
        } catch {
            print("[TypoCorrections] Failed to save: \(error)")
        }
    }

    private func sanitizeTypoCorrections(_ corrections: [TypoCorrection]) -> [TypoCorrection] {
        var unique: [String: TypoCorrection] = [:]

        for item in corrections {
            let trimmedSource = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedReplacement = item.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSource.isEmpty, !trimmedReplacement.isEmpty else { continue }

            var sanitized = item
            sanitized.source = trimmedSource
            sanitized.replacement = trimmedReplacement

            if let existing = unique[trimmedSource] {
                var updated = existing
                updated.replacement = sanitized.replacement
                unique[trimmedSource] = updated
            } else {
                unique[trimmedSource] = sanitized
            }
        }

        let sorted = unique.values.sorted { lhs, rhs in
            lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
        }
        return sorted
    }
}

extension AppViewModel {
    enum ReviewState: String, CaseIterable, Identifiable {
        case notStarted
        case inProgress
        case completed

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .notStarted: return "未开始"
            case .inProgress: return "进行中"
            case .completed: return "已完成"
            }
        }

        var iconName: String {
            switch self {
            case .notStarted: return "circle"
            case .inProgress: return "clock"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }
}

@MainActor
final class ArticleDocument: ObservableObject {
    @Published var article: Article {
        didSet {
            hasUnsavedChanges = article != originalArticle
        }
    }
    private var originalArticle: Article
    let url: URL
    @Published private(set) var hasUnsavedChanges: Bool = false

    init(article: Article, url: URL) {
        self.article = article
        self.originalArticle = article
        self.url = url
    }

    func addContentEntry() {
        article.content.append(ArticleContent(timestample: "00:00:00", text: ""))
    }

    func removeContentEntry(_ entry: ArticleContent) {
        article.content.removeAll { $0.id == entry.id }
    }

    func updateAuthor(at index: Int, with newValue: String) {
        if index < article.authors.count {
            article.authors[index] = newValue
        }
    }

    func addAuthor() {
        article.authors.append("")
    }

    func removeAuthor(at index: Int) {
        guard article.authors.indices.contains(index) else { return }
        article.authors.remove(at: index)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(article)
        try data.write(to: url, options: [.atomic])
        originalArticle = article
        hasUnsavedChanges = false
    }

    func revertChanges() {
        article = originalArticle
        hasUnsavedChanges = false
    }

}
