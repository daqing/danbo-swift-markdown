//
//  MarkdownTaskInteractionTests.swift
//  DanboSwiftMarkdownTests
//
//  任务行点击的路由：渲染出的任务链接必须经 clickedOnLink 代理回调到宿主，
//  否则点 checkbox / 行内文字都不会翻转勾选状态。
//

import XCTest
import AppKit
@testable import DanboSwiftMarkdown

final class MarkdownTaskInteractionTests: XCTestCase {
    private func makeCoordinator(
        onToggle: @escaping (String) -> Void = { _ in },
        onToggleTask: @escaping (Int) -> Void
    ) -> MarkdownTextRepresentable.Coordinator {
        MarkdownTextRepresentable.Coordinator(onToggle: onToggle, onToggleTask: onToggleTask)
    }

    private func internalURL(host: String, queryName: String, value: String) throws -> URL {
        var components = URLComponents()
        components.scheme = DanboMarkdownConfiguration.linkScheme
        components.host = host
        components.queryItems = [URLQueryItem(name: queryName, value: value)]
        return try XCTUnwrap(components.url)
    }

    /// 任务链接（<linkScheme>://task?line=…）必须回调宿主，参数是源 Markdown 行号。
    func testClickedTaskLinkReportsSourceLine() throws {
        var toggledLines: [Int] = []
        let coordinator = makeCoordinator { toggledLines.append($0) }

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: try internalURL(host: "task", queryName: "line", value: "7"),
            at: 3
        )

        XCTAssertTrue(handled, "任务链接必须被消费，不能落到 NSWorkspace 去打开")
        XCTAssertEqual(toggledLines, [7])
    }

    /// 非任务链接不能触达任务回调：正文里的外部链接点击仍是打开链接。
    func testClickedExternalLinkDoesNotToggleTask() throws {
        var toggledLines: [Int] = []
        let coordinator = makeCoordinator { toggledLines.append($0) }

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: try XCTUnwrap(URL(string: "https://example.com/docs")),
            at: 0
        )

        XCTAssertFalse(handled)
        XCTAssertTrue(toggledLines.isEmpty)
    }

    /// 折叠标题链接与任务链接共用内部 scheme，必须各走各的回调。
    func testClickedCollapseLinkTogglesSectionOnly() throws {
        var toggledLines: [Int] = []
        var toggledKeys: [String] = []
        let coordinator = makeCoordinator(onToggle: { toggledKeys.append($0) }) {
            toggledLines.append($0)
        }

        let handled = coordinator.textView(
            NSTextView(),
            clickedOnLink: try internalURL(host: "collapse", queryName: "key", value: "标题"),
            at: 0
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(toggledKeys, ["标题"])
        XCTAssertTrue(toggledLines.isEmpty)
    }

    // MARK: - 连击兜底（mouseDown 命中）

    /// 单击之外的连击不再经 clickedOnLink（AppKit 只对单击回调），
    /// mouseDown 必须自己命中任务行并消费，否则「点一次翻转后就再也点不动」。
    func testRepeatedClickOnTaskLineTogglesEveryTime() throws {
        let textView = makeLaidOutTextView(markdown: "- [ ] 第一项待办")
        var toggledLines: [Int] = []
        textView.onToggleTask = { toggledLines.append($0) }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = textView
        let inWindow = textView.convert(try center(of: "第一项待办", in: textView), to: nil)

        for clickCount in [2, 3] {
            textView.mouseDown(with: try XCTUnwrap(mouseEvent(at: inWindow, in: window, clickCount: clickCount)))
        }

        XCTAssertEqual(toggledLines, [0, 0], "连击的每一击都要翻转一次")
    }

    /// 行内文字与 checkbox 都算命中；非任务行（普通段落）不命中，连击落回默认行为。
    func testTaskLineHitTestCoversTextAndMarker() throws {
        let textView = makeLaidOutTextView(markdown: "第一段\n\n- [ ] 第一项待办\n- [x] 第二项已完成\n\n结尾段落")

        XCTAssertEqual(textView.taskLine(at: try center(of: "第一项待办", in: textView)), 2)
        XCTAssertEqual(textView.taskLine(at: try center(of: "☐", in: textView)), 2)
        XCTAssertEqual(textView.taskLine(at: try center(of: "第二项已完成", in: textView)), 3)
        XCTAssertNil(textView.taskLine(at: try center(of: "结尾段落", in: textView)))
    }

    // MARK: - 测试用排版视图

    private func makeLaidOutTextView(markdown: String) -> MarkdownTextView {
        let width: CGFloat = 300
        let textView = MarkdownTextView()
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        MarkdownAttributedBuilder.availableContentWidth = width
        textView.textStorage?.setAttributedString(MarkdownAttributedBuilder.build(
            markdown: markdown,
            collapsedSections: [],
            highlightText: nil,
            taskLinksEnabled: true
        ))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        return textView
    }

    private func center(of text: String, in textView: MarkdownTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let range = (textView.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound, "排版结果里找不到「\(text)」")
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func mouseEvent(at location: NSPoint, in window: NSWindow, clickCount: Int) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: clickCount, pressure: 1
        )
    }
}
