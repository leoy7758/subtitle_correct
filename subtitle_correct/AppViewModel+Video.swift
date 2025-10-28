//
//  AppViewModel+Video.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation
import AVFoundation

extension AppViewModel {
    func configureInitialVideoRoot() {
        guard let restoredURL = restorePersistedVideoRootURL() else { return }
        if prepareVideoRootAccess(for: restoredURL) {
            videoRootURL = restoredURL
            persistVideoRootBookmark(for: restoredURL)
        } else {
            clearPersistedVideoRoot()
        }
    }

    @discardableResult
    func prepareVideoRootAccess(for url: URL) -> Bool {
        securityScopedVideoRootURL = nil
        if url.startAccessingSecurityScopedResource() {
            securityScopedVideoRootURL = url
            return true
        }
        if fileManager.isReadableFile(atPath: url.path) {
            return true
        }
        return false
    }

    func persistVideoRootBookmark(for url: URL) {
        guard url.isFileURL else { return }

        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            userDefaults.set(data, forKey: Self.lastVideoBookmarkKey)
        } catch {
            print("[VideoRootBookmark] Failed to store: \(error)")
            userDefaults.removeObject(forKey: Self.lastVideoBookmarkKey)
        }

        userDefaults.set(url.path, forKey: Self.lastVideoPathKey)
    }

    func clearPersistedVideoRoot() {
        userDefaults.removeObject(forKey: Self.lastVideoBookmarkKey)
        userDefaults.removeObject(forKey: Self.lastVideoPathKey)
        securityScopedVideoRootURL?.stopAccessingSecurityScopedResource()
        securityScopedVideoRootURL = nil
        videoRootURL = nil
        applyVideoSelection(nil)
    }

    func restorePersistedVideoRootURL() -> URL? {
        if let bookmarkData = userDefaults.data(forKey: Self.lastVideoBookmarkKey) {
            var isStale = false
            do {
                let resolved = try URL(resolvingBookmarkData: bookmarkData,
                                       options: [.withSecurityScope],
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale)
                if fileManager.fileExists(atPath: resolved.path) {
                    return resolved
                } else {
                    clearPersistedVideoRoot()
                }
            } catch {
                print("[VideoRootBookmark] Failed to resolve: \(error)")
                clearPersistedVideoRoot()
            }
        }

        if let storedPath = userDefaults.string(forKey: Self.lastVideoPathKey) {
            let url = URL(fileURLWithPath: storedPath, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                return url
            } else {
                clearPersistedVideoRoot()
            }
        }

        return nil
    }

    func loadMatchingVideo(for subtitleURL: URL) {
        videoLookupTask?.cancel()

        guard let videoRootURL else {
            applyVideoSelection(nil)
            return
        }

        let baseName = subtitleURL.deletingPathExtension().lastPathComponent
        videoLookupTask = Task { [weak self] in
            guard let self else { return }
            let matchedURL = await self.lookupVideo(named: baseName, under: videoRootURL)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.applyVideoSelection(matchedURL)
            }
        }
    }

    func lookupVideo(named baseName: String, under root: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let targetName = baseName + ".mp4"
                let enumerator = fm.enumerator(at: root,
                                               includingPropertiesForKeys: [.isDirectoryKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let next = enumerator?.nextObject() as? URL {
                    if next.lastPathComponent.compare(targetName, options: .caseInsensitive) == .orderedSame {
                        var isDirectory: ObjCBool = false
                        if fm.fileExists(atPath: next.path, isDirectory: &isDirectory),
                           !isDirectory.boolValue {
                            continuation.resume(returning: next)
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    @MainActor
    func applyVideoSelection(_ url: URL?) {
        if currentVideoURL == url {
            return
        }

        setCurrentVideoURL(url)

        if let url {
            let player = AVPlayer(url: url)
            player.seek(to: .zero)
            setVideoPlayer(player)
        } else {
            videoPlayer?.pause()
            setVideoPlayer(nil)
        }
    }

    func playVideo(at timestamp: String) {
        guard let player = videoPlayer,
              let seconds = seconds(fromTimestamp: timestamp) else { return }

        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.2, preferredTimescale: 600)

        player.seek(to: target,
                    toleranceBefore: tolerance,
                    toleranceAfter: tolerance) { finished in
            guard finished else { return }
            player.play()
            player.rate = self.playbackRate
        }
    }

    @discardableResult
    func adjustPlaybackRate(by delta: Float) -> Float {
        let raw = playbackRate + delta
        let clamped = max(0.1, min(3.0, raw))
        let rounded = Float((Double(clamped) * 10).rounded() / 10.0)
        if abs(rounded - playbackRate) > 0.0001 {
            setPlaybackRate(rounded)
            applyCurrentPlaybackRate()
        }
        return playbackRate
    }

    func applyCurrentPlaybackRate() {
        guard let player = videoPlayer else { return }
        player.rate = playbackRate
    }
}
