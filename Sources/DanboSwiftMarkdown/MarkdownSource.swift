//
//  MarkdownSource.swift
//  swift-markdown
//

import Foundation
import Markdown

/// 源 Markdown 的行索引：把 swift-markdown 的 (行, 列) 源码位置换算成文本。
///
/// AST 不保留原始分隔符（`**x**` 与 `__x__` 解析出的节点完全相同），自定义的绿色强调
/// 只能回查源串才能与加粗区分，见 MarkdownAttributedBuilder.isGreenStrong。
struct MarkdownSource {
    private let source: String
    /// 每一行（0 基）起始处的 UTF-8 字节偏移。
    private let lineStarts: [Int]

    init(_ source: String) {
        self.source = source
        var starts: [Int] = [0]
        var offset = 0
        for byte in source.utf8 {
            offset += 1
            if byte == UInt8(ascii: "\n") {
                starts.append(offset)
            }
        }
        self.lineStarts = starts
    }

    /// 源码位置处是否以 prefix 开头；位置越界或前缀不匹配时返回 false。
    func hasPrefix(_ prefix: String, at location: SourceLocation) -> Bool {
        guard let text = text(at: location, utf8Count: prefix.utf8.count) else { return false }
        return text == prefix
    }

    /// 取源码位置起 utf8Count 个字节的文本。SourceLocation 的行、列都是 1 基，
    /// 且列是行内的 **UTF-8 字节** 偏移，因此全程按字节换算。
    private func text(at location: SourceLocation, utf8Count: Int) -> String? {
        let lineIndex = location.line - 1
        guard lineIndex >= 0, lineIndex < lineStarts.count, location.column >= 1 else { return nil }

        let utf8 = source.utf8
        let startOffset = lineStarts[lineIndex] + location.column - 1
        guard startOffset >= 0, startOffset <= utf8.count else { return nil }

        let start = utf8.index(utf8.startIndex, offsetBy: startOffset)
        guard let end = utf8.index(start, offsetBy: utf8Count, limitedBy: utf8.endIndex) else { return nil }
        return String(utf8[start..<end])
    }
}
