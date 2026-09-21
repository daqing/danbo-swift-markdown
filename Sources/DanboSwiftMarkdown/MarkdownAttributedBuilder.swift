//
//  MarkdownAttributedBuilder.swift
//  swift-markdown
//

import AppKit
import Foundation
import Markdown

// 代码块卡片：圆角 + 内边距。NSAttributedString.backgroundColor 只能画直角矩形，
// 因此这里用自定义 attribute 标记代码区，由 MarkdownTextView.drawBackground 自绘圆角卡片。
let codeBlockBackgroundAttributeKey = NSAttributedString.Key("DanboSwiftMarkdown.codeBlock")
let codeBlockBackgroundFill = NSColor.labelColor.withAlphaComponent(0.06)
let codeBlockCornerRadius: CGFloat = 10
let codeBlockPaddingX: CGFloat = 12
let codeBlockPaddingY: CGFloat = 8
/// 代码块卡片右侧为复制图标预留的额外宽度：让图标完整落在文字右侧的空白区，
/// 不再压住行尾文字（短单行代码块尤其明显）。
let codeBlockCopyIconReserve: CGFloat = 40

// 表格：单元格折行到所在列宽内，逐行渲染成段落，列位置用空白附件占位推齐；
// 网格线与表头底色由 MarkdownTextView 依据行段落上的 tableRowAttributeKey 属性自绘。
let tableRowAttributeKey = NSAttributedString.Key("DanboSwiftMarkdown.tableRow")
let tableBorderColor = NSColor.separatorColor
let tableHeaderBackgroundColor = NSColor.labelColor.withAlphaComponent(0.05)
let tableColumnPadding: CGFloat = 12
/// 单元格文字与上方分隔线（或表格上边框）的留白：每个单元格的顶部内边距。
let tableCellTopPadding: CGFloat = 10
/// 单元格文字与下方分隔线（或表格下边框）的留白。
let tableCellBottomPadding: CGFloat = 6

enum MarkdownAttributedBuilder {
    private static let bodyFont = NSFont.systemFont(ofSize: DanboMarkdownConfiguration.bodyFontSize)

    // 黑白 Notion 风格配色：用 labelColor 的层级区分，不引入彩色。
    private static let primaryColor = NSColor.labelColor
    private static let secondaryColor = NSColor.secondaryLabelColor

