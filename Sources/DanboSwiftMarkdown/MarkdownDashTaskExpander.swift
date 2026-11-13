//
//  MarkdownDashTaskExpander.swift
//  swift-markdown
//

import Foundation
import Markdown

/// `-- ` 简写任务行：`-- 内容` 等价于 GFM 的 `- [ ] 内容`（恒为未完成），只是更好写。
///
/// swift-markdown/cmark 不认识这种写法，这里在解析前把简写行逐行改写成标准任务行：
/// 行数与其它行的内容都保持不变，任务行的 sourceLine 与勾选回写仍指回源 Markdown 的
/// 原行。改写是幂等的（标准写法不再匹配简写模式），重复展开不会叠加。
/// 依赖解析侧关闭智能标点（`.disableSmartOpts`），否则 `--` 会被改写成印刷体破折号。
enum MarkdownDashTaskExpander {
    /// 返回展开后的 Markdown；没有可展开的行时原样返回（不触发任何解析）。
    static func expand(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        // 快路径：连候选行（含代码块里的）都没有，就不必再请出解析器。
        guard lines.contains(where: { expandedLine($0) != nil }) else { return markdown }

        // 用 cmark 对原始文本的解析结果圈出「按字面渲染」的行，让解析器自己判定
        // 哪些 `-- ` 只是普通字符，而不是手写围栏状态机——列表/引用里嵌套代码块的
        // 缩进规则很容易写错，错了会悄悄改坏代码块内容。
        var protectedLines = Set<Int>()
        collectLiteralLines(in: Document(parsing: markdown, options: [.disableSmartOpts]), into: &protectedLines)

        var result = lines
        for index in result.indices where !protectedLines.contains(index) {
            result[index] = expandedLine(lines[index]) ?? lines[index]
        }
        return result.joined(separator: "\n")
    }

    /// 单行改写：行首（≤3 空格缩进）的 `-- <内容>` → `- [ ] <内容>`；不是简写行返回 nil。
    ///
    /// 与 GFM 任务行同规则：`--` 后要有一个空白作分隔，且其后要有非空白内容。
    /// 光杆 `--`（或后面只有空白）可能是 setext 二级标题的下划线，`---` 是分隔线，
    /// `--x` 没有分隔空白，都不能动；4 个以上空格的缩进是代码块，也不改写。
    private static func expandedLine(_ line: String) -> String? {
        var index = line.startIndex
        var indent = 0
        while index < line.endIndex, line[index] == " " {
            indent += 1
            if indent > 3 { return nil }
            index = line.index(after: index)
        }
        guard line[index...].hasPrefix("--") else { return nil }
        let separator = line.index(index, offsetBy: 2)
        guard separator < line.endIndex, line[separator] == " " || line[separator] == "\t" else { return nil }
        let content = line[line.index(after: separator)...]
        guard content.contains(where: { !$0.isWhitespace }) else { return nil }
        return String(line[..<index]) + "- [ ] " + String(content)
    }

    /// 收集「按源码字面渲染」的节点所覆盖的行（0 基，两端都算）：代码块（围栏与
    /// 缩进都算）、HTML 块、行内代码、行内 HTML——它们的文本会原样出现在渲染
    /// 结果里，改写会直接改变所见内容。
    private static func collectLiteralLines(in markup: Markup, into lines: inout Set<Int>) {
        if markup is CodeBlock || markup is HTMLBlock || markup is InlineCode || markup is InlineHTML,
           let range = markup.range {
            for line in range.lowerBound.line...range.upperBound.line {
                lines.insert(line - 1)
            }
        }
        for child in markup.children {
            collectLiteralLines(in: child, into: &lines)
        }
    }
}
