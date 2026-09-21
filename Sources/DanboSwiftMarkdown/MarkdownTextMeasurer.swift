//
//  MarkdownTextMeasurer.swift
//  swift-markdown
//

import AppKit

/// 供回归测试使用的测高入口：与行内渲染完全同源——同一个 MarkdownTextView 配置、
/// 同一个 MarkdownAttributedBuilder 构建、同一套「替换内容 → invalidateIntrinsicContentSize
/// → ensureLayout 重测」流程（对应 MarkdownTextRepresentable.updateNSView / sizeThatFits）。
/// 「笔记编辑保存成多行后行高必须跟着长」的契约由此在单元测试中固定下来；
/// SwiftUI 侧不缓存测高结果则由 sizeThatFits 实现与 fixedSize 修饰保证。
public enum MarkdownTextMeasurer {
    /// 便捷入口：新建文本视图只渲染一个内容并测高。
    public static func height(markdown: String, width: CGFloat) -> CGFloat {
        height([(markdown: markdown, width: width)])
    }

    /// 回归测试/调试入口：渲染 markdown 后枚举全部 line fragment 的几何与文本，
    /// 相邻行纵向重叠时标注 OVERLAP（代码块卡片与段落重叠类 bug 的无窗口复现）。
    public static func debugLineLayout(markdown: String, width: CGFloat) -> String {
        let view = MarkdownTextView()
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        MarkdownAttributedBuilder.availableContentWidth = width
        let attributed = MarkdownAttributedBuilder.build(
            markdown: markdown,
            collapsedSections: [],
            highlightText: nil
        )
        view.textStorage?.setAttributedString(attributed)
        guard let layoutManager = view.layoutManager,
              let textContainer = view.textContainer,
              let storage = view.textStorage else { return "(no layout)" }
        layoutManager.ensureLayout(for: textContainer)

        var lines: [String] = []
        var previous: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { _, usedRect, _, glyphRange, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let text = (storage.string as NSString)
                .substring(with: charRange)
                .replacingOccurrences(of: "\n", with: "\\n")
            let isCode = storage.attribute(codeBlockBackgroundAttributeKey, at: charRange.location, effectiveRange: nil) != nil
            lines.append(String(
                format: "y=%.1f h=%.1f x=%.1f w=%.1f %@ | %@",
                usedRect.minY, usedRect.height, usedRect.minX, usedRect.width,
                isCode ? "CODE" : "text", text
            ))
            if let previous, usedRect.minY < previous.maxY - 0.5 {
                lines.append("OVERLAP: 本行与上一行纵向重叠")
            }
            previous = usedRect
        }
        return lines.joined(separator: "\n")
    }

    /// 新建一个文本视图，依次渲染 markdowns（模拟「单行笔记 → 编辑成多行 → 保存」的
    /// 原地改写链路），返回渲染完最后一个内容后的完整布局高度。
    public static func height(markdowns: [String], width: CGFloat) -> CGFloat {
        height(markdowns.map { (markdown: $0, width: width) })
    }

    /// 每步用各自的宽度渲染同一个文本视图（模拟「按宽度 A 构建 → 放进宽度 B 布局」
    /// 的跨宽度链路，对应生产 updateNSView / sizeThatFits），返回最终布局高度。
    public static func height(_ steps: [(markdown: String, width: CGFloat)]) -> CGFloat {
        let view = MarkdownTextView()
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        // 无窗口环境下文本视图 bounds 为 0，宽度跟踪会把容器宽度同步成 0，
        // 导致任何文字都排不下（测高恒为 0）。这里与 sizeThatFits 一样
        // 用显式容器宽度测量；生产视图的宽度由 SwiftUI frame 提供，不受影响。
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        let lastWidth = steps.last?.width ?? 1
        view.textContainer?.containerSize = NSSize(width: max(1, lastWidth), height: CGFloat.greatestFiniteMagnitude)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        for step in steps {
            // 与 updateNSView / renderIfChanged 一致：构建前写入构建宽度、重建富文本、
            // 整体替换、失效测高。
            if step.width > 0 {
                MarkdownAttributedBuilder.availableContentWidth = step.width
            }
            let attributed = MarkdownAttributedBuilder.build(
                markdown: step.markdown,
                collapsedSections: [],
                highlightText: nil
            )
            view.textStorage?.setAttributedString(attributed)
            view.invalidateIntrinsicContentSize()
        }

        guard let layoutManager = view.layoutManager, let textContainer = view.textContainer else {
            return 0
        }
        layoutManager.ensureLayout(for: textContainer)
        // 用 intrinsicContentSize 而不是裸 usedRect：代码块结尾的笔记要把卡片
        // 向下外扩的 padding 也算进高度（见 MarkdownTextView.intrinsicContentSize）。
        return view.intrinsicContentSize.height
    }
}