    // 加粗：用红色强调。明暗主题各取一档，保证在各自底色上的对比度。
    private static let boldColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 1.00, green: 0.60, blue: 0.58, alpha: 1)
            : NSColor(srgbRed: 0.85, green: 0.23, blue: 0.23, alpha: 1)
    }

    // 自定义语法 __Foo__：绿色强调。同样按明暗主题各取一档。
    private static let greenTextColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.62, green: 0.91, blue: 0.62, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.56, blue: 0.24, alpha: 1)
    }

    // __Foo__ 与 **Foo** 在 CommonMark 里都解析成加粗节点，AST 不保留原始分隔符，
    // 因此绿色强调靠回查源码区分，见 isGreenStrong。


    // 链接：Notion 采用与正文同色 + 下划线的处理。
    private static let linkColor = NSColor.labelColor
    private static let linkUnderlineColor = NSColor.labelColor.withAlphaComponent(0.5)

    // 代码：浅灰底 + 等宽字体。代码块背景由 MarkdownTextView.drawBackground 自绘圆角卡片。
    private static let inlineCodeBackgroundColor = NSColor.labelColor.withAlphaComponent(0.08)

    // 引用：浅灰底 + 次级文字色。
    private static let quoteBackgroundColor = NSColor.labelColor.withAlphaComponent(0.05)

    // 分隔线：细灰线。
    private static let dividerColor = NSColor.separatorColor
    // 分隔线上下等宽的留白，与正文段落间距保持一致，让分隔线看起来居中。
    private static let dividerVerticalPadding: CGFloat = 10

    // 段落间距：空行（两个换行）分隔的段落之间留白更大。
    private static let blockParagraphSpacing: CGFloat = 14
    // 段内行距：单个换行分隔的多行属于同一段落，行距收紧、聚在一起。
    private static let innerLineSpacing: CGFloat = 0.85

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    /// 当前构建所用的源 Markdown：AST 不保留原始分隔符，自定义的绿色强调要靠源码位置
    /// 回查区分（见 isGreenStrong）。与 availableContentWidth 一样属于构建期输入，
    /// 由 build 在每次构建前写入；全部在主线程读写，与渲染管线同一线程约定。
    private static var currentSource: MarkdownSource?

    private static let newline = NSAttributedString(string: "\n")

    static func build(markdown: String, collapsedSections: Set<String>, highlightText: String?, taskLinksEnabled: Bool = false) -> NSAttributedString {
        self.taskLinksEnabled = taskLinksEnabled
        self.currentSource = MarkdownSource(markdown)
        let root = MarkdownSectionParser.parse(markdown)
        let result = NSMutableAttributedString()

        appendBlocks(root.content, to: result, indent: 0)
        for node in root.children {
            appendNode(node, to: result, indent: 0, collapsed: collapsedSections)
        }

        styleLinks(in: result)
        trimTrailingWhitespace(in: result)

        if let highlightText, !highlightText.isEmpty {
            applyHighlight(to: result, highlightText: highlightText)
        }
        return result
    }

    private static func appendNode(_ node: MarkdownNode, to result: NSMutableAttributedString, indent: CGFloat, collapsed: Set<String>) {
        guard let heading = node.heading else { return }
        let level = heading.level
        let isCollapsed = collapsed.contains(node.collapseKey)

        let chevron = node.hasBody ? (isCollapsed ? "▸ " : "▾ ") : ""
        let chevronWidth: CGFloat = chevron.isEmpty ? 0 : (chevron as NSString).size(withAttributes: [.font: headingFont(level)]).width
        var line = chevron + heading.text.uppercased()
        if isCollapsed {
            line += "  · \(node.collapsedCount)"
        }

        let headingString = NSMutableAttributedString(
            string: line,
            attributes: [
                .font: headingFont(level),
                .foregroundColor: primaryColor,
                .paragraphStyle: headingParagraphStyle(indent: indent, level: level)
            ]
        )
        if node.hasBody, let url = collapseURL(for: node.collapseKey) {
            headingString.addAttribute(.link, value: url, range: NSRange(location: 0, length: headingString.length))
        }
        let headingStart = result.length
        result.append(headingString)
        result.append(newline)

        guard !isCollapsed else { return }

        // 标题后紧跟分隔线时，同样清零标题的段后间距，让分隔线自己承担等宽留白。
        if isDividerBlock(node.content.first) {
            zeroTrailingParagraphSpacing(in: result, within: NSRange(location: headingStart, length: headingString.length + 1))
        }

        let contentIndent = indent + chevronWidth
        appendBlocks(node.content, to: result, indent: contentIndent)
        for child in node.children {
            appendNode(child, to: result, indent: contentIndent, collapsed: collapsed)
        }
    }

    private static func appendBlocks(_ blocks: [MarkdownBlock], to result: NSMutableAttributedString, indent: CGFloat) {
        for (index, block) in blocks.enumerated() {
            let followedByDivider = blocks.indices.contains(index + 1) && isDividerBlock(blocks[index + 1])
            appendBlock(block, to: result, indent: indent, followedByDivider: followedByDivider)
        }
    }

    private static func isDividerBlock(_ block: MarkdownBlock?) -> Bool {
        guard let block else { return false }
        if case .divider = block.kind { return true }
        return false
    }

    private static func appendBlock(_ block: MarkdownBlock, to result: NSMutableAttributedString, indent: CGFloat, followedByDivider: Bool) {
        let start = result.length
        switch block.kind {
        case let .paragraph(content):
            // 整段只有一张图片时按图片段落排版（上下留白与正文段落不同）。
            let isImage = isSingleImage(content)
            let style = isImage ? imageParagraphStyle(indent: indent) : paragraphStyle(indent: indent)
            result.append(inline(content, baseFont: bodyFont, color: primaryColor, paragraphStyle: style))
            result.append(newline)
            if !isImage {
                tightenInnerLineSpacing(in: result, within: NSRange(location: start, length: result.length - start))
            }

        case let .unordered(items):
            for item in items {
                let style = listParagraphStyle(indent: indent, markerWidth: 16)
                result.append(inlineLine(marker: "•  ", content: item, baseFont: bodyFont, color: primaryColor, paragraphStyle: style))
                result.append(newline)
            }
            setTrailingParagraphSpacing(10, in: result, within: NSRange(location: start, length: result.length - start))

        case let .ordered(items):
            for (number, content) in items {
                let style = listParagraphStyle(indent: indent, markerWidth: 22)
                result.append(inlineLine(marker: "\(number).  ", content: content, baseFont: bodyFont, color: primaryColor, paragraphStyle: style))
                result.append(newline)
            }
            setTrailingParagraphSpacing(10, in: result, within: NSRange(location: start, length: result.length - start))

        case let .task(isDone, content):
            let marker = isDone ? "☑  " : "☐  "
            let style = listParagraphStyle(indent: indent, markerWidth: 18)
            let line = NSMutableAttributedString(attributedString: inlineLine(
                marker: marker,
                content: content,
                baseFont: bodyFont,
                color: isDone ? secondaryColor : primaryColor,
                paragraphStyle: style
            ))
            let markerLength = (marker as NSString).length
            // 任务行整行可点（OKR 进度等所见即所得更新）：checkbox 与行内文字都挂任务
            // 链接，点击任一处都翻转源 Markdown 对应行的勾选状态。行内自带的链接
            // （Markdown 链接 / 裸链接）保留自己的 URL，点击仍是打开链接。
            // 只读场景（项目简介等）不加链接。
            if taskLinksEnabled, block.sourceLine >= 0, let url = taskURL(forLine: block.sourceLine) {
                for range in taskLinkRanges(in: line) {
                    line.addAttribute(.link, value: url, range: range)
                }
            }
            if isDone {
                // 划线只打在任务文字上，checkbox 本身保持干净的完成态。
                line.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: markerLength, length: line.length - markerLength))
            }
            result.append(line)
            result.append(newline)
            setTrailingParagraphSpacing(10, in: result, within: NSRange(location: start, length: result.length - start))

        case let .quote(content):
            let line = NSMutableAttributedString(attributedString: inline(content, baseFont: bodyFont, color: secondaryColor, paragraphStyle: paragraphStyle(indent: indent + 4)))
            line.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: NSRange(location: 0, length: line.length))
            result.append(line)
            result.append(newline)
            tightenInnerLineSpacing(in: result, within: NSRange(location: start, length: result.length - start))

        case let .code(text):
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                    .foregroundColor: primaryColor,
                    .paragraphStyle: codeParagraphStyle(indent: indent)
                ]
            )
            attributed.addAttribute(codeBlockBackgroundAttributeKey, value: true, range: NSRange(location: 0, length: attributed.length))
            // 块内行距/段距为 0（紧凑），块与上下文之间的间距只在首/末行补回。
            setCodeBlockFirstLineSpacing(in: attributed)
            setTrailingParagraphSpacing(20, in: attributed, within: NSRange(location: 0, length: attributed.length))
            result.append(attributed)
            result.append(newline)

        case let .table(header, alignments, rows):
            appendTable(header: header, alignments: alignments, rows: rows, to: result, indent: indent)

        case .divider:
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = dividerVerticalPadding
            style.paragraphSpacing = dividerVerticalPadding
            result.append(NSAttributedString(
                string: "─────",
                attributes: [.foregroundColor: dividerColor, .font: NSFont.systemFont(ofSize: 11), .paragraphStyle: style]
            ))
            result.append(newline)
        }

        // 若后面紧跟分隔线，把本块末尾段落的段后间距清零，
        // 让分隔线自身承担等宽的上下留白，避免上方间距叠加后不居中。
        if followedByDivider {
            zeroTrailingParagraphSpacing(in: result, within: NSRange(location: start, length: result.length - start))
        }
    }

    /// 将给定范围内「最后一个段落」的段后间距设为指定值（不影响块内其它行/段落的间距）。
    private static func setTrailingParagraphSpacing(_ spacing: CGFloat, in attributed: NSMutableAttributedString, within range: NSRange) {
        applyTrailingParagraphSpacing(spacing, in: attributed, within: range)
    }

    /// 段落内部由单个换行分隔的多行仍属于同一段落：
    /// 收紧除最后一行外各行的段后间距，让整段聚在一起，与空行分隔的段落间留白形成对比。
    private static func tightenInnerLineSpacing(in attributed: NSMutableAttributedString, within range: NSRange) {
        let ns = attributed.string as NSString
        let end = NSMaxRange(range)
        var paragraphs: [NSRange] = []
        var start = range.location
        while start < end {
            let newlineRange = ns.range(of: "\n", options: [], range: NSRange(location: start, length: end - start))
            if newlineRange.location == NSNotFound {
                paragraphs.append(NSRange(location: start, length: end - start))
                break
            }
            paragraphs.append(NSRange(location: start, length: newlineRange.location + 1 - start))
            start = newlineRange.location + 1
        }
        guard paragraphs.count > 1 else { return }
        for paragraphRange in paragraphs.dropLast() {
            let existing = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let style = NSMutableParagraphStyle()
            if let existing {
                style.setParagraphStyle(existing)
            }
            // 单换行的行与行之间：行距减半、段后间距清零，让整段聚在一起。
            style.lineSpacing = innerLineSpacing
            style.paragraphSpacing = 0
            attributed.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        }
    }

    /// 将给定范围内「最后一个段落」的段后间距清零（不影响块内其它行/段落的间距）。
    private static func zeroTrailingParagraphSpacing(in attributed: NSMutableAttributedString, within range: NSRange) {
        applyTrailingParagraphSpacing(0, in: attributed, within: range)
    }

    private static func applyTrailingParagraphSpacing(_ spacing: CGFloat, in attributed: NSMutableAttributedString, within range: NSRange) {
        let ns = attributed.string as NSString
        let rangeEnd = range.location + range.length
        let lastNewline = ns.range(of: "\n", options: .backwards, range: range).location

        let paragraphStart: Int
        let paragraphEnd: Int
        if lastNewline == NSNotFound {
            paragraphStart = range.location
            paragraphEnd = rangeEnd
        } else if lastNewline < rangeEnd - 1 {
            // 尾部没有换行符：最后一个段落是最后一个换行符之后的内容
            //（代码块文本就是这种形态，此前被误判成倒数第二段）。
            paragraphStart = lastNewline + 1
            paragraphEnd = rangeEnd
        } else {
            let before = NSRange(location: range.location, length: lastNewline - range.location)
            let prevNewline = before.length > 0 ? ns.range(of: "\n", options: .backwards, range: before).location : NSNotFound
            paragraphStart = prevNewline == NSNotFound ? range.location : prevNewline + 1
            paragraphEnd = lastNewline + 1
        }
        let paragraphRange = NSRange(location: paragraphStart, length: paragraphEnd - paragraphStart)
        guard paragraphRange.length > 0 else { return }

        let existing = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        let style = NSMutableParagraphStyle()
        if let existing {
            style.setParagraphStyle(existing)
        }
        style.paragraphSpacing = spacing
        attributed.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
    }

    // MARK: 行内渲染

    /// 行内渲染上下文：walk 行内 AST 时逐层叠加的字体、颜色与装饰。
    private struct InlineStyle {
        var font: NSFont
        var color: NSColor
        var strikethrough = false
        var link: URL?
    }

    /// 渲染一段行内 AST，并按整段施加段落样式与裸链接检测。
    private static func inline(_ content: MarkdownInline, baseFont: NSFont, color: NSColor, paragraphStyle: NSParagraphStyle, htmlBreaksAsSpaces: Bool = false) -> NSAttributedString {
        inlineLine(marker: "", content: content, baseFont: baseFont, color: color, paragraphStyle: paragraphStyle, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
    }

    /// 渲染「标记 + 行内内容」组成的一行（列表圆点、序号、任务 checkbox 都走这里）：
    /// 段落样式必须覆盖整行（含标记），否则排版器按段首字符取样式会拿不到。
    private static func inlineLine(marker: String, content: MarkdownInline, baseFont: NSFont, color: NSColor, paragraphStyle: NSParagraphStyle, htmlBreaksAsSpaces: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let style = InlineStyle(font: baseFont, color: color)
        appendText(marker, to: result, style: style)
        append(content, to: result, style: style, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
        let full = NSRange(location: 0, length: result.length)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: full)
        addDetectedLinks(to: result, in: full)
        return result
    }

    private static func append(_ content: MarkdownInline, to result: NSMutableAttributedString, style: InlineStyle, htmlBreaksAsSpaces: Bool) {
        for node in content {
            append(node, to: result, style: style, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
        }
    }

    private static func append(_ node: any InlineMarkup, to result: NSMutableAttributedString, style: InlineStyle, htmlBreaksAsSpaces: Bool) {
        switch node {
        case let text as Markdown.Text:
            appendText(text.string, to: result, style: style)

        case let code as Markdown.InlineCode:
            var codeStyle = style
            codeStyle.font = .monospacedSystemFont(ofSize: style.font.pointSize * 0.92, weight: .regular)
            let start = result.length
            appendText(code.code, to: result, style: codeStyle)
            result.addAttribute(.backgroundColor, value: inlineCodeBackgroundColor, range: NSRange(location: start, length: result.length - start))

        case let strong as Markdown.Strong:
            var strongStyle = style
            strongStyle.font = .systemFont(ofSize: style.font.pointSize, weight: .semibold)
            strongStyle.color = isGreenStrong(strong) ? greenTextColor : boldColor
            append(children(of: strong), to: result, style: strongStyle, htmlBreaksAsSpaces: htmlBreaksAsSpaces)

        case let emphasis as Markdown.Emphasis:
            var emphasisStyle = style
            emphasisStyle.font = NSFontManager.shared.convert(style.font, toHaveTrait: .italicFontMask)
            append(children(of: emphasis), to: result, style: emphasisStyle, htmlBreaksAsSpaces: htmlBreaksAsSpaces)

        case let strikethrough as Markdown.Strikethrough:
            var strikethroughStyle = style
            strikethroughStyle.strikethrough = true
            append(children(of: strikethrough), to: result, style: strikethroughStyle, htmlBreaksAsSpaces: htmlBreaksAsSpaces)

        case let link as Markdown.Link:
            var linkStyle = style
            if let destination = link.destination {
                linkStyle.link = URL(string: destination)
            }
            let start = result.length
            append(children(of: link), to: result, style: linkStyle, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
            if let url = linkStyle.link, result.length > start {
                result.addAttribute(.link, value: url, range: NSRange(location: start, length: result.length - start))
            }

        case let image as Markdown.Image:
            appendImage(image, to: result, style: style, htmlBreaksAsSpaces: htmlBreaksAsSpaces)

        case is Markdown.SoftBreak, is Markdown.LineBreak:
            appendText("\n", to: result, style: style)

        case let html as Markdown.InlineHTML:
            // 表格单元格不支持行内 HTML：`<br>` 这类换行标记按空白渲染。
            appendText(htmlBreaksAsSpaces && isBreakTag(html.rawHTML) ? " " : html.rawHTML, to: result, style: style)

        case let symbol as Markdown.SymbolLink:
            appendText(symbol.destination ?? "", to: result, style: style)

        default:
            // 其余节点（CustomInline、InlineAttributes 等）：有子节点就继续下钻，否则退回纯文本。
            let nested = children(of: node)
            if nested.isEmpty {
                // InlineMarkup 本身继承 PlainTextConvertibleMarkup，无需再判定转换。
                appendText(node.plainText, to: result, style: style)
            } else {
                append(nested, to: result, style: style, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
            }
        }
    }

    private static func children(of markup: Markup) -> MarkdownInline {
        markup.children.compactMap { $0 as? any InlineMarkup }
    }

    private static func appendText(_ text: String, to result: NSMutableAttributedString, style: InlineStyle) {
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.color
        ]
        if style.strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = style.link {
            attributes[.link] = link
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
    }

    /// `__Foo__` 在 CommonMark 里与 `**Foo**` 等价，都解析成加粗节点；AST 不保留分隔符，
    /// 只能按节点的源码位置回查源串区分两者（见 MarkdownSource）。
    private static func isGreenStrong(_ strong: Markdown.Strong) -> Bool {
        guard let source = currentSource, let range = strong.range else { return false }
        return source.hasPrefix("__", at: range.lowerBound)
    }

    private static func isBreakTag(_ html: String) -> Bool {
        let compact = html.lowercased().replacingOccurrences(of: " ", with: "")
        return compact == "<br>" || compact == "<br/>"
    }

    /// 整段只有一张图片：按图片段落排版（上下留白与正文段落不同）。
    private static func isSingleImage(_ content: MarkdownInline) -> Bool {
        content.count == 1 && content[0] is Markdown.Image
    }

    private static func appendImage(_ image: Markdown.Image, to result: NSMutableAttributedString, style: InlineStyle, htmlBreaksAsSpaces: Bool) {
        if let source = image.source, let url = URL(string: source), let attachment = imageAttachment(from: url) {
            result.append(NSAttributedString(attachment: attachment))
        } else {
            // 图片加载失败：显示 alt 文本，避免内容凭空消失。
            append(children(of: image), to: result, style: style, htmlBreaksAsSpaces: htmlBreaksAsSpaces)
        }
    }

    // MARK: 图片附件

    private static let imageCache = NSCache<NSString, NSImage>()
    /// 图片最大显示尺寸（按比例缩放，不拉伸）。
    private static let imageMaxWidth: CGFloat = 480
    private static let imageMaxHeight: CGFloat = 560
    /// 独立成行的图片上下留白。
    private static let imageParagraphSpacing: CGFloat = 12
    /// 当前渲染容器的内容宽度，由 updateNSView 在每次渲染前写入，用于让图片自适应容器。
    static var availableContentWidth: CGFloat = imageMaxWidth

    /// 任务行是否渲染为可点击链接（scheme 见 DanboMarkdownConfiguration.linkScheme，
    /// host 为 task），由 build 在每次构建前写入。
    private static var taskLinksEnabled = false

    /// 从 URL 加载图片并缩放，返回可插入到文本系统的附件；加载失败返回 nil。
    private static func imageAttachment(from url: URL) -> NSTextAttachment? {
        let key = url.absoluteString as NSString
        let image: NSImage?
        if let cached = imageCache.object(forKey: key) {
            image = cached
        } else if let loaded = NSImage(contentsOf: url) {
            imageCache.setObject(loaded, forKey: key)
            image = loaded
        } else {
            image = nil
        }
        guard let image else { return nil }

        var size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // 先按容器宽度缩放到等宽，再按最大高度夹取，保持宽高比。
        if size.width > availableContentWidth {
            let scale = availableContentWidth / size.width
            size = NSSize(width: availableContentWidth, height: size.height * scale)
        }
        if size.height > imageMaxHeight {
            let scale = imageMaxHeight / size.height
            size = NSSize(width: size.width * scale, height: imageMaxHeight)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(origin: .zero, size: size)
        return attachment
    }

    private static func imageParagraphStyle(indent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = imageParagraphSpacing
        style.paragraphSpacing = imageParagraphSpacing
        if indent > 0 {
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        return style
    }

    // MARK: 表格

    /// 把 GFM 表格渲染成对齐的网格文本：先量出各列宽度，把每个单元格的富文本
    /// 折行到所在列的内容宽度内，再逐可视行渲染成段落，用空白附件（见
    /// TableSpacerFactory）把内容推到精确的列位置；网格线与表头底色由
    /// MarkdownTextView 依据行段落上的 TableRowInfo 属性自绘。
    /// 不用制表位/kern（在当前文本引擎下不可靠），也不用 NSTextTable（NSBlock
    /// 表格布局在当前系统的文本引擎下无法成格）；附件宽度是最稳定的占位手段。
    private static func appendTable(header: [MarkdownInline], alignments: [TableAlignment], rows: [[MarkdownInline]], to result: NSMutableAttributedString, indent: CGFloat) {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return }
        // 嵌套缩进（如折叠标题下的表格）忽略：列位置与网格线统一按容器左缘计算。
        let contentWidth = max(40, availableContentWidth)

        func padToColumns(_ cells: [MarkdownInline]) -> [MarkdownInline] {
            var padded = cells
            if padded.count < columnCount {
                padded.append(contentsOf: Array(repeating: [], count: columnCount - padded.count))
            }
            return padded
        }

        let headerFont = NSFont.systemFont(ofSize: DanboMarkdownConfiguration.bodyFontSize, weight: .semibold)
        // 逻辑行的段落间距；折行产生的可视行之间不留段落间距，行距靠 lineSpacing 收紧。
        func lineStyle(spacingBefore: CGFloat, spacing: CGFloat) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = spacing
            return style
        }
        // 行与行之间的留白 = 上单元格底部内边距 + 下单元格顶部内边距，
        // 让分隔线两侧的距离与单元格上下内边距一致；折行产生的中间行不留间距。
        let singleLineStyle = lineStyle(spacingBefore: tableCellTopPadding, spacing: tableCellBottomPadding)
        let firstLineStyle = lineStyle(spacingBefore: tableCellTopPadding, spacing: 0)
        let middleLineStyle = lineStyle(spacingBefore: 0, spacing: 0)
        let lastLineStyle = lineStyle(spacingBefore: 0, spacing: tableCellBottomPadding)

        // 预渲染每个单元格（行内 Markdown 已生效），量出单行实际宽度。
        // GFM 不支持 HTML，单元格里的 `<br>` 等换行标记按普通空白渲染。
        let renderedTable = ([header] + rows).enumerated().map { index, row -> [NSAttributedString] in
            let font = index == 0 ? headerFont : bodyFont
            return padToColumns(row).map {
                inline($0, baseFont: font, color: primaryColor, paragraphStyle: singleLineStyle, htmlBreaksAsSpaces: true)
            }
        }
        let naturalWidths = renderedTable.map { $0.map { $0.size().width } }

        // 列宽：取各列单行宽度最大值；过宽的列封顶，由折行消化，整体超宽时等比压缩。
        let maxColumnWidth = max(24, contentWidth * 0.55)
        var widths = (0..<columnCount).map { column in
            naturalWidths.reduce(24) { max($0, $1[column]) }
        }
        widths = widths.map { min($0, maxColumnWidth) }
        let paddingTotal = CGFloat(columnCount + 1) * tableColumnPadding
        let widthsTotal = widths.reduce(0, +)
        if widthsTotal + paddingTotal > contentWidth, widthsTotal > 0 {
            let scale = max(0, (contentWidth - paddingTotal) / widthsTotal)
            widths = widths.map { max(24, $0 * scale) }
        }

        // edges[i] 为第 i 列左缘 x，末项为表格右缘。
        var edges: [CGFloat] = [0]
        for width in widths {
            edges.append((edges.last ?? 0) + width + 2 * tableColumnPadding)
        }

        // 用表格在整篇文本中的起始位置作 id：同一张表重渲染时 id 稳定（利于相等性比较），
        // 同一篇里内容相同的多张表位置不同，id 也不会撞。
        let tableID = result.length

        // 每个单元格折行到所在列的内容宽度内。
        let wrappedTable = renderedTable.enumerated().map { index, cells -> [[NSAttributedString]] in
            cells.enumerated().map { column, cell in
                wrappedLines(of: cell, maxWidth: max(24, widths[column]))
            }
        }

        func appendRow(_ wrappedCells: [[NSAttributedString]], rowIndex: Int) {
            let visualCount = wrappedCells.map(\.count).max() ?? 1
            for line in 0..<visualCount {
                let style: NSParagraphStyle
                switch (line == 0, line == visualCount - 1) {
                case (true, true): style = singleLineStyle
                case (true, false): style = firstLineStyle
                case (false, true): style = lastLineStyle
                case (false, false): style = middleLineStyle
                }

                let info = TableRowInfo(tableID: tableID, rowIndex: rowIndex, columnEdges: edges)
                let start = result.length
                var pen: CGFloat = 0
                for column in 0..<columnCount {
                    guard line < wrappedCells[column].count else { continue }
                    let cell = wrappedCells[column][line]
                    let columnAlignment = column < alignments.count ? alignments[column] : TableAlignment.left
                    let columnSpan = edges[column + 1] - edges[column]
                    let contentStart = edges[column] + tableColumnPadding
                    let cellWidth = cell.size().width
                    let offset: CGFloat
                    switch columnAlignment {
                    case .left:
                        offset = 0
                    case .center:
                        offset = max(0, (columnSpan - 2 * tableColumnPadding - cellWidth) / 2)
                    case .right:
                        offset = max(0, columnSpan - 2 * tableColumnPadding - cellWidth)
                    }
                    // 目标位置与画笔的差值全部折算到空白附件的占位宽度上
                    //（至少前进 0.5pt：上格内容超宽时允许轻微越界，避免文字互相压住）。
                    let advance = max(0.5, contentStart + offset - pen)
                    // 段落样式必须从段首字符就生效：排版器按段落首字符的样式排版，
                    // 定位附件是每段第一个字符，缺了段落样式整行的行距/段前距都会失效。
                    result.append(NSAttributedString(
                        attachment: TableSpacerFactory.spacer(advance: advance),
                        attributes: [.paragraphStyle: style]
                    ))
                    pen = contentStart + offset
                    let cellStart = result.length
                    result.append(cell)
                    // 折行前预渲染时带的是行间距样式，这里按可视行位置覆盖成正确的段落样式。
                    result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: cellStart, length: result.length - cellStart))
                    pen += cellWidth
                }
                // 段尾换行符同样要带段落样式（含段后距），否则本段与下一段的间距不生效。
                result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
                result.addAttribute(tableRowAttributeKey, value: info, range: NSRange(location: start, length: result.length - start))
            }
        }

        for (rowIndex, wrappedCells) in wrappedTable.enumerated() {
            appendRow(wrappedCells, rowIndex: rowIndex)
        }

        // 表格末尾补一个极小的空段落，承接与后续内容之间的间距。
        let separatorStyle = NSMutableParagraphStyle()
        separatorStyle.paragraphSpacing = blockParagraphSpacing
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 1),
            .paragraphStyle: separatorStyle
        ]))
    }

    /// 把富文本贪心折行到 maxWidth 内：优先在空格处断行，放不下的超长词按字符断开。
    private static func wrappedLines(of attributed: NSAttributedString, maxWidth: CGFloat) -> [NSAttributedString] {
        let ns = attributed.string as NSString
        guard ns.length > 0, maxWidth > 8 else { return [attributed] }
        var lines: [NSAttributedString] = []
        var location = 0
        while location < ns.length {
            let remaining = ns.length - location
            var fit = 0
            var low = 1
            var high = remaining
            while low <= high {
                let mid = (low + high) / 2
                let width = attributed.attributedSubstring(from: NSRange(location: location, length: mid)).size().width
                if width <= maxWidth {
                    fit = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            var lineLength = max(fit, 1)
            if fit > 0, location + fit < ns.length {
                // 断点落在词中间时回退到本行最后一个空格处（空格留在行尾，下面裁掉）。
                let head = NSRange(location: location, length: fit)
                let lastSpace = ns.range(of: " ", options: .backwards, range: head)
                if lastSpace.location != NSNotFound {
                    lineLength = lastSpace.location - location + 1
                }
            }
            let line = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: NSRange(location: location, length: min(lineLength, remaining))))
            while line.length > 0, line.string.hasSuffix(" ") {
                line.deleteCharacters(in: NSRange(location: line.length - 1, length: 1))
            }
            if line.length > 0 {
                lines.append(line)
            }
            location += lineLength
        }
        return lines.isEmpty ? [attributed] : lines
    }

    /// 把裸链接（NSDataDetector 识别出的 URL）补成 .link。
    /// 只在整段都没有链接的位置添加，避免覆盖 Markdown 里显式写出的链接。
    private static func addDetectedLinks(to attributed: NSMutableAttributedString, in range: NSRange) {
        guard let detector = linkDetector, range.length > 0 else { return }
        let plainText = (attributed.string as NSString).substring(with: range)
        let searchRange = NSRange(location: 0, length: (plainText as NSString).length)

        for match in detector.matches(in: plainText, range: searchRange) {
            guard let url = match.url else { continue }
            let target = NSRange(location: range.location + match.range.location, length: match.range.length)
            var hasLink = false
            attributed.enumerateAttribute(.link, in: target, options: []) { value, _, stop in
                guard value != nil else { return }
                hasLink = true
                stop.pointee = true
            }
            if !hasLink {
                attributed.addAttribute(.link, value: url, range: target)
            }
        }
    }

    private static func styleLinks(in attributed: NSMutableAttributedString) {
        attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            guard let url = value as? URL, url.scheme != DanboMarkdownConfiguration.linkScheme else { return }
            attributed.addAttribute(.foregroundColor, value: linkColor, range: range)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            attributed.addAttribute(.underlineColor, value: linkUnderlineColor, range: range)
        }
    }

    /// 去掉末尾多余的换行与空白，并清除最后一个段落的段后间距，避免文本底部出现大块留白。
    private static func trimTrailingWhitespace(in attributed: NSMutableAttributedString) {
        while attributed.length > 0 {
            let string = attributed.string
            if string.hasSuffix("\n") || string.hasSuffix(" ") || string.hasSuffix("\t") {
                attributed.deleteCharacters(in: NSRange(location: attributed.length - 1, length: 1))
            } else {
                break
            }
        }
        guard attributed.length > 0 else { return }
        let nsString = attributed.string as NSString
        let lastNewline = nsString.range(of: "\n", options: .backwards).location
        let lastStart = lastNewline == NSNotFound ? 0 : lastNewline + 1
        let lastRange = NSRange(location: lastStart, length: attributed.length - lastStart)
        attributed.enumerateAttribute(.paragraphStyle, in: lastRange, options: []) { value, range, _ in
            guard let style = value as? NSParagraphStyle else { return }
            let updated = NSMutableParagraphStyle()
            updated.setParagraphStyle(style)
            updated.paragraphSpacing = 0
            attributed.addAttribute(.paragraphStyle, value: updated, range: range)
        }
    }

    private static func headingFont(_ level: Int) -> NSFont {
        .systemFont(ofSize: DanboMarkdownConfiguration.bodyFontSize, weight: .regular)
    }

    private static func paragraphStyle(indent: CGFloat, spacing: CGFloat = blockParagraphSpacing) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = spacing
        if indent > 0 {
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        return style
    }

    private static func headingParagraphStyle(indent: CGFloat, level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        switch level {
        case 1: style.paragraphSpacingBefore = 22
        case 2: style.paragraphSpacingBefore = 16
        case 3: style.paragraphSpacingBefore = 12
        default: style.paragraphSpacingBefore = 8
        }
        style.paragraphSpacing = 8
        if indent > 0 {
            style.firstLineHeadIndent = indent
            style.headIndent = indent
        }
        return style
    }

    private static func listParagraphStyle(indent: CGFloat, markerWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 3
        style.firstLineHeadIndent = indent
        style.headIndent = indent + markerWidth
        return style
    }

    private static func codeParagraphStyle(indent: CGFloat) -> NSParagraphStyle {
        // 代码块内部按等宽编辑器的紧凑排版：行距/段距全部为 0，
        // 空行也只占一个行高；块与上下文之间的间距由首/末段落单独补回。
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent + codeBlockPaddingX
        style.headIndent = indent + codeBlockPaddingX
        style.tailIndent = -codeBlockPaddingX
        return style
    }

    /// 代码块首行的段前距：块级间距只加在第一行，内部行不加。
    private static func setCodeBlockFirstLineSpacing(in attributed: NSMutableAttributedString) {
        let ns = attributed.string as NSString
        let length = ns.length
        guard length > 0 else { return }

        var paragraphEnd = ns.range(of: "\n").location
        if paragraphEnd == NSNotFound { paragraphEnd = length }

        let existing = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let style = NSMutableParagraphStyle()
        if let existing {
            style.setParagraphStyle(existing)
        }
        style.paragraphSpacingBefore = 10
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraphEnd))
    }

    private static func collapseURL(for key: String) -> URL? {
        var components = URLComponents()
        components.scheme = DanboMarkdownConfiguration.linkScheme
        components.host = "collapse"
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        return components.url
    }

    /// 任务行链接：携带任务行在源 Markdown 中的行号（0 起），
    /// 点击后由 MarkdownRenderer 的 onToggleTask 回调翻转该行勾选状态。
    private static func taskURL(forLine line: Int) -> URL? {
        var components = URLComponents()
        components.scheme = DanboMarkdownConfiguration.linkScheme
        components.host = "task"
        components.queryItems = [URLQueryItem(name: "line", value: String(line))]
        return components.url
    }

    /// 任务链接（<linkScheme>://task?line=N）里的源行号；不是任务链接则为 nil。
    static func taskLine(from url: URL) -> Int? {
        guard url.scheme == DanboMarkdownConfiguration.linkScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "task",
              let value = components.queryItems?.first(where: { $0.name == "line" })?.value,
              let line = Int(value) else { return nil }
        return line
    }

    /// 任务行里还没带链接的字符区间（整行挂任务链接时用）。
    /// 先收集再写入：边枚举 `.link` 边改写同一个属性会打乱枚举的范围切分。
    private static func taskLinkRanges(in attributed: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length), options: []) { value, range, _ in
            guard value == nil else { return }
            ranges.append(range)
        }
        return ranges
    }

    private static func applyHighlight(to attributed: NSMutableAttributedString, highlightText: String) {
        let string = attributed.string as NSString
        var searchRange = NSRange(location: 0, length: string.length)
        while true {
            let range = string.range(of: highlightText, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard range.location != NSNotFound else { break }
            attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.55), range: range)
            let next = range.location + range.length
            guard next < string.length else { break }
            searchRange = NSRange(location: next, length: string.length - next)
        }
    }
}

