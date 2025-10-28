//
//  AppViewModel.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Published State

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
    @Published var videoRootURL: URL?
    @Published private(set) var currentVideoURL: URL?
    @Published private(set) var videoPlayer: AVPlayer?
    @Published private(set) var playbackRate: Float = 1.2

    // MARK: - Persistence Keys

    static let lastRootBookmarkKey = "LastSelectedRootBookmarkData"
    static let lastRootPathKey = "LastSelectedRootPath"
    static let lastVideoBookmarkKey = "LastSelectedVideoBookmarkData"
    static let lastVideoPathKey = "LastSelectedVideoPath"

    // MARK: - Dependencies & State

    let userDefaults = UserDefaults.standard
    let fileManager = FileManager.default
    var securityScopedRootURL: URL?
    var securityScopedVideoRootURL: URL?
    let typoCorrectionsURL: URL
    var isLoadingTypoCorrections = false
    var videoLookupTask: Task<Void, Never>?

    func setTypoCorrections(_ corrections: [TypoCorrection]) {
        typoCorrections = corrections
    }

    func setCurrentVideoURL(_ url: URL?) {
        currentVideoURL = url
    }

    func setVideoPlayer(_ player: AVPlayer?) {
        videoPlayer = player
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }

    // MARK: - Lifecycle

    deinit {
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
        securityScopedVideoRootURL?.stopAccessingSecurityScopedResource()
        videoLookupTask?.cancel()
    }

    init(defaultRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.rootURL = defaultRoot
        self.typoCorrectionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".subtitle_correct_typos.json", isDirectory: false)

        loadTypoCorrections()
        configureInitialRoot(fallback: defaultRoot)
        configureInitialVideoRoot()
        refreshTree()
    }

    // MARK: - Public Interface

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

    func selectVideoFolder(at url: URL) {
        securityScopedVideoRootURL?.stopAccessingSecurityScopedResource()
        securityScopedVideoRootURL = nil

        guard prepareVideoRootAccess(for: url) else {
            loadError = "无法访问所选视频文件夹，请检查权限。"
            clearPersistedVideoRoot()
            return
        }

        videoRootURL = url
        persistVideoRootBookmark(for: url)

        if let currentArticleURL = articleDocument?.url {
            loadMatchingVideo(for: currentArticleURL)
        }
    }

    func refreshTree() {
        Task { @MainActor in
            let tree = buildTree(for: rootURL)
            let hydratedStates = loadReviewStates(for: tree)

            fileTree = tree

            for (url, state) in hydratedStates {
                if let currentDocument = articleDocument,
                   currentDocument.url == url,
                   currentDocument.hasUnsavedChanges {
                    continue
                }
                reviewStates[url] = state
            }

            if let articleURL = articleDocument?.url,
               let node = node(for: articleURL, within: tree) {
                selectedNodeID = node.id
            } else if selectedNodeID == nil,
                      let first = firstFileNode(in: tree) {
                selectedNodeID = first.id
            }
        }
    }

    func deleteFileNode(_ node: FileNode) {
        guard !node.isDirectory else { return }

        if articleDocument?.url == node.url {
            articleDocument = nil
        }
        if selectedNodeID == node.id {
            selectedNodeID = nil
        }

        reviewStates.removeValue(forKey: node.url)
        validationIssues = []
        lastReplacementCount = nil

        do {
            try fileManager.removeItem(at: node.url)
            refreshTree()
        } catch {
            loadError = "删除失败：\(error.localizedDescription)"
        }
    }

    func saveChanges() {
        guard let document = articleDocument else { return }

        do {
            let state = reviewStates[document.url] ?? .notStarted
            document.article.reviewState = state.rawValue

            let iso = ISO8601DateFormatter()
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            document.article.reviewedAt = iso.string(from: Date())

            try document.save()

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

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        articleDocument?.article.reviewedAt = iso.string(from: Date())
    }
}
