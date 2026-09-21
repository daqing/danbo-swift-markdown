//
//  MarkdownCodeHighlightTests.swift
//  DanboSwiftMarkdownTests
//
//  围栏代码块语法高亮的接入点：有语言标记才着色、卡片底色与代码正文色同源、
//  换配色必须触发重建、以及最要紧的一条——配色绝不影响测高。
//

import XCTest
import AppKit
import DanboSwiftHighlight
@testable import DanboSwiftMarkdown

/// 把动态色按指定外观解析成 sRGB。
///
/// 不包 `performAsCurrentDrawingAppearance` 的话解析结果会跟着本机的系统外观飘，
/// 「深色配色 + 浅色外观」这类组合就测不稳。
private func resolve(_ color: NSColor, as appearanceName: NSAppearance.Name,
                     file: StaticString = #filePath, line: UInt = #line) -> NSColor? {
    guard let appearance = NSAppearance(named: appearanceName) else {
        XCTFail("取不到外观 \(appearanceName.rawValue)", file: file, line: line)
        return nil
    }
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB)
    }
    return resolved
}

private func assertMatches(_ color: NSColor, _ expected: UInt32,
                           _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) {
    guard let resolved = resolve(color, as: .darkAqua, file: file, line: line) else { return }
    let actual = UInt32(resolved.redComponent * 255 + 0.5) << 16
        | UInt32(resolved.greenComponent * 255 + 0.5) << 8
        | UInt32(resolved.blueComponent * 255 + 0.5)
    XCTAssertEqual(actual, expected, message, file: file, line: line)
}

final class MarkdownCodeHighlightTests: XCTestCase {
    private let width: CGFloat = 420

    /// 默认配色是配对配色，明暗各一套。
    private let theme = HighlightTheme.paired("default")!

    private func makeView() -> MarkdownTextView {
        let view = MarkdownTextView()
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        return view
    }

    private func makeCoordinator() -> MarkdownTextRepresentable.Coordinator {
        MarkdownTextRepresentable.Coordinator(onToggle: { _ in }, onToggleTask: nil)
    }

    /// 与生产同源的渲染入口：MarkdownTextRepresentable.render 就是 updateNSView 走的那条路
    ///（`Context` 无法在测试里构造，所以直接调它）。
    @discardableResult
    private func render(_ markdown: String, theme: HighlightTheme?,
                        into view: MarkdownTextView) -> MarkdownTextRepresentable.Coordinator {
        let coordinator = makeCoordinator()
        return render(markdown, theme: theme, into: view, coordinator: coordinator)
    }

    @discardableResult
    private func render(_ markdown: String, theme: HighlightTheme?, into view: MarkdownTextView,
                        coordinator: MarkdownTextRepresentable.Coordinator) -> MarkdownTextRepresentable.Coordinator {
        let representable = MarkdownTextRepresentable(
            markdown: markdown,
            collapsedSections: [],
            highlightText: nil,
            onToggle: { _ in },
            onDoubleClick: nil,
            onToggleTask: nil,
            measuredHeight: .constant(nil),
            skipRenderUntilSized: false,
            highlightTheme: theme
        )
        MarkdownAttributedBuilder.availableContentWidth = width
        representable.render(view, contentWidth: width, coordinator: coordinator)
        return coordinator
    }

    private func foregroundColor(of text: String, in view: MarkdownTextView) throws -> NSColor {
        let storage = try XCTUnwrap(view.textStorage)
        let found = (storage.string as NSString).range(of: text)
        XCTAssertNotEqual(found.location, NSNotFound, "渲染结果里找不到「\(text)」:\n\(storage.string)")
        return try XCTUnwrap(storage.attribute(.foregroundColor, at: found.location, effectiveRange: nil) as? NSColor)
    }

    // MARK: - 着色

    /// 语言标记认得出才着色，且颜色取自配色的槽位而不是随手指定的。
    func testKnownLanguageIsHighlighted() throws {
        let view = makeView()
        render("```swift\nfunc f() {}\n```", theme: theme, into: view)

        let keyword = try foregroundColor(of: "func", in: view)
        assertMatches(keyword, theme.dark[.base0E], "swift 的 func 应取关键字的槽位")

        let plain = try foregroundColor(of: "{}", in: view)
        assertMatches(plain, theme.dark[.base05], "没有 span 的字符用代码正文色")
    }

    /// 没有语言标记就是纯灰代码——这条是承重的：`testCodeKeepsBracketLiteral`
    /// 渲染的就是无语言标记的代码块，凭空着色会破坏它的断言。
    func testMissingOrUnknownLanguageStaysMonochrome() throws {
        // kotlin 不在列表里不是因为它没规则，而是它被有意并进了 java 的规则表
        //（JVM 语言的词法面基本一致），所以这里只用真正认不出的名字。
        for fence in ["```", "```brainfuck", "```  "] {
            let view = makeView()
            render("\(fence)\nif x then\n```", theme: theme, into: view)

            for text in ["if", "then"] {
                let color = try foregroundColor(of: text, in: view)
                assertMatches(color, theme.dark[.base05], "\(fence) 的 \(text) 不应被着色")
            }
        }
    }

