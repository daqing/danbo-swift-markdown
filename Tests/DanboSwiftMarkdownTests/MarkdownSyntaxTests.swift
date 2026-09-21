//
//  MarkdownSyntaxTests.swift
//  DanboSwiftMarkdownTests
//
//  解析改用 swift-markdown（CommonMark + GFM）后的语法覆盖：
//  `__Foo__` 与 `**Foo**` 在 AST 里是同一个加粗节点，必须靠源码分隔符区分成绿色/红色强调；
//  任务行的 0 基源行号、GFM 表格的列对齐、行内图片也都由新的解析路径产出。
//

import XCTest
import AppKit
@testable import DanboSwiftMarkdown

final class MarkdownSyntaxTests: XCTestCase {
    private let width: CGFloat = 420

    /// 与生产同源的构建入口；打开任务链接（可写场景才开，见 MarkdownTextView）。
    private func render(_ markdown: String) -> NSAttributedString {
        MarkdownAttributedBuilder.availableContentWidth = width
        return MarkdownAttributedBuilder.build(
            markdown: markdown,
            collapsedSections: [],
            highlightText: nil,
            taskLinksEnabled: true
        )
    }

    private func range(of text: String, in rendered: NSAttributedString) throws -> NSRange {
        let found = (rendered.string as NSString).range(of: text)
        XCTAssertNotEqual(found.location, NSNotFound, "渲染结果里找不到「\(text)」:\n\(rendered.string)")
        return found
    }

    private func foregroundColor(of text: String, in rendered: NSAttributedString) throws -> NSColor {
        let found = try range(of: text, in: rendered)
        return try XCTUnwrap(rendered.attribute(.foregroundColor, at: found.location, effectiveRange: nil) as? NSColor)
    }

    /// `**Foo**` 与 `__Foo__` 必须是两种样式：AST 不保留原始分隔符，
    /// 完全依赖回查源码位置区分，属性对不上就说明绿色强调退化成了普通加粗。
    func testBoldAndGreenEmphasisUseDifferentStyles() throws {
        let rendered = render("普通 **粗体** 与 __绿色__ 并列")

        // 分隔符必须被剥掉，不能留在正文里。
        XCTAssertFalse(rendered.string.contains("**"), "加粗分隔符不应出现在正文:\n\(rendered.string)")
        XCTAssertFalse(rendered.string.contains("__"), "绿色强调分隔符不应出现在正文:\n\(rendered.string)")

        let bold = try foregroundColor(of: "粗体", in: rendered)
        let green = try foregroundColor(of: "绿色", in: rendered)
        let body = try foregroundColor(of: "普通", in: rendered)
        XCTAssertNotEqual(green, bold, "__Foo__ 与 **Foo** 必须是不同的强调样式")

        let boldRGB = try XCTUnwrap(bold.usingColorSpace(.sRGB))
        let greenRGB = try XCTUnwrap(green.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(boldRGB.redComponent, boldRGB.greenComponent, "**Foo** 走红色强调")
        XCTAssertGreaterThan(greenRGB.greenComponent, greenRGB.redComponent, "__Foo__ 走绿色强调")
        XCTAssertNotEqual(greenRGB, try XCTUnwrap(body.usingColorSpace(.sRGB)), "强调色不能与正文同色")
    }

    /// 自定义语法 `[Foo]`：整段（含方括号）蓝色加粗，正文其余部分不受影响。
    func testBracketMarkerRendersBlueAndBold() throws {
        let rendered = render("本期重点 [重要] 收尾")

        let marker = try range(of: "[重要]", in: rendered)
        let markerColor = try foregroundColor(of: "[重要]", in: rendered)
        XCTAssertNotEqual(try foregroundColor(of: "本期重点", in: rendered), markerColor, "正文不应被染成标记色")
        XCTAssertNotEqual(try foregroundColor(of: "收尾", in: rendered), markerColor, "正文不应被染成标记色")

        // 首尾两个方括号也要在标记范围内：整段换色 + 加粗。
        for index in [marker.location, NSMaxRange(marker) - 1] {
            let color = try XCTUnwrap(rendered.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
            XCTAssertEqual(color, markerColor, "整段（含方括号）用同一个强调色")
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent, "[Foo] 走蓝色强调")
            XCTAssertGreaterThan(rgb.blueComponent, rgb.greenComponent, "[Foo] 走蓝色强调")

            let font = try XCTUnwrap(rendered.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
                          "[Foo] 含方括号必须整段加粗")
        }
    }

    /// 标记可能跨行内样式：`[需 **确认**]` 在 AST 里是多个节点，
    /// 蓝色加粗仍要盖住包括方括号在内的整段。
    func testBracketMarkerSpanningInlineStyles() throws {
        let rendered = render("见 [需 **确认**] 的条目")

        let marker = try range(of: "[需 确认]", in: rendered)
        XCTAssertEqual(marker.length, ("[需 确认]" as NSString).length)
        for index in [marker.location, NSMaxRange(marker) - 1] {
            let color = try XCTUnwrap(rendered.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
            let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent, "跨样式的标记也要整段变蓝")
        }
    }

    /// 代码块与行内代码里的方括号保持字面，不能被蓝色标记吃掉。
    func testCodeKeepsBracketLiteral() throws {
        let rendered = render("`[inline]` 与结尾 [标记]\n\n```\n[block]\n```")

        let marker = try range(of: "[标记]", in: rendered)
        let markerColor = try XCTUnwrap(rendered.attribute(.foregroundColor, at: marker.location, effectiveRange: nil) as? NSColor)

        for code in ["[inline]", "[block]"] {
            let found = try range(of: code, in: rendered)
            let color = try XCTUnwrap(rendered.attribute(.foregroundColor, at: found.location, effectiveRange: nil) as? NSColor)
            XCTAssertNotEqual(color, markerColor, "代码里的 \(code) 不应被当成蓝色标记")

            let font = try XCTUnwrap(rendered.attribute(.font, at: found.location, effectiveRange: nil) as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.boldFontMask),
                           "代码里的 \(code) 不应被加粗")
        }
    }

