//
//  MarkdownSectionParser.swift
//  swift-markdown
//

import Foundation

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String), unordered([String])
        case ordered([(number: Int, text: String)]), task(Bool, String)
        case quote(String), code(String), divider
        case image(alt: String, url: URL)
        // GFM 表格：表头 + 每列对齐方式 + 数据行。
        case table(header: [String], alignments: [TableAlignment], rows: [[String]])
    }

    let id: String
    let kind: Kind
    /// 任务行在源 Markdown 中的行号（0 起）：checkbox 点击回写用；非任务块为 -1。
    /// 显式写 init：带默认值的 let 不会进入成员初始化器的参数列表（var 才会）。
    let sourceLine: Int

    init(id: String, kind: Kind, sourceLine: Int = -1) {
        self.id = id
        self.kind = kind
        self.sourceLine = sourceLine
    }
}

/// 表格每列的对齐方式（由分隔行 `:---: / ---: / :---` 的冒号位置决定）。
enum TableAlignment {
    case left, center, right
}

struct MarkdownHeading {
    let level: Int
    let text: String
}

struct MarkdownNode: Identifiable {
    let id: String
    let collapseKey: String
    let heading: MarkdownHeading?
    var content: [MarkdownBlock]
    var children: [MarkdownNode]

    var hasBody: Bool { !content.isEmpty || !children.isEmpty }

    var collapsedCount: Int {
        content.count + children.reduce(0) { $0 + 1 + $1.collapsedCount }
    }
}

struct MarkdownEntry {
    enum Kind {
        case heading(Int, String)
        case block(MarkdownBlock)
    }
    let kind: Kind
}

enum MarkdownSectionParser {
    static func parse(_ markdown: String) -> MarkdownNode {
        buildTree(buildEntries(markdown))
    }

    static func collapseKeys(_ markdown: String) -> [String] {
        var keys: [String] = []
        collectKeys(buildTree(buildEntries(markdown)).children, into: &keys)
        return keys
    }

    private static func collectKeys(_ nodes: [MarkdownNode], into keys: inout [String]) {
        for node in nodes {
            keys.append(node.collapseKey)
            collectKeys(node.children, into: &keys)
        }
    }

