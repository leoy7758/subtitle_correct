//
//  AppViewModel+Article.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import Foundation

extension AppViewModel {
    func loadSelectedArticle() {
        guard let selectedID = selectedNodeID,
              let node = node(for: selectedID, within: fileTree),
              !node.isDirectory else {
            articleDocument = nil
            applyVideoSelection(nil)
            return
        }

        do {
            let data = try Data(contentsOf: node.url)
            let decoder = JSONDecoder()
            let article = try decoder.decode(Article.self, from: data)

            articleDocument = ArticleDocument(article: article, url: node.url)

            if let savedState = article.reviewState,
               let parsed = ReviewState(rawValue: savedState) {
                reviewStates[node.url] = parsed
            }

            loadError = nil
            validationIssues = []
            lastReplacementCount = nil
            loadMatchingVideo(for: node.url)
        } catch let DecodingError.keyNotFound(key, context) {
            articleDocument = nil
            applyVideoSelection(nil)
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            loadError = "无法加载 JSON：缺少必需字段 ‘\(key.stringValue)’。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.typeMismatch(type, context) {
            articleDocument = nil
            applyVideoSelection(nil)
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            loadError = "无法加载 JSON：字段类型不匹配（期望 \(type)）。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.valueNotFound(type, context) {
            articleDocument = nil
            applyVideoSelection(nil)
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            loadError = "无法加载 JSON：必需值缺失（\(type)）。路径：\(path)。"
            lastReplacementCount = nil
        } catch let DecodingError.dataCorrupted(context) {
            articleDocument = nil
            applyVideoSelection(nil)
            loadError = "无法加载 JSON：数据损坏。\(context.debugDescription)"
            lastReplacementCount = nil
        } catch {
            articleDocument = nil
            applyVideoSelection(nil)
            loadError = "无法加载 JSON：\(error.localizedDescription)"
            lastReplacementCount = nil
        }
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
                issues.append(ValidationIssue(message: "时间 \(entry.timestample) 的文本为空",
                                              severity: .error,
                                              suggestion: "填写字幕文本"))
            }

            if timestampPattern?.firstMatch(in: entry.timestample,
                                            options: [],
                                            range: NSRange(location: 0, length: entry.timestample.count)) == nil {
                issues.append(ValidationIssue(message: "\(entry.timestample) 不是有效的时间戳",
                                              severity: .error,
                                              suggestion: "使用 00:00:00 格式"))
            }

            if let previous = previousComponents,
               let previousDate = calendar.date(from: previous),
               let current = components(from: entry.timestample),
               let currentDate = calendar.date(from: current),
               currentDate < previousDate {
                issues.append(ValidationIssue(message: "时间 \(entry.timestample) 早于上一条字幕",
                                              severity: .warning,
                                              suggestion: "检查排序"))
            }

            previousComponents = components(from: entry.timestample)
        }

        if article.duration != nil {
            issues.append(ValidationIssue(message: "缺少 duration 字段",
                                          severity: .warning,
                                          suggestion: "补充视频时长"))
        }
        if article.title?.isEmpty ?? true {
            issues.append(ValidationIssue(message: "缺少标题",
                                          severity: .warning,
                                          suggestion: "填写 title"))
        }
        if article.url?.isEmpty ?? true {
            issues.append(ValidationIssue(message: "缺少视频 URL",
                                          severity: .warning,
                                          suggestion: "填写 url"))
        }

        validationIssues = issues
    }
}
