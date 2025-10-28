//
//  ArticleDocument.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation
import Combine
import SwiftUI

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
