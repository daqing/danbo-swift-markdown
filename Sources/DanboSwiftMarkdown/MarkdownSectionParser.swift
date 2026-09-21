//
//  MarkdownSectionParser.swift
//  swift-markdown
//

import Foundation
import Markdown

/// 一段行内内容：直接持有 swift-markdown 的 AST 节点，由 MarkdownAttributedBuilder
/// 的行内 walker 产出属性文本（块级结构则由下面的 MarkdownBlock 承载）。
typealias MarkdownInline = [any InlineMarkup]

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(MarkdownInline), unordered([MarkdownInline])
        case ordered([(number: Int, content: MarkdownInline)]), task(isDone: Bool, content: MarkdownInline)
        // 围栏代码块：language 是 cmark 的原始 info string（可能是 `swift title="x"`，
        // 也可能带 `js,linenos`），刻意不在这里切分——解析归 LanguageRegistry 管。
        case quote(MarkdownInline), code(text: String, language: String?), divider
        // GFM 表格：表头 + 每列对齐方式 + 数据行。
        case table(header: [MarkdownInline], alignments: [TableAlignment], rows: [[MarkdownInline]])
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

    /// 用 swift-markdown（CommonMark + GFM）解析整篇，再把 AST 拍平成 entries。
    /// 关掉智能标点：默认会把 `--` `...` 和直引号改写成印刷体，篡改笔记里的字面文本。
    private static func buildEntries(_ markdown: String) -> [MarkdownEntry] {
        var collector = MarkdownBlockCollector()
        collector.collect(Document(parsing: markdown, options: [.disableSmartOpts]))
        return collector.entries
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
}

/// 把 swift-markdown 的块级 AST 拍平成 MarkdownEntry 序列。
///
/// 本库的块模型是平的（见 MarkdownBlock），因此这里对嵌套结构做有损拍平：
/// 嵌套列表拍平成同级项、引用内的多个块合并成一段文本。这与替换前手写解析器
/// 按行扫描的结果一致，不引入视觉回归；真正的嵌套排版留作后续。
private struct MarkdownBlockCollector {
    private(set) var entries: [MarkdownEntry] = []
    private var blockCounter = 0

    mutating func collect(_ document: Document) {
        for child in document.children {
            append(child)
        }
    }

    private mutating func append(_ markup: Markup) {
        switch markup {
        case let heading as Heading:
            entries.append(MarkdownEntry(kind: .heading(heading.level, heading.plainText)))
        case let paragraph as Paragraph:
            appendBlock(.paragraph(Array(paragraph.inlineChildren)))
        case let list as UnorderedList:
            appendUnordered(list)
        case let list as OrderedList:
            appendOrdered(list)
        case let quote as BlockQuote:
            appendBlock(.quote(flattenedInline(quote.blockChildren)))
        case let code as CodeBlock:
            appendBlock(.code(text: trimmedCodeLiteral(code.code), language: code.language))
        case is ThematicBreak:
            appendBlock(.divider)
        case let table as Table:
            appendTable(table)
        default:
            // HTMLBlock / CustomBlock / BlockDirective 等：按原文当段落渲染，
            // 与替换前「不认识的行并入段落」的行为接近。
            let text = flattenedText(of: markup)
            guard !text.isEmpty else { return }
            appendBlock(.paragraph([Markdown.Text(text)]))
        }
    }

    private mutating func appendBlock(_ kind: MarkdownBlock.Kind, sourceLine: Int = -1) {
        blockCounter += 1
        let block = MarkdownBlock(id: "b\(blockCounter)", kind: kind, sourceLine: sourceLine)
        entries.append(MarkdownEntry(kind: .block(block)))
    }

    /// 无序列表：连续的非任务项聚合为一个列表块，任务项各自成块
    ///（替换前任务行会打断普通列表，分段方式保持一致）。
    private mutating func appendUnordered(_ list: UnorderedList) {
        var pending: [MarkdownInline] = []

        for item in flattenedItems(of: list) {
            guard let checkbox = item.checkbox else {
                pending.append(itemContent(item))
                continue
            }
            if !pending.isEmpty {
                appendBlock(.unordered(pending))
                pending = []
            }
            appendBlock(.task(isDone: checkbox == .checked, content: itemContent(item)),
                        sourceLine: sourceLine(of: item))
        }
        if !pending.isEmpty {
            appendBlock(.unordered(pending))
        }
    }