    /// 没有主题时属性必须与加高亮之前完全一致：单色等宽、不挂任何 token 色。
    func testNoThemeKeepsTheOriginalMonochromeOutput() throws {
        let view = makeView()
        render("```swift\nfunc f() {}\n```", theme: nil, into: view)

        let storage = try XCTUnwrap(view.textStorage)
        var colored = 0
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let color = value as? NSColor, color === self.theme.color(for: .keyword) { colored += 1 }
        }
        XCTAssertEqual(colored, 0, "没配主题就不该出现 token 色")
        XCTAssertEqual(view.codeBlockCardFill, codeBlockBackgroundFill, "没配主题时卡片用默认底色")
    }

    /// 代码里的 `[Foo]` 仍保持字面：token 着色是叠加属性，不能让
    /// `styleBracketMarkers` 的蓝色标记漏进代码块（它在代码之后才跑）。
    func testBracketMarkerStillSkipsThemedCodeBlocks() throws {
        let markdown = "结尾 [标记]\n\n```swift\nlet a = [block]\n```"
        let view = makeView()
        render(markdown, theme: theme, into: view)

        let marker = try foregroundColor(of: "[标记]", in: view)
        let inCode = try foregroundColor(of: "[block]", in: view)
        XCTAssertNotEqual(inCode, marker, "代码里的 [block] 不应被当成蓝色标记")
    }

    // MARK: - 卡片底色

    /// 卡片底色与代码正文色必须同源（base00 / base05）。混用跟随*外观*的
    /// `labelColor` 时，「深色配色 + 浅色外观」会变成黑字黑底。
    func testCardFillFollowsTheme() throws {
        let view = makeView()
        render("```swift\nfunc f() {}\n```", theme: theme, into: view)

        XCTAssertTrue(view.highlightTheme === theme, "渲染后视图要拿到本次构建的配色")
        XCTAssertTrue(view.codeBlockCardFill === theme.cardFill)
        assertMatches(view.codeBlockCardFill, theme.dark[.base00], "卡片底色取 base00")

        let body = try foregroundColor(of: "func", in: view)
        XCTAssertNotEqual(resolve(body, as: .darkAqua), resolve(view.codeBlockCardFill, as: .darkAqua),
                          "正文与卡片底色不能是同一个色")
    }

    // MARK: - 重建

    /// 换配色不改笔记内容，指纹不带配色就永远不重建，文字上留的还是旧主题那批颜色。
    func testSwitchingThemeRebuildsTheText() throws {
        let view = makeView()
        let markdown = "```swift\nfunc f() {}\n```"
        let coordinator = render(markdown, theme: theme, into: view)
        let before = try foregroundColor(of: "func", in: view)

        let nord = try XCTUnwrap(HighlightTheme.named("nord"))
        render(markdown, theme: nord, into: view, coordinator: coordinator)
        let after = try foregroundColor(of: "func", in: view)

        XCTAssertNotEqual(before, after, "换配色后文字颜色必须跟着变")
        assertMatches(after, nord.dark[.base0E], "换成 nord 后取的是 nord 的关键字色")
        XCTAssertEqual(coordinator.lastRenderKey?.themeID, nord.id)
    }

    /// 输入没变就不重建：往文本里塞一个哨兵字符，同配色的下一次渲染必须原样留着它
    /// （重建会把整段文本替换掉）。这条保证加了指纹维度之后没有变成每帧重建。
    func testSameThemeDoesNotRebuild() throws {
        let view = makeView()
        let markdown = "```swift\nfunc f() {}\n```"
        let coordinator = makeCoordinator()
        render(markdown, theme: theme, into: view, coordinator: coordinator)

        let storage = try XCTUnwrap(view.textStorage)
        storage.append(NSAttributedString(string: "SENTINEL"))

        render(markdown, theme: theme, into: view, coordinator: coordinator)
        XCTAssertTrue(storage.string.contains("SENTINEL"), "输入没变时不该重建文本")
    }

    // MARK: - 测高

    /// 硬约束：配色只改颜色，不改字体——字宽一变，折行与测高就跟着变，而
    /// 代码块与相邻段落的间距（20pt）和「没有行重叠」都是既有测试钉死的。
    /// 这里把「开关高亮后测高逐位相同」机械化，防止将来有人给 token 加粗体或改字号。
    func testThemeDoesNotAffectMeasuredHeight() {
        let markdown = """
        段落一，用于撑出一行正文与代码块之间的间距。

        ```swift
        func greet(_ name: String) -> String {
            return "你好，\\(name)"
        }
        ```

        中间段落。

        ```bash
        if [ $# -lt 2 ]; then
            echo "usage: $0 <a> <b>"
        fi
        ```

        ```python
        def f(x):
            return {"k": x}
        ```

        结尾段落，中文与 emoji 🚀 混排。
        """

        let plain = MarkdownTextMeasurer.height(markdown: markdown, width: width)
        XCTAssertGreaterThan(plain, 0)

        DanboMarkdownConfiguration.highlightTheme = theme
        defer { DanboMarkdownConfiguration.highlightTheme = nil }
        let themed = MarkdownTextMeasurer.height(markdown: markdown, width: width)

        XCTAssertEqual(plain, themed, "开关高亮不得改变任何一个点的测高结果")

        // 光相等还不够：主题要是压根没生效，上面那条也会通过。
        let view = makeView()
        render(markdown, theme: theme, into: view)
        var hasTokenColor = false
        let storage = try? XCTUnwrap(view.textStorage)
        storage?.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage?.length ?? 0)) { value, _, _ in
            if let color = value as? NSColor, color === self.theme.color(for: .keyword) { hasTokenColor = true }
        }
        XCTAssertTrue(hasTokenColor, "测高场景里主题确实生效了，相等才有意义")
    }
}
