//
//  AppViewModel+TypoCorrections.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

extension AppViewModel {
    func updateTypoCorrections(with newCorrections: [TypoCorrection]) {
        let sanitized = sanitizeTypoCorrections(newCorrections)
        isLoadingTypoCorrections = true
        setTypoCorrections(sanitized)
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

    func loadTypoCorrections() {
        isLoadingTypoCorrections = true
        defer { isLoadingTypoCorrections = false }

        let fm = FileManager.default
        if !fm.fileExists(atPath: typoCorrectionsURL.path) {
            do {
                try Data("[]".utf8).write(to: typoCorrectionsURL, options: [.atomic])
            } catch {
                print("[TypoCorrections] Failed to create storage: \(error)")
            }
            setTypoCorrections([])
            return
        }

        do {
            let data = try Data(contentsOf: typoCorrectionsURL)
            guard !data.isEmpty else {
                setTypoCorrections([])
                return
            }
            let decoded = try JSONDecoder().decode([TypoCorrection].self, from: data)
            setTypoCorrections(sanitizeTypoCorrections(decoded))
        } catch {
            print("[TypoCorrections] Failed to load: \(error)")
            setTypoCorrections([])
        }
    }

    func saveTypoCorrections() {
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

    func sanitizeTypoCorrections(_ corrections: [TypoCorrection]) -> [TypoCorrection] {
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

        let sorted = unique.values.sorted {
            $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending
        }
        return sorted
    }
}