    /// 有序列表同理；序号由 swift-markdown 的 startIndex 起逐个递增。
    private mutating func appendOrdered(_ list: OrderedList) {
        var pending: [(number: Int, content: MarkdownInline)] = []
        var number = Int(list.startIndex)

        for item in flattenedItems(of: list) {
            guard let checkbox = item.checkbox else {
                pending.append((number, itemContent(item)))
                number += 1
                continue
            }
            if !pending.isEmpty {
                appendBlock(.ordered(pending))
                pending = []
            }
            appendBlock(.task(isDone: checkbox == .checked, content: itemContent(item)),
                        sourceLine: sourceLine(of: item))
        }
        if !pending.isEmpty {
            appendBlock(.ordered(pending))
        }
    }

    private mutating func appendTable(_ table: Table) {
        // cells / rows 都是 LazyMapSequence，必须显式收成 Array。
        let header = Array(table.head.cells).map { Array($0.inlineChildren) }
        guard !header.isEmpty else { return }

        let alignments = table.columnAlignments.map { alignment -> TableAlignment in
            switch alignment {
            case .center?: return .center
            case .right?: return .right
            default: return .left
            }
        }
        let rows = Array(table.body.rows).map { row in
            Array(row.cells).map { Array($0.inlineChildren) }
        }
        appendBlock(.table(header: header, alignments: alignments, rows: rows))
    }

    /// 列表项序列：嵌套列表的项拍平到同一级（替换前按行扫描时它们本就是同级项）。
    private func flattenedItems(of markup: Markup) -> [ListItem] {
        var items: [ListItem] = []
        for child in markup.children {
            guard let item = child as? ListItem else { continue }
            items.append(item)
            for block in item.blockChildren where block is UnorderedList || block is OrderedList {
                items.append(contentsOf: flattenedItems(of: block))
            }
        }
        return items
    }

    /// 列表项的行内内容：取首个段落，块内的代码块/引用等折成文本追加。
    private func itemContent(_ item: ListItem) -> MarkdownInline {
        var content: MarkdownInline = []
        for block in item.blockChildren {
            // 嵌套列表已拍平成同级项，不再重复折进本项文本。
            if block is UnorderedList || block is OrderedList { continue }
            appendInline(of: block, to: &content)
        }
        return content
    }

    private func flattenedInline(_ blocks: some Sequence<BlockMarkup>) -> MarkdownInline {
        var content: MarkdownInline = []
        for block in blocks {
            appendInline(of: block, to: &content)
        }
        return content
    }

    /// 把一个块折成行内内容：段落取其行内节点，其它块取纯文本。
    /// 多段之间用换行符分隔，与替换前「多行合并成一个块」的形态一致。
    private func appendInline(of block: BlockMarkup, to content: inout MarkdownInline) {
        if let paragraph = block as? Paragraph {
            if !content.isEmpty { content.append(Markdown.Text("\n")) }
            content.append(contentsOf: paragraph.inlineChildren)
            return
        }

        let text = flattenedText(of: block)
        guard !text.isEmpty else { return }
        if !content.isEmpty { content.append(Markdown.Text("\n")) }
        content.append(Markdown.Text(text))
    }

    /// cmark 的代码块字面量恒带结尾换行，而这里每行都由调用方自己补换行，
    /// 原样保留会多渲染出一个空行（块后再接一段时表现为多一条空段落）。
    /// 去掉后与替换前「按行拼接」的形态一致。
    private func trimmedCodeLiteral(_ code: String) -> String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    private func flattenedText(of markup: Markup) -> String {
        switch markup {
        case let code as CodeBlock:
            return trimmedCodeLiteral(code.code)
        case let html as HTMLBlock:
            return html.rawHTML
        case is ThematicBreak:
            return ""
        case let quote as BlockQuote:
            return quote.blockChildren.map { flattenedText(of: $0) }.joined(separator: "\n")
        default:
            return (markup as? PlainTextConvertibleMarkup)?.plainText ?? ""
        }
    }

    /// swift-markdown 的行号是 1 基，这里换成源 Markdown 的 0 基行号（宿主按行回写勾选状态）；
    /// 拿不到 range 时回退 -1，checkbox 渲染成不可点，与非任务块一致。
    private func sourceLine(of item: ListItem) -> Int {
        guard let range = item.range else { return -1 }
        return max(0, range.lowerBound.line - 1)
    }
}