    private static func buildEntries(_ markdown: String) -> [MarkdownEntry] {
        let lines = markdown.components(separatedBy: .newlines)
        var entries: [MarkdownEntry] = []
        var paragraph: [String] = []
        var index = 0
        var blockCounter = 0

        func nextBlockID() -> String {
            blockCounter += 1
            return "b\(blockCounter)"
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let block = MarkdownBlock(id: nextBlockID(), kind: .paragraph(paragraph.joined(separator: "\n")))
            entries.append(MarkdownEntry(kind: .block(block)))
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                index += 1
            } else if let heading = heading(in: line) {
                flushParagraph()
                entries.append(MarkdownEntry(kind: .heading(heading.level, heading.text)))
                index += 1
            } else if isDivider(line) {
                flushParagraph()
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .divider))))
                index += 1
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .code(code.joined(separator: "\n"))))))
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .quote(quote.joined(separator: "\n"))))))
            } else if let task = task(in: line) {
                flushParagraph()
                // 记录源行号：渲染出的 checkbox 点击后按行号回写源 Markdown。
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .task(task.done, task.text), sourceLine: index))))
                index += 1
            } else if let item = unorderedItem(in: line) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let next = unorderedItem(in: lines[index]), task(in: lines[index]) == nil {
                    items.append(next)
                    index += 1
                }
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .unordered(items)))))
            } else if let item = orderedItem(in: line) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let next = orderedItem(in: lines[index]) {
                    items.append(next)
                    index += 1
                }
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .ordered(items)))))
            } else if let image = imageLine(in: line) {
                flushParagraph()
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(id: nextBlockID(), kind: .image(alt: image.alt, url: image.url)))))
                index += 1
            } else if let table = table(in: lines, at: index) {
                flushParagraph()
                entries.append(MarkdownEntry(kind: .block(MarkdownBlock(
                    id: nextBlockID(),
                    kind: .table(header: table.header, alignments: table.alignments, rows: table.rows)
                ))))
                index += table.rowCount
            } else {
                paragraph.append(line)
                index += 1
            }
        }
        flushParagraph()
        return entries
    }

    private static func buildTree(_ entries: [MarkdownEntry]) -> MarkdownNode {
        var root = MarkdownNode(id: "root", collapseKey: "", heading: nil, content: [], children: [])
        var i = 0
        var childIndex = 0

        while i < entries.count {
            switch entries[i].kind {
            case .block(let block):
                root.content.append(block)
                i += 1
            case .heading(let level, _):
                let (node, next) = buildSection(entries, i, level, path: "root/\(childIndex)")
                root.children.append(node)
                childIndex += 1
                i = next
            }
        }
        return root
    }

    private static func buildSection(
        _ entries: [MarkdownEntry],
        _ start: Int,
        _ level: Int,
        path: String
    ) -> (MarkdownNode, Int) {
        guard case .heading(let headingLevel, let text) = entries[start].kind else {
            return (MarkdownNode(id: path, collapseKey: "", heading: nil, content: [], children: []), start + 1)
        }

        var node = MarkdownNode(
            id: path,
            collapseKey: "\(headingLevel):\(text)",
            heading: MarkdownHeading(level: headingLevel, text: text),
            content: [],
            children: []
        )
        var i = start + 1
        var childIndex = 0

        while i < entries.count {
            switch entries[i].kind {
            case .block(let block):
                node.content.append(block)
                i += 1
            case .heading(let childLevel, _):
                if childLevel <= level {
                    return (node, i)
                }
                let (child, next) = buildSection(entries, i, childLevel, path: "\(path)/\(childIndex)")
                node.children.append(child)
                childIndex += 1
                i = next
            }
        }
        return (node, i)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let remainder = trimmed.dropFirst(level)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (level, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2, ["- ", "* ", "+ "].contains(String(trimmed.prefix(2))) else { return nil }
        return String(trimmed.dropFirst(2))
    }

    private static func task(in line: String) -> (done: Bool, text: String)? {
        guard let item = unorderedItem(in: line), item.count >= 4 else { return nil }
        if item.hasPrefix("[ ] ") { return (false, String(item.dropFirst(4))) }
        // 空方括号也算未完成：`- [] 任务`。
        if item.hasPrefix("[] ") { return (false, String(item.dropFirst(3))) }
        if item.lowercased().hasPrefix("[x] ") { return (true, String(item.dropFirst(4))) }
        return nil
    }

    private static func orderedItem(in line: String) -> (number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: "."),
              let number = Int(trimmed[..<dot]) else { return nil }
        let text = trimmed[trimmed.index(after: dot)...]
        guard text.first?.isWhitespace == true else { return nil }
        return (number, text.trimmingCharacters(in: .whitespaces))
    }

    private struct Table {
        let header: [String]
        let alignments: [TableAlignment]
        let rows: [[String]]
        /// 整张表格占用的行数（表头 + 分隔行 + 数据行）。
        let rowCount: Int
    }

    /// 从 lines[start] 开始解析 GFM 表格：表头行 + `---` 分隔行 + 若干 `|` 分列的数据行。
    private static func table(in lines: [String], at start: Int) -> Table? {
        guard start + 1 < lines.count else { return nil }
        let header = splitTableRow(lines[start])
        guard !header.isEmpty, isTableSeparator(lines[start + 1]) else { return nil }

        let separatorCells = splitTableRow(lines[start + 1])
        var alignments = separatorCells.prefix(header.count).map(alignment(for:))
        alignments.append(contentsOf: Array(repeating: TableAlignment.left, count: max(0, header.count - alignments.count)))

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count, isTableRow(lines[index]) {
            rows.append(splitTableRow(lines[index]))
            index += 1
        }
        return Table(header: header, alignments: alignments, rows: rows, rowCount: 2 + rows.count)
    }

    /// 按竖线切分表格行：允许省略行首/行尾的竖线，单元格内容去掉首尾空白。
    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return [] }
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 分隔行：每个单元格形如 `---` / `:---` / `:---:` / `---:`。
    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            var body = Substring(cell)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).contains("|")
    }

    private static func alignment(for separatorCell: String) -> TableAlignment {
        let leading = separatorCell.hasPrefix(":")
        let trailing = separatorCell.hasSuffix(":")
        if leading && trailing { return .center }
        if trailing { return .right }
        return .left
    }

    /// 匹配一整行都是图片引用 `![alt](url)` 的情况，例如由粘贴/拖拽插入的图片。
    private static let imageLineRegex = try? NSRegularExpression(
        pattern: #"^!\[([^\]]*)\]\(([^)]+)\)$"#
    )

    private static func imageLine(in line: String) -> (alt: String, url: URL)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let regex = imageLineRegex,
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(location: 0, length: (trimmed as NSString).length)
              ) else { return nil }

        let ns = trimmed as NSString
        let alt = ns.substring(with: match.range(at: 1))
        let urlString = ns.substring(with: match.range(at: 2))
        guard let url = URL(string: urlString) else { return nil }
        return (alt, url)
    }

    private static func isDivider(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespaces)
        return value.count >= 3 && (Set(value) == ["-"] || Set(value) == ["*"] || Set(value) == ["_"])
    }
}
