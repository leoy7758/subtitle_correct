//
//  ContentView.swift
//  subtitle_correct
//
//  Created by Codex on behalf of Leo Y.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel: AppViewModel
    @State private var isShowingFolderImporter = false
    @State private var isShowingRevertAlert = false

    init() {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let suggested = cwd.appendingPathComponent("articles")
        if fm.fileExists(atPath: suggested.path) {
            _viewModel = StateObject(wrappedValue: AppViewModel(defaultRoot: suggested))
        } else {
            _viewModel = StateObject(wrappedValue: AppViewModel(defaultRoot: cwd))
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel,
                        onSelectFolder: { isShowingFolderImporter = true })
        } detail: {
            DetailView(viewModel: viewModel,
                       onRequestFolderPicker: { isShowingFolderImporter = true },
                       onRequestRevert: { isShowingRevertAlert = true })
                .alert("放弃未保存的更改？", isPresented: $isShowingRevertAlert) {
                    Button("保留", role: .cancel) {}
                    Button("放弃更改", role: .destructive) {
                        viewModel.articleDocument?.revertChanges()
                    }
                } message: {
                    Text("此操作会恢复到上一次保存的内容。")
                }
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(isPresented: $isShowingFolderImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.selectFolder(at: url)
                }
            case .failure(let error):
                viewModel.loadError = "无法打开文件夹：\(error.localizedDescription)"
            }
        }
        .alert("错误", isPresented: Binding<Bool>(
            get: { viewModel.loadError != nil },
            set: { isPresented in
                if !isPresented { viewModel.loadError = nil }
            }
        )) {
            Button("确定", role: .cancel) { viewModel.loadError = nil }
        } message: {
            Text(viewModel.loadError ?? "未知错误")
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    var onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.rootURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    onSelectFolder()
                } label: {
                    Label("选择文件夹", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("切换待审文件夹")
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List(selection: Binding(
                get: { viewModel.selectedNodeID },
                set: { viewModel.selectedNodeID = $0 }
            )) {
                OutlineGroup(viewModel.fileTree, children: \.children) { node in
                    FileNodeRow(node: node,
                                isSelected: viewModel.selectedNode?.id == node.id,
                                reviewState: viewModel.reviewStates[node.url] ?? .notStarted,
                                hasUnsavedChanges: viewModel.articleDocument?.url == node.url && (viewModel.articleDocument?.hasUnsavedChanges ?? false))
                    .tag(node.id)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let isSelected: Bool
    let reviewState: AppViewModel.ReviewState
    let hasUnsavedChanges: Bool

    var body: some View {
        HStack {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(node.isDirectory ? .secondary : .primary)
            Text(node.name)
            Spacer()
            if hasUnsavedChanges {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                    .help("存在未保存的修改")
            } else if !node.isDirectory {
                Image(systemName: reviewState.iconName)
                    .foregroundStyle(reviewState == .completed ? .green : (reviewState == .inProgress ? .yellow : .secondary))
                    .help(reviewState.displayName)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct DetailView: View {
    @ObservedObject var viewModel: AppViewModel
    var onRequestFolderPicker: () -> Void
    var onRequestRevert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let document = viewModel.articleDocument {
                ArticleEditorView(document: document,
                                  viewModel: viewModel,
                                  onSelectFolder: onRequestFolderPicker,
                                  onRevertRequested: onRequestRevert)
            } else if (viewModel.selectedNode?.isDirectory ?? false) {
                PlaceholderView(title: "请选择一个 JSON 文件",
                                 subtitle: "左侧树形结构中选择要核对的字幕文件。")
            } else if viewModel.selectedNodeID != nil {
                PlaceholderView(title: "暂无法展示",
                                 subtitle: "请选择有效的 JSON 文件。")
            } else {
                PlaceholderView(title: "准备开始",
                                 subtitle: "从左侧选择或上方按钮切换工作目录。")
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArticleEditorView: View {
    @ObservedObject var document: ArticleDocument
    @ObservedObject var viewModel: AppViewModel
    var onSelectFolder: () -> Void
    var onRevertRequested: () -> Void
    @State private var contentFilter: ContentFilter = .all
    @State private var isShowingCorrectionsSheet = false

    private enum ContentFilter: String, CaseIterable, Identifiable {
        case all
        case matches
        case missing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .matches: return "仅搜索结果"
            case .missing: return "缺失文本"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metadataSection
                authorSection
                contentSection
                validationSection
            }
            .padding()
        }
        .toolbar { toolbar }
        .sheet(isPresented: $isShowingCorrectionsSheet) {
            TypoCorrectionManagerView(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                onSelectFolder()
            } label: {
                Label("切换文件夹", systemImage: "folder")
            }
            Button {
                viewModel.runValidation()
            } label: {
                Label("校验", systemImage: "checkmark.shield")
            }
            .disabled(viewModel.articleDocument == nil)

            Button {
                viewModel.saveChanges()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!(viewModel.articleDocument?.hasUnsavedChanges ?? false))

            Button(role: .destructive) {
                onRevertRequested()
            } label: {
                Label("放弃更改", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(viewModel.articleDocument?.hasUnsavedChanges ?? false))
        }

        ToolbarItem(placement: .principal) {
            HStack {
                Image(systemName: "doc.text")
                Text(document.url.lastPathComponent)
                    .font(.headline)
            }
        }

        ToolbarItem(placement: .status) {
            SearchField(text: $viewModel.searchText)
                .frame(width: 220)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.url.lastPathComponent)
                .font(.title3)
                .fontWeight(.semibold)
            Text(document.url.deletingLastPathComponent().path)
                .font(.callout)
                .foregroundStyle(.secondary)
            reviewStatePicker
        }
    }

    private var reviewStatePicker: some View {
        HStack(spacing: 12) {
            Text("审核状态")
                .font(.callout)
            Picker("审核状态", selection: Binding(
                get: { viewModel.reviewStates[document.url] ?? .notStarted },
                set: { newValue in viewModel.markReviewed(newValue) }
            )) {
                ForEach(AppViewModel.ReviewState.allCases) { state in
                    Label(state.displayName, systemImage: state.iconName)
                        .tag(state)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
            if let values = try? document.url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modifiedDate = values.contentModificationDate {
                Text("修改时间：\(formatted(modifiedDate))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基本信息")
                .font(.headline)
            HStack(alignment: .top, spacing: 24) {
                // 左列
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    metadataRow(label: "标题", keyPath: \Article.title)
                    metadataRow(label: "描述", keyPath: \Article.description, axis: .vertical)
                    metadataRow(label: "URL", keyPath: \Article.url)
                    metadataRow(label: "时长", keyPath: \Article.duration)
                    metadataRow(label: "上传时间", keyPath: \Article.uploadDate)
                    metadataRow(label: "准备时间", keyPath: \Article.prepareDate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右列
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    metadataRow(label: "生成时间", keyPath: \Article.creationDate)
                    metadataRow(label: "分辨率", keyPath: \Article.resolution)
                    metadataRow(label: "尺寸", keyPath: \Article.width)
                    metadataRow(label: "高度", keyPath: \Article.height)
                    metadataRow(label: "码率", keyPath: \Article.bitrate)
                    metadataRow(label: "类型", keyPath: \Article.type)
                    metadataRow(label: "版本", keyPath: \Article.version)
                    metadataRow(label: "封面", keyPath: \Article.previewImageURL)
                    metadataRow(label: "校正时间", keyPath: \Article.correctedAt)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private enum MetadataAxis {
        case horizontal
        case vertical
    }

    private func metadataRow<T: LosslessStringConvertible>(label: String, keyPath: WritableKeyPath<Article, T?>, axis: MetadataAxis = .horizontal) -> some View {
        let binding = Binding<String>(
            get: { document.article[keyPath: keyPath].map { String($0) } ?? "" },
            set: { document.article[keyPath: keyPath] = $0.isEmpty ? nil : T($0) }
        )

        return GridRow {
            Text(label)
                .font(.callout)
                .frame(minWidth: 72, alignment: .leading)
            if axis == .vertical {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: binding)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                    if binding.wrappedValue.isEmpty {
                        Text("请输入")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
            } else {
                TextField("请输入", text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var authorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("作者")
                    .font(.headline)
                Spacer()
                Button {
                    document.addAuthor()
                } label: {
                    Label("添加作者", systemImage: "plus")
                }
            }

            if document.article.authors.isEmpty {
                Text("暂无作者信息")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(document.article.authors.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("作者", text: Binding(
                            get: { document.article.authors[index] },
                            set: { document.updateAuthor(at: index, with: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            document.removeAuthor(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("字幕内容")
                    .font(.headline)
                Spacer()
                Text("共 \(document.article.content.count) 条")
                    .foregroundStyle(.secondary)
                Button {
                    document.addContentEntry()
                } label: {
                    Label("新增一条", systemImage: "plus")
                }
            }

            HStack(spacing: 12) {
                Picker("过滤", selection: $contentFilter) {
                    ForEach(ContentFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Stepper("字体: \(Int(viewModel.contentFontSize))", value: $viewModel.contentFontSize, in: 10.0...30.0)
                    .frame(width: 160)

                Button {
                    viewModel.replaceTyposInContent()
                } label: {
                    Label("替换错别字", systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(viewModel.articleDocument == nil)

                Button {
                    isShowingCorrectionsSheet = true
                } label: {
                    Label("管理替换词", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }

                Spacer()

                if contentFilter == .missing {
                    Text("缺失 \(missingCount) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if searchKeyword != nil {
                    Text("匹配 \(matchingCount) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let count = viewModel.lastReplacementCount {
                    Text(count > 0 ? "已替换 \(count) 处" : "未找到可替换项")
                        .font(.caption)
                        .foregroundStyle(count > 0 ? .secondary : .tertiary)
                }
            }

            if document.article.content.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .overlay {
                        Text("暂无字幕内容")
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
            } else {
                VStack(spacing: 12) {
                    ForEach($document.article.content) { $entry in
                        if shouldDisplay($entry.wrappedValue) {
                            contentRow(entry: $entry)
                        }
                    }
                }
            }
        }
    }

    private func contentRow(entry: Binding<ArticleContent>) -> some View {
        let keyword = searchKeyword
        let highlight = keyword.map { matches(entry.wrappedValue, keyword: $0) } ?? false
        let dimmed = keyword != nil && !highlight && contentFilter == .all
        let isMissing = entry.text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let characterCount = entry.text.wrappedValue.count
        let isImportant = entry.important.wrappedValue ?? false

        return HStack(alignment: .top, spacing: 12) {
            // 左列：正文（主视区）
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: entry.text)
                        .font(.system(size: CGFloat(viewModel.contentFontSize)))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                    if entry.text.wrappedValue.isEmpty {
                        Text("请输入字幕文本")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(highlight ? Color.primary.opacity(0.25) : Color.secondary.opacity(0.25))
            )
            .opacity(dimmed ? 0.6 : 1)

            // 右列：时间与操作（固定较窄宽度，不干扰阅读）
            VStack(alignment: .trailing, spacing: 8) {
                TextField("时间戳", text: entry.timestample)
                    .frame(width: 140)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 6) {
                    Text("字符：\(characterCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isMissing {
                        Text("缺失文本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.25)))
                    }
                }

                Button {
                    entry.important.wrappedValue = isImportant ? nil : true
                } label: {
                    Label("是否重要标记", systemImage: isImportant ? "star.fill" : "star")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
                .foregroundStyle(isImportant ? Color.yellow : Color.primary)

                HStack(spacing: 8) {
                    Button { move(entry: entry.wrappedValue, up: true) } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderless)
                        .disabled(isFirst(entry: entry.wrappedValue))
                    Button { move(entry: entry.wrappedValue, up: false) } label: { Image(systemName: "arrow.down") }
                        .buttonStyle(.borderless)
                        .disabled(isLast(entry: entry.wrappedValue))
                    Button(role: .destructive) { document.removeContentEntry(entry.wrappedValue) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    Button { copyToPasteboard(entry.text.wrappedValue) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("复制字幕文本到剪贴板")
                }

                Spacer(minLength: 0)
            }
            .frame(width: 180, alignment: .trailing)
        }
        .padding(12)
        .background(isImportant ? Color.yellow.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.12), value: highlight)
        .animation(.easeInOut(duration: 0.12), value: dimmed)
        .animation(.easeInOut(duration: 0.12), value: isImportant)
    }

    private func isFirst(entry: ArticleContent) -> Bool {
        guard let first = document.article.content.first else { return false }
        return first.id == entry.id
    }

    private func isLast(entry: ArticleContent) -> Bool {
        guard let last = document.article.content.last else { return false }
        return last.id == entry.id
    }

    private func move(entry: ArticleContent, up: Bool) {
        guard let index = document.article.content.firstIndex(where: { $0.id == entry.id }) else { return }
        if up {
            guard index > 0 else { return }
            let item = document.article.content.remove(at: index)
            document.article.content.insert(item, at: index - 1)
        } else {
            guard index < document.article.content.count - 1 else { return }
            let item = document.article.content.remove(at: index)
            let target = min(index + 1, document.article.content.count)
            document.article.content.insert(item, at: target)
        }
    }

    private var searchKeyword: String? {
        let trimmed = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private var matchingCount: Int {
        guard let keyword = searchKeyword else { return document.article.content.count }
        return document.article.content.filter { matches($0, keyword: keyword) }.count
    }

    private var missingCount: Int {
        document.article.content.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private func shouldDisplay(_ entry: ArticleContent) -> Bool {
        switch contentFilter {
        case .all:
            return true
        case .matches:
            guard let keyword = searchKeyword else { return true }
            return matches(entry, keyword: keyword)
        case .missing:
            return entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func matches(_ entry: ArticleContent, keyword: String) -> Bool {
        entry.text.lowercased().contains(keyword) || entry.timestample.lowercased().contains(keyword)
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var validationSection: some View {
        Group {
            if viewModel.validationIssues.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自动检查")
                        .font(.headline)
                    ForEach(viewModel.validationIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "lightbulb")
                                .foregroundStyle(issue.severity == .error ? .red : .yellow)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.message)
                                if let suggestion = issue.suggestion {
                                    Text(suggestion)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(issue.severity == .error ? Color.red.opacity(0.1) : Color.yellow.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct TypoCorrectionManagerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var workingCorrections: [TypoCorrection] = []
    @State private var newSource: String = ""
    @State private var newReplacement: String = ""
    @State private var feedbackMessage: String?
    @State private var hasLoaded = false

    private var storagePath: String {
        viewModel.typoCorrectionsFilePath
    }

    private var relativeStoragePath: String {
        let home = NSHomeDirectory()
        if storagePath.hasPrefix(home) {
            let suffix = storagePath.dropFirst(home.count)
            return "~" + suffix
        }
        return storagePath
    }

    private var sanitizedWorkingCorrections: [TypoCorrection] {
        var unique: [String: TypoCorrection] = [:]
        for item in workingCorrections {
            let trimmedSource = item.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedReplacement = item.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSource.isEmpty, !trimmedReplacement.isEmpty else { continue }

            var sanitized = item
            sanitized.source = trimmedSource
            sanitized.replacement = trimmedReplacement

            if var existing = unique[trimmedSource] {
                existing.replacement = sanitized.replacement
                unique[trimmedSource] = existing
            } else {
                unique[trimmedSource] = sanitized
            }
        }
        return unique.values.sorted { lhs, rhs in
            lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
        }
    }

    private var canAddNewCorrection: Bool {
        let trimmedSource = newSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedSource.isEmpty && !trimmedReplacement.isEmpty
    }

    private var hasMeaningfulChanges: Bool {
        sanitizedWorkingCorrections != viewModel.typoCorrections
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("替换词将保存在 \(relativeStoragePath)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                List {
                    Section {
                        if workingCorrections.isEmpty {
                            Text("暂无自定义替换词")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($workingCorrections) { $item in
                                HStack(spacing: 12) {
                                    TextField("原词", text: $item.source)
                                        .textFieldStyle(.roundedBorder)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    TextField("替换为", text: $item.replacement)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            .onDelete { offsets in
                                workingCorrections.remove(atOffsets: offsets)
                            }
                        }
                    } header: {
                        Text("当前替换词")
                    } footer: {
                        Text("保存后将在替换时生效。")
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 220)

                VStack(alignment: .leading, spacing: 8) {
                    Text("添加新的替换词")
                        .font(.headline)
                    HStack(spacing: 12) {
                        TextField("原词", text: $newSource)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("替换为", text: $newReplacement)
                            .textFieldStyle(.roundedBorder)
                        Button("添加") {
                            appendNewCorrection()
                        }
                        .disabled(!canAddNewCorrection)
                    }
                    if let feedback = feedbackMessage {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack {
                    Button("取消") {
                        dismiss()
                    }
                    Spacer()
                    Button("保存更改") {
                        saveAndDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasMeaningfulChanges)
                }
            }
            .padding()
            .frame(minWidth: 520, minHeight: 420)
            .navigationTitle("管理替换词")
        }
        .onAppear {
            guard !hasLoaded else { return }
            workingCorrections = viewModel.typoCorrections
            hasLoaded = true
        }
    }

    private func appendNewCorrection() {
        let trimmedSource = newSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedReplacement.isEmpty else { return }

        if let index = workingCorrections.firstIndex(where: { $0.source.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedSource }) {
            workingCorrections[index].replacement = trimmedReplacement
            feedbackMessage = "已更新现有替换词"
        } else {
            workingCorrections.append(TypoCorrection(source: trimmedSource, replacement: trimmedReplacement))
            feedbackMessage = "已添加新的替换词"
        }

        workingCorrections.sort { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }

        newSource = ""
        newReplacement = ""
    }

    private func saveAndDismiss() {
        viewModel.updateTypoCorrections(with: sanitizedWorkingCorrections)
        dismiss()
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.delegate = context.coordinator
        searchField.placeholderString = "搜索字幕"
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