    /// 任务块的 sourceLine 是源 Markdown 的 0 基行号：宿主 onToggleTask 靠它回写
    /// 对应行的勾选状态，差一行就会改错笔记内容。整行（checkbox 与文字）都要挂上
    /// 同一个链接，点行内文字才能同样翻转勾选状态。
    func testTaskSourceLineIsZeroBasedAndPointsAtItsOwnLine() throws {
        let markdown = "# 标题\n\n正文\n- [ ] 第一项\n- [x] 第二项"
        let rendered = render(markdown)

        for (marker, text, expectedLine) in [("☐", "第一项", 3), ("☑", "第二项", 4)] {
            for target in [marker, text] {
                let found = try range(of: target, in: rendered)
                let link = try XCTUnwrap(
                    rendered.attribute(.link, at: found.location, effectiveRange: nil) as? URL,
                    "任务行的「\(target)」必须带可点击的任务链接"
                )
                XCTAssertEqual(queryValue(named: "line", in: link), String(expectedLine),
                               "任务行的「\(target)」应回写源 Markdown 的第 \(expectedLine) 行（0 基）")
            }
        }
    }

    /// 任务行整行可点，但行内自带的链接不能被任务链接覆盖：点了还是打开原链接。
    func testTaskLineKeepsItsOwnInlineLink() throws {
        let rendered = render("- [ ] 读 [文档](https://example.com/docs) 并归档")

        let linkRange = try range(of: "文档", in: rendered)
        let link = try XCTUnwrap(rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.absoluteString, "https://example.com/docs", "行内链接必须保留自己的 URL")

        let textRange = try range(of: "归档", in: rendered)
        let taskLink = try XCTUnwrap(rendered.attribute(.link, at: textRange.location, effectiveRange: nil) as? URL)
        XCTAssertEqual(taskLink.host, "task", "链接之外的文字仍是任务链接")
    }

    /// GFM 表格：表头与数据行都渲染出来，且分隔行只用于声明对齐、不能落进正文。
    func testTableRendersHeaderAndBodyWithoutSeparatorRow() throws {
        let rendered = render("| 项目 | 说明 |\n| --- | --- |\n| 甲 | 乙 |")

        for text in ["项目", "说明", "甲", "乙"] {
            _ = try range(of: text, in: rendered)
        }
        XCTAssertFalse(rendered.string.contains("---"), "分隔行不应出现在正文里:\n\(rendered.string)")
    }