/// 表格行信息：挂在每个表格行段落上，MarkdownTextView 借此画网格线与表头底色。
/// 该属性参与 NSAttributedString 的相等性比较，isEqual/hash 必须按值实现，
/// 否则内容未变时 updateNSView 会误判文本变化而反复重设 textStorage。
final class TableRowInfo: NSObject {
    let tableID: Int
    /// 逻辑行号（单元格自动折行产生的多个可视行同属一个逻辑行）。
    let rowIndex: Int
    /// 列边界 x 坐标（含首列左缘与表格右缘）。
    let columnEdges: [CGFloat]

    init(tableID: Int, rowIndex: Int, columnEdges: [CGFloat]) {
        self.tableID = tableID
        self.rowIndex = rowIndex
        self.columnEdges = columnEdges
        super.init()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TableRowInfo else { return false }
        return tableID == other.tableID && rowIndex == other.rowIndex && columnEdges == other.columnEdges
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(tableID)
        hasher.combine(rowIndex)
        hasher.combine(columnEdges)
        return hasher.finalize()
    }
}

/// 定位用的空白附件工厂：透明占位图 + bounds 提供精确占位宽度，把单元格内容
/// 推到精确的列位置。使用系统自带的 NSTextAttachment（与正文图片同一机制），
/// 不子类化——新 SDK 的文本系统在复制/归档路径上会用 init(data:ofType:) 等
/// 初始化器重建附件，自定义子类在该路径上会崩溃；系统类的实现是完备的。
/// 制表位与 kern 在当前文本引擎下不可靠，附件占位是最稳定的方式。
enum TableSpacerFactory {
    /// 按宽度缓存附件实例：宽度以 0.5pt 粒度归并，避免生成大量重复附件。
    private static var cache: [Int: NSTextAttachment] = [:]

    static func spacer(advance: CGFloat) -> NSTextAttachment {
        let key = Int((max(0.5, advance) * 2).rounded())
        if let cached = cache[key] { return cached }
        let size = NSSize(width: CGFloat(key) / 2, height: 1)
        let blank = NSImage(size: size)
        // 不加任何绘制内容：透明占位，仅按 bounds 占据宽度。
        let attachment = NSTextAttachment()
        attachment.image = blank
        attachment.bounds = NSRect(origin: .zero, size: size)
        cache[key] = attachment
        return attachment
    }
}
