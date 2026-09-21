//
//  MarkdownRowHeightTests.swift
//  DanboSwiftMarkdownTests
//
//  回归测试：笔记「先创建单行内容，再编辑成多行保存」后，行高必须跟着内容增长，
//  否则多出的正文会被旧行高裁掉 / 被下一张笔记卡片挡住（MarkdownRenderer 的
//  NSTextView 测高契约，见 Sources/DanboSwiftMarkdown 的 MarkdownTextMeasurer）。
//

import XCTest
import AppKit
import DanboSwiftMarkdown

final class MarkdownRowHeightTests: XCTestCase {
    private let width: CGFloat = 320
    private let singleLine = "单行内容"
    private let multiLine = "第一行\n第二行\n第三行\n第四行\n第五行"

    /// 历史 bug 场景：同一个文本视图先渲染单行，再原地改写成多行（编辑保存），
    /// 测高必须反映新内容，而不是停留在首次测量的旧行高。
    func testHeightGrowsWhenContentChangesFromSingleLineToMultiLine() {
        let beforeRewrite = MarkdownTextMeasurer.height(markdown: singleLine, width: width)
        let afterRewrite = MarkdownTextMeasurer.height(markdowns: [singleLine, multiLine], width: width)

        // 五行文本的高度必须明显高于单行（行高随内容增长，不允许沿用旧值）。
        XCTAssertGreaterThan(afterRewrite, beforeRewrite * 2,
                             "编辑成多行后测高应显著增长，旧行高会把多出的正文裁掉")
    }

    /// 原地改写后的测高必须与全新渲染同一内容的结果一致：不允许存在陈旧的缓存高度。
    func testRewrittenHeightMatchesFreshMeasurement() {
        let afterRewrite = MarkdownTextMeasurer.height(markdowns: [singleLine, multiLine], width: width)
        let fresh = MarkdownTextMeasurer.height(markdown: multiLine, width: width)

        XCTAssertEqual(afterRewrite, fresh, accuracy: 0.5,
                       "改写内容后测高必须与全新渲染一致，否则行内显示与实际高度不符")
    }

    /// 反方向同理：多行改回单行后，高度也要缩回去，避免留下大块空白或遮挡布局。
    func testHeightShrinksWhenContentChangesBackToSingleLine() {
        let beforeRewrite = MarkdownTextMeasurer.height(markdown: multiLine, width: width)
        let afterRewrite = MarkdownTextMeasurer.height(markdowns: [multiLine, singleLine], width: width)
        let fresh = MarkdownTextMeasurer.height(markdown: singleLine, width: width)

        XCTAssertLessThan(afterRewrite, beforeRewrite * 0.6,
                          "改回单行后测高应明显回落")
        XCTAssertEqual(afterRewrite, fresh, accuracy: 0.5,
                       "改回单行后的测高必须与全新渲染一致")
    }

    /// 多行内容在任何宽度下都不允许被量成单行高度（宽度折叠只影响折行数，不丢行）。
    func testMultiLineHeightStaysAboveSingleLineAtVariousWidths() {
        let single = MarkdownTextMeasurer.height(markdown: singleLine, width: width)

        for narrowWidth in stride(from: CGFloat(120), through: 400, by: 40) {
            let multi = MarkdownTextMeasurer.height(markdown: multiLine, width: narrowWidth)
            XCTAssertGreaterThan(multi, single * 2,
                                 "宽度 \(narrowWidth) 下多行内容测高不得塌缩成单行高度")
        }
    }

    /// 超长单行在窄容器里折行后高度必须增长：测高走的是真实布局结果，
    /// 保证按宽度折行的正文（不需要手动换行）也能撑开行高。
    func testLongLineWrapsAndGrowsHeightInNarrowContainer() {
        let longLine = String(repeating: "很长的一段文字内容", count: 12)

        let wide = MarkdownTextMeasurer.height(markdown: longLine, width: 640)
        let narrow = MarkdownTextMeasurer.height(markdown: longLine, width: 160)

        XCTAssertGreaterThan(narrow, wide,
                             "同一内容在更窄的容器里折行更多，测高必须随之增长")
    }

    /// 空内容不允许撑出正文高度：空文本存储会保留一个默认行高（实测 14pt，
    /// NSTextView 固有行为，生产同样如此），只要不超过一行正文高度即可。
    func testEmptyAndBlankContentMeasureNearZero() {
        let bodyLineHeight = MarkdownTextMeasurer.height(markdown: singleLine, width: width)

        XCTAssertLessThanOrEqual(MarkdownTextMeasurer.height(markdown: "", width: width), bodyLineHeight)
        XCTAssertLessThanOrEqual(MarkdownTextMeasurer.height(markdown: "  \n \n ", width: width), bodyLineHeight)
    }

    /// 置顶页内容被截断的场景：视图初次渲染时按其它实例遗留的宽度构建（生产中此时
    /// bounds 还没量出来），随后放进真实容器宽度布局。内容必须按真实宽度重新排版：
    /// 表格列宽、图片尺寸若停留在构建时的宽度，会横向溢出被裁且指纹不变不再重建。
    func testCrossWidthLayoutMatchesFreshRender() {
        let longCell = String(repeating: "很长的单元格内容", count: 8)
        let table = "| 项目 | 说明 |\n| --- | --- |\n| \(longCell) | 备注 |"

        // 先按宽容器 600 构建、再按窄容器 220 布局，结果必须与直接按 220 全新渲染
        // 一致（窄容器列宽封顶更低，折行更多、更高）。
        let freshNarrow = MarkdownTextMeasurer.height(markdown: table, width: 220)
        let crossNarrow = MarkdownTextMeasurer.height([
            (markdown: table, width: 600),
            (markdown: table, width: 220)
        ])
        XCTAssertEqual(crossNarrow, freshNarrow, accuracy: 0.5,
                       "按遗留宽度构建、真实宽度布局，必须等价于按真实宽度全新渲染")

        // 反方向同理：先窄后宽，宽容器下列宽上限更高、折行更少、高度回落。
        let freshWide = MarkdownTextMeasurer.height(markdown: table, width: 600)
        let crossWide = MarkdownTextMeasurer.height([
            (markdown: table, width: 220),
            (markdown: table, width: 600)
        ])
        XCTAssertEqual(crossWide, freshWide, accuracy: 0.5,
                       "跨宽度布局必须按新宽度重建，而不是沿用窄容器排版")
        XCTAssertLessThan(crossWide, crossNarrow,
                          "同一表格在宽容器下的排版高度应明显小于窄容器")
    }