    /// 分隔行冒号声明的列对齐必须一路传到排版：右对齐的列前面要垫更多空白，
    /// 同一段内容排出来更宽（内容整体右移）。
    func testTableColumnAlignmentReachesLayout() throws {
        let columnHeader = "表头文字比较长"
        let left = MarkdownTextMeasurer.debugLineLayout(
            markdown: "| \(columnHeader) |\n| :--- |\n| a |", width: width
        )
        let right = MarkdownTextMeasurer.debugLineLayout(
            markdown: "| \(columnHeader) |\n| ---: |\n| a |", width: width
        )

        let leftWidth = try bodyRowWidth(in: left)
        let rightWidth = try bodyRowWidth(in: right)
        XCTAssertGreaterThan(rightWidth, leftWidth,
                             "「---:」声明的右对齐列必须比「:---」左对齐列更靠右:\n\(right)")
    }

    /// 行内图片解析成附件渲染，而不是把 `![](…)` 原样当文本吐出来；
    /// 图片加载失败时回退 alt 文本，保证内容不凭空消失。
    func testInlineImageBecomesAttachmentAndFallsBackToAltText() throws {
        let imageURL = try makeTestImageFile()
        let rendered = render("前 ![示意图](\(imageURL.absoluteString)) 后")

        _ = try range(of: "前", in: rendered)
        _ = try range(of: "后", in: rendered)
        XCTAssertFalse(rendered.string.contains("!["), "图片语法不应原样出现在正文:\n\(rendered.string)")

        let attachment = try XCTUnwrap(firstImageAttachment(in: rendered), "行内图片应渲染成附件")
        XCTAssertGreaterThan(attachment.bounds.width, 0)
        XCTAssertGreaterThan(attachment.bounds.height, 0)

        let broken = render("前 ![图](https://example.invalid/nope.png) 后")
        _ = try range(of: "图", in: broken)
        XCTAssertNil(firstImageAttachment(in: broken), "加载失败的图片不应留下空附件")
    }

    /// 代码块 + 表格 + 行内图片混排的冒烟回归：换成 AST 解析后行布局不得出现纵向重叠。
    func testMixedNoteHasNoOverlappingLines() throws {
        let imageURL = try makeTestImageFile()
        let note = """
        混排样例

        ```
        幫我根據
          docs/design/collocation/seizou/in_seizou_etl_m_center_products.md
        ```

        | 项目 | 说明 |
        | :--- | ---: |
        | 甲 | 乙 |

        行内图片 ![示意图](\(imageURL.absoluteString)) 收尾
        """

        let report = MarkdownTextMeasurer.debugLineLayout(markdown: note, width: 528)
        print(report)
        XCTAssertFalse(report.contains("OVERLAP"), "行布局发生重叠:\n\(report)")
    }

    // MARK: 辅助

    private func queryValue(named name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    /// 从 debugLineLayout 报告里取表格数据行（内容为 "a" 的那一行，行首的占位附件
    /// 在文本里是 U+FFFC）的行宽。
    private func bodyRowWidth(in report: String) throws -> Double {
        for line in report.split(separator: "\n") where line.hasPrefix("y=") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, parts[1].hasSuffix("a") else { continue }
            let widthField = parts[0].split(separator: " ").first { $0.hasPrefix("w=") }
            return try XCTUnwrap(widthField.flatMap { Double($0.dropFirst(2)) }, "报告行缺少宽度字段:\n\(report)")
        }
        XCTFail("布局报告里找不到表格数据行:\n\(report)")
        return 0
    }

    private func firstImageAttachment(in rendered: NSAttributedString) -> NSTextAttachment? {
        var found: NSTextAttachment?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length), options: []) { value, _, stop in
            guard let attachment = value as? NSTextAttachment, attachment.image != nil else { return }
            found = attachment
            stop.pointee = true
        }
        return found
    }

    /// 生成 40×20 的小测试图：窄于任何测高宽度，不会触发按容器缩放。
    private func makeTestImageFile() throws -> URL {
        let pixelsWide = 40
        let pixelsHigh = 20
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()

        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("danbonote-syntax-test-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }
}
