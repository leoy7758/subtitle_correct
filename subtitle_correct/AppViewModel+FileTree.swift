//
//  AppViewModel+FileTree.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

extension AppViewModel {
    func configureInitialRoot(fallback: URL) {
        if let restoredURL = restorePersistedRootURL() {
            if prepareRootAccess(for: restoredURL) {
                rootURL = restoredURL
                persistRootBookmark(for: restoredURL)
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

    func restorePersistedRootURL() -> URL? {
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
    func prepareRootAccess(for url: URL) -> Bool {
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

    func persistRootBookmark(for url: URL) {
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

    func clearPersistedRoot() {
        userDefaults.removeObject(forKey: Self.lastRootBookmarkKey)
        userDefaults.removeObject(forKey: Self.lastRootPathKey)
    }

    func node(for url: URL, within nodes: [FileNode]) -> FileNode? {
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

    func node(for id: FileNode.ID, within nodes: [FileNode]) -> FileNode? {
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

    func firstFileNode(in nodes: [FileNode]) -> FileNode? {
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

    func buildTree(for root: URL) -> [FileNode] {
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
            guard let childrenURLs = try? fileManager.contentsOfDirectory(at: url,
                                                                          includingPropertiesForKeys: [.isDirectoryKey],
                                                                          options: [.skipsHiddenFiles]) else {
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

    func loadReviewStates(for nodes: [FileNode]) -> [URL: ReviewState] {
        var result: [URL: ReviewState] = [:]
        var stack = nodes

        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children ?? [])
                continue
            }

            if let state = reviewState(for: node.url) {
                result[node.url] = state
            }
        }

        return result
    }

    func reviewState(for url: URL) -> ReviewState? {
        guard url.pathExtension.lowercased() == "json" else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(ReviewStateEnvelope.self, from: data)
            if let value = envelope.reviewState,
               let state = ReviewState(rawValue: value) {
                return state
            }
        } catch {
            return nil
        }

        return nil
    }
}