    /// 图片路径的独立覆盖：附件缩放与表格一样在构建期读取可用宽度，跨宽度重建后
    /// 必须按真实宽度重新缩放，而不是停留在构建时的尺寸（在窄容器里横向溢出被裁）。
    func testImageCrossWidthLayoutMatchesFreshRender() throws {
        let imageURL = try makeWideImageFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        let note = "![示意图](\(imageURL.absoluteString))"

        // 前提断言：宽图按容器宽度等比缩放，宽窄容器下显示高度不同。
        let freshWide = MarkdownTextMeasurer.height(markdown: note, width: 600)
        let freshNarrow = MarkdownTextMeasurer.height(markdown: note, width: 220)
        XCTAssertGreaterThan(freshWide, freshNarrow,
                             "宽图在窄容器里缩放后应更矮；此前提失败说明图片缩放未生效")

        XCTAssertEqual(
            MarkdownTextMeasurer.height([
                (markdown: note, width: 600),
                (markdown: note, width: 220)
            ]),
            freshNarrow, accuracy: 0.5,
            "按遗留宽度构建、真实宽度布局：图片必须按真实宽度重建缩放"
        )
        XCTAssertEqual(
            MarkdownTextMeasurer.height([
                (markdown: note, width: 220),
                (markdown: note, width: 600)
            ]),
            freshWide, accuracy: 0.5,
            "跨宽度布局必须按新宽度重建，而不是沿用窄容器的附件尺寸"
        )
    }

    /// 回归：段落夹在两个代码块之间时，各行不得纵向重叠
    /// （draw.io 提示词笔记的「段落与代码块卡片重叠」bug 的无窗口复现）。
    func testParagraphBetweenCodeBlocksDoesNotOverlap() {
        let note = """
        生成 draw.io 流程图的提示词

        ```
        幫我根據
          docs/design/collocation/seizou/in_seizou_etl_m_center_products.md
          生成draw.io兼容的diagram (.drawio文件)，可以讓我導入draw.io后，手動生成路程圖並導出
        ```

        生成的文件在

        ```
         docs/design/collocation/seizou/imgs/in_seizou_etl_m_center_products.drawio
        ```
        """

        let report = MarkdownTextMeasurer.debugLineLayout(markdown: note, width: 528)
        print(report)
        XCTAssertFalse(report.contains("OVERLAP"), "行布局发生重叠:\n\(report)")

        // 代码块卡片自带 8pt 下 padding，块尾若没有段后间距，卡片会盖住下一段文字。
        // 段后间距必须加在代码块最后一行，而不是中间的某一行。
        struct LayoutLine { let y: Double; let maxY: Double; let isCode: Bool; let text: String }
        let layoutLines: [LayoutLine] = report.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("y=") else { return nil }
            let parts = line.split(separator: "|", maxSplits: 1)
            let fields = parts[0].split(separator: " ")
            guard fields.count == 5,
                  let y = Double(fields[0].dropFirst(2)),
                  let h = Double(fields[1].dropFirst(2)) else { return nil }
            return LayoutLine(y: y, maxY: y + h, isCode: fields[4] == "CODE", text: String(parts[1]))
        }
        // 「生成的文件在」与上方代码块末行之间要有 20pt 段后间距。
        if let paragraphIndex = layoutLines.firstIndex(where: { $0.text.contains("生成的文件在") }), paragraphIndex > 0 {
            let gap = layoutLines[paragraphIndex].y - layoutLines[paragraphIndex - 1].maxY
            XCTAssertEqual(gap, 20, accuracy: 0.5, "代码块末行缺少段后间距:\n\(report)")
        } else {
            XCTFail("布局中找不到「生成的文件在」段落:\n\(report)")
        }
        // 代码块内部行间保持紧凑（间距为 0），不允许间距落在块中间。
        for (previous, current) in zip(layoutLines, layoutLines.dropFirst()) where previous.isCode && current.isCode {
            XCTAssertEqual(current.y - previous.maxY, 0, accuracy: 0.5, "代码块内部出现多余间距:\n\(report)")
        }

        // 笔记以代码块结尾时，测高必须包含卡片向下外扩的 8pt padding，
        // 否则行高不够、卡片底边被裁掉。
        let measured = MarkdownTextMeasurer.height(markdown: note, width: 528)
        let lastLineBottom = layoutLines.map(\.maxY).max() ?? 0
        XCTAssertGreaterThanOrEqual(measured, lastLineBottom + 8 - 0.5, "测高未包含代码块卡片的底部 padding:\n\(report)")
    }

    /// 生成 1200×80 的宽测试图：宽于全部测高宽度，确保命中「超宽图片按容器缩放」分支。
    private func makeWideImageFile() throws -> URL {
        let pixelsWide = 1200
        let pixelsHigh = 80
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
            .appendingPathComponent("danbonote-rowheight-test-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }
}
