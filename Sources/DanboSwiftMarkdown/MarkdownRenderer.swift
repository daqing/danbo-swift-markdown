//
//  MarkdownRenderer.swift
//  swift-markdown
//

import SwiftUI
import AppKit
import DanboSwiftHighlight

/// A native Markdown renderer that keeps Markdown semantics (links, emphasis,
/// strikethrough and inline code) while adding layout for common block types.
public struct MarkdownCollapseRequest: Equatable {
    public let token: Int
    public let collapseAll: Bool

    public init(token: Int, collapseAll: Bool) {
        self.token = token
        self.collapseAll = collapseAll
    }
}

public struct MarkdownRenderer: View {
    public let markdown: String
    public var highlightText: String? = nil
    public var collapseRequest: MarkdownCollapseRequest? = nil
    public var onDoubleClick: (() -> Void)? = nil
    /// 任务行点击回调（参数为源 Markdown 行号）：点击 checkbox 或该行文字都触发；
    /// nil 时任务行渲染为纯文本。
    public var onToggleTask: ((Int) -> Void)? = nil
    /// 正文排版高度回写（全文高度，与展示层裁剪无关）；nil 表示不关心。
    public var onMeasuredHeight: ((CGFloat) -> Void)? = nil
    /// 首次布局前的已知排版高度（与展示层裁剪无关）：非 nil 时作为初始行高钉住，
    /// 避免首帧按零高布局、测高异步回写后再增高引发的布局竞争（独立笔记窗口传入）。
    public var initialMeasuredHeight: CGFloat? = nil
    /// 延迟首次渲染直到视图有真实宽度：首帧 bounds 为 0 时容器宽度也是 0，此时用
    /// 共享静态宽度渲染会与容器宽度矛盾（重折行后代码块卡片等错位重叠）。开启后
    /// 跳过零宽渲染，由 sizeThatFits 按真实宽度排期唯一一次渲染（独立笔记窗口用）。
    public var skipRenderUntilSized: Bool = false

    /// 围栏代码块的高亮配色。nil 时用 `DanboMarkdownConfiguration.highlightTheme`
    /// （两者都为空即不着色）。配色只改颜色、不改字体，所以不影响测高。
    public var highlightTheme: HighlightTheme? = nil

    /// 文本实际排版高度，由 MarkdownTextView 布局后写回。用显式 frame 钉住行高：
    /// SwiftUI 对 NSViewRepresentable 的 sizeThatFits 结果可能不再重询（首屏批量
    /// 插入、滚动条出现收窄内容宽度等时序下，文本按更窄宽度重新折行变高），
    /// 此时文本视图仍按旧行高摆放，末行被卡片底边裁掉。写回实际高度可强制纠正。
    @State private var measuredHeight: CGFloat?

    @State private var collapsedSections: Set<String> = []

    public init(
        markdown: String,
        highlightText: String? = nil,
        collapseRequest: MarkdownCollapseRequest? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onToggleTask: ((Int) -> Void)? = nil,
        onMeasuredHeight: ((CGFloat) -> Void)? = nil,
        initialMeasuredHeight: CGFloat? = nil,
        skipRenderUntilSized: Bool = false,
        highlightTheme: HighlightTheme? = nil
    ) {
        self.markdown = markdown
        self.highlightText = highlightText
        self.collapseRequest = collapseRequest
        self.onDoubleClick = onDoubleClick
        self.onToggleTask = onToggleTask
        self.onMeasuredHeight = onMeasuredHeight
        self._measuredHeight = State(initialValue: initialMeasuredHeight)
        self.skipRenderUntilSized = skipRenderUntilSized
        self.highlightTheme = highlightTheme
    }

    public var body: some View {
        MarkdownTextRepresentable(
            markdown: markdown,
            collapsedSections: collapsedSections,
            highlightText: highlightText,
            onToggle: { toggle($0) },
            onDoubleClick: onDoubleClick,
            onToggleTask: onToggleTask,
            measuredHeight: $measuredHeight,
            skipRenderUntilSized: skipRenderUntilSized,
            highlightTheme: highlightTheme
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: measuredHeight)
        .onChange(of: collapseRequest) { _, request in
            guard let request else { return }
            apply(request)
        }
        .onChange(of: measuredHeight) { _, height in
            guard let height else { return }
            onMeasuredHeight?(height)
        }
    }

    private func toggle(_ key: String) {
        if collapsedSections.contains(key) {
            collapsedSections.remove(key)
        } else {
            collapsedSections.insert(key)
        }
    }

    private func apply(_ request: MarkdownCollapseRequest) {
        if request.collapseAll {
            collapsedSections = Set(MarkdownSectionParser.collapseKeys(markdown))
        } else {
            collapsedSections = []
        }
    }
}

struct MarkdownTextRepresentable: NSViewRepresentable {
    let markdown: String
    let collapsedSections: Set<String>
    let highlightText: String?
    let onToggle: (String) -> Void
    let onDoubleClick: (() -> Void)?
    /// 任务行点击回调（参数为源 Markdown 行号）；nil 时任务行渲染为纯文本。
    let onToggleTask: ((Int) -> Void)?
    /// 文本实际排版高度的回写通道，见 MarkdownRenderer.measuredHeight。
    @Binding var measuredHeight: CGFloat?
    /// 延迟首次渲染直到有真实宽度，见 MarkdownRenderer.skipRenderUntilSized。
    let skipRenderUntilSized: Bool
    /// 代码块配色，nil 时用全局配置，见 MarkdownRenderer.highlightTheme。
    let highlightTheme: HighlightTheme?

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggle: onToggle, onToggleTask: onToggleTask)
    }

    func makeNSView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onToggleCollapse = onToggle
        textView.onToggleTask = onToggleTask
        textView.onDoubleClick = onDoubleClick
        return textView
    }

    func updateNSView(_ textView: MarkdownTextView, context: Context) {
        context.coordinator.onToggle = onToggle
        context.coordinator.onToggleTask = onToggleTask
        textView.onToggleCollapse = onToggle
        textView.onToggleTask = onToggleTask
        textView.onDoubleClick = onDoubleClick
        // 排版高度变化时回写 SwiftUI 的显式高度（异步：布局回调里同步改 state
        // 会触发 "Modifying state during view update"）。
        textView.onLayoutHeightChanged = { [heightBinding = $measuredHeight] height in
            DispatchQueue.main.async {
                guard heightBinding.wrappedValue == nil
                    || abs(heightBinding.wrappedValue! - height) > 0.5 else { return }
                heightBinding.wrappedValue = height
            }
        }
        // 视图已有实际宽度就用它；首次布局（bounds 还是 0）沿用上次构建宽度先渲染，
        // 真实容器宽度确定后由 scheduleContentWidthFix 补一次重建纠正（见 sizeThatFits）。
        // skipRenderUntilSized：首帧零宽时干脆不渲染（零宽容器下渲染出的布局与
        // 真实宽度矛盾，重折行后代码块卡片/文字错位），等 sizeThatFits 以真实宽度排期。
        if skipRenderUntilSized, textView.bounds.width <= 0 {
            scheduleContentWidthFix(
                textView,
                contentWidth: MarkdownAttributedBuilder.availableContentWidth,
                coordinator: context.coordinator
            )
            return
        }
        let fallbackWidth = context.coordinator.lastRenderKey?.contentWidth
            ?? MarkdownAttributedBuilder.availableContentWidth
        let contentWidth = textView.bounds.width > 0
            ? textView.bounds.width.rounded(.down)
            : fallbackWidth
        render(textView, contentWidth: contentWidth, coordinator: context.coordinator)
    }

    /// 构建并写入文本。输入指纹（内容/折叠/高亮/宽度/配色）任一变化才重建。
    /// 不能依赖文本相等性做门控：文本系统会在布局期间复制/重建附件，
    /// 复制后的存储与重新构建的结果可能永远「不相等」，若每次 updateNSView 都重设
    /// textStorage，会陷入 重建→布局失效→再重建 的死循环（卡死随后崩溃）。
    ///
    /// 不是 private：测试直接调用它验证指纹与配色（SwiftUI 的 `Context` 无法在
    /// 测试里构造，走不到 updateNSView）。
    func render(_ textView: MarkdownTextView, contentWidth: CGFloat, coordinator: Coordinator) {
        // 每次重建时解析一次（不缓存）：换配色族不会改笔记内容，指纹不带它就永远不重建，
        // 属性里存着的还是旧主题那批颜色实例。
        let theme = highlightTheme ?? DanboMarkdownConfiguration.highlightTheme
        let key = Coordinator.RenderKey(
            markdown: markdown,
            collapsedSections: collapsedSections,
            highlightText: highlightText,
            contentWidth: contentWidth,
            // 任务行链接是否生成是构建期输入：同一内容从只读变成可点时必须重建。
            tasksClickable: onToggleTask != nil,
            themeID: theme?.id
        )
        guard coordinator.lastRenderKey != key else {
            return
        }
        // 可用宽度是构建期输入（表格列宽、图片尺寸都按它预排版），必须紧邻构建写入：
        // 它是所有实例共享的静态值，若残留其它实例（如右侧详情面板）的宽度，
        // 内容会按错误宽度排版，放进当前容器就横向溢出被裁，且指纹不变不会再重建。
        MarkdownAttributedBuilder.availableContentWidth = contentWidth
        let attributed = MarkdownAttributedBuilder.build(
            markdown: markdown,
            collapsedSections: collapsedSections,
            highlightText: highlightText,
            taskLinksEnabled: onToggleTask != nil,
            theme: theme
        )
        textView.textStorage?.setAttributedString(attributed)
        // 卡片底色是自绘的，得让视图自己知道用哪套配色。按 view 存值，不新增全局静态量：
        // availableContentWidth 跨实例串味的教训在那儿（同一进程里多个渲染实例共存）。
        textView.highlightTheme = theme
        textView.invalidateIntrinsicContentSize()
        // 纯文本替换不会改变视图 frame，layout() 不会自动触发，高度回写（钉住
        // measuredHeight 的唯一通道）也就不再执行，行高会永远钉在旧值上——内容
        // 增高后正文溢出视图底边（如项目简介越过下方的分隔线）。标脏强制一次
        // layout 让新高度得以及时回写。
        textView.needsLayout = true
        coordinator.lastRenderKey = key
    }

    /// 每次布局都按文本自身的布局结果报告尺寸。不实现 sizeThatFits 时，SwiftUI
    /// 可能在内容变化（如编辑保存成多行）后沿用首次测量的行高，导致正文超出
    /// 旧行高被裁掉/被下一行卡片挡住。
    ///
    /// 这里必须保持纯读（只设容器宽度 + 测高）：SwiftUI 会在一个布局周期内多次调用
    /// 它，且宽度提案可能逐轮抖动；若在其中重建文本/失效固有尺寸，重建 → 布局失效
    /// → 再布局 → 再重建会永远排不完，主线程跑满、整个 App 失去响应。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownTextView, context: Context) -> NSSize? {
        // 有具体宽度提案时先让文本按该宽度完成布局：窗口/分栏宽度变化的首个
        // 布局周期里，文本视图 bounds 可能还是旧值，直接量会得到错误行高。
        guard let width = proposal.width, width.isFinite, width > 0,
              let textContainer = nsView.textContainer else {
            return nil
        }
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        // 构建宽度与真实容器宽度不一致（如初次渲染按其它实例遗留的宽度构建，表格
        // 列宽/图片尺寸会横向溢出被裁且指纹不变不会再重建）：排到下一个 runloop
        // 补一次重建，本轮先用现有文本测高，纠正后的下一轮布局自然拿到正确行高。
        let contentWidth = width.rounded(.down)
        if context.coordinator.lastRenderKey?.contentWidth != contentWidth {
            scheduleContentWidthFix(nsView, contentWidth: contentWidth, coordinator: context.coordinator)
        }
        let intrinsic = nsView.intrinsicContentSize
        guard intrinsic.height.isFinite, intrinsic.height >= 0 else {
            return nil
        }
        return NSSize(width: width, height: intrinsic.height)
    }

    /// 下一个 runloop 按真实容器宽度重建文本。同一宽度只排一次：重建后指纹里的
    /// 宽度即与容器一致，sizeThatFits 不再重复排；排队期间容器宽度若有变化，
    /// 执行时以当时 bounds 为准。
    private func scheduleContentWidthFix(_ textView: MarkdownTextView, contentWidth: CGFloat, coordinator: Coordinator) {
        guard coordinator.scheduledFixWidth != contentWidth else { return }
        coordinator.scheduledFixWidth = contentWidth
        // self 是结构体，无引用循环，直接捕获；textView / coordinator 是类，用 weak。
        DispatchQueue.main.async { [self, weak textView, weak coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.scheduledFixWidth = nil
            let width = textView.bounds.width > 0
                ? textView.bounds.width.rounded(.down)
                : contentWidth
            self.render(textView, contentWidth: width, coordinator: coordinator)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onToggle: (String) -> Void
        var onToggleTask: ((Int) -> Void)?

        /// 上次渲染的输入指纹：markdown、折叠集合、高亮词、内容宽度、checkbox 是否可点。
        struct RenderKey: Equatable {
            let markdown: String
            let collapsedSections: Set<String>
            let highlightText: String?
            let contentWidth: CGFloat
            let tasksClickable: Bool
            /// 代码块配色标识：换配色族时内容没变，但它变了，必须重建。
            let themeID: String?
        }
        var lastRenderKey: RenderKey?

        /// 已排队待重建的容器宽度：同一宽度只排一次，防止布局期内重复派发。
        var scheduledFixWidth: CGFloat?

        init(onToggle: @escaping (String) -> Void, onToggleTask: ((Int) -> Void)?) {
            self.onToggle = onToggle
            self.onToggleTask = onToggleTask
        }

        /// 内部链接的点击入口。走代理而不是 mouseDown 命中测试：AppKit 只在
        /// 「点击」时回调（按下后拖动选字不会触发），所以在任务行上拖选文字仍然可用。
        /// 连击（clickCount ≥ 2）不经这里，由 MarkdownTextView.mouseDown 兜底。
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }

            if url.scheme == DanboMarkdownConfiguration.linkScheme,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                // 任务行链接（<linkScheme>://task?line=…）：checkbox 与行内文字都命中。
                if let line = MarkdownAttributedBuilder.taskLine(from: url) {
                    onToggleTask?(line)
                    return true
                }

                // 折叠/展开标题链接（<linkScheme>://collapse?key=…）。
                if let key = components.queryItems?.first(where: { $0.name == "key" })?.value {
                    onToggle(key)
                    return true
                }
            }

            // 本地附件链接（file://…）：点击用默认应用打开文件。
            if url.isFileURL {
                NSWorkspace.shared.open(url)
                return true
            }

            return false
        }
    }
}

final class MarkdownTextView: NSTextView {
    /// 代码块卡片底色用的配色，由渲染时写入。nil 时用默认底色。
    ///
    /// 存在视图上而不是读全局：底色是在 drawBackground 里取的，那时拿不到本次构建
    /// 用的那套配色；而全局量在同进程多个渲染实例（笔记窗口 + 右侧详情面板）之间
    /// 是共用的，谁最后写谁说了算。
    var highlightTheme: HighlightTheme?

    /// 代码块卡片的实际底色。主题的底色与代码正文色同源（base00 / base05）：
    /// 只有底色跟着主题走、文字还是 labelColor（跟随外观）时，
    /// 「深色配色 + 浅色外观」就是黑字黑底。
    var codeBlockCardFill: NSColor { highlightTheme?.cardFill ?? codeBlockBackgroundFill }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        var height = layoutManager.usedRect(for: textContainer).height
        // 末行是代码块时，卡片向下外扩的 padding 会超出文本排版高度（尾换行被
        // trimTrailingWhitespace 删掉后，usedRect 也不含末行的段后间距），
        // 不把这部分算进固有高度，SwiftUI 行高就不够，卡片底边被裁掉。
        if let cardBottom = codeBlockFrames().map(\.frame.maxY).max(), cardBottom > height {
            height = cardBottom
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
        // 把文本实际排版高度上报给 SwiftUI（写回显式 frame）。AppKit 的
        // invalidateIntrinsicContentSize 对 SwiftUI 不生效：宽度/内容变化导致
        // 重折行后，若 SwiftUI 不再询问 sizeThatFits，行高会停留在旧测量值，
        // 增高的正文被卡片底边裁掉。同值只报一次，收敛后不再触发重排。
        let height = intrinsicContentSize.height
        guard height.isFinite, height >= 0 else { return }
        if lastReportedHeight == nil || abs(lastReportedHeight! - height) > 0.5 {
            lastReportedHeight = height
            onLayoutHeightChanged?(height)
        }
    }

    /// 文本实际排版高度变化时回调（值已 ceil，由 MarkdownTextRepresentable 写回 SwiftUI）。
    var onLayoutHeightChanged: ((CGFloat) -> Void)?
    private var lastReportedHeight: CGFloat?

    /// 每个代码块的卡片 frame 与文本（画背景、画复制图标、命中测试、复制共用）。
    /// isSingleLine 用于复制图标的垂直定位：单行时居中，多行时贴右上角。
    private func codeBlockFrames() -> [(frame: NSRect, text: String, isSingleLine: Bool)] {
        guard let textStorage = textStorage, let layoutManager = layoutManager, let textContainer = textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var result: [(frame: NSRect, text: String, isSingleLine: Bool)] = []
        textStorage.enumerateAttribute(codeBlockBackgroundAttributeKey, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            // 用每行的 usedRect（该行实际占用区域）并集，卡片才会贴着代码内容；
            // enumerateEnclosingRects 返回的是横跨整行宽度的片段框，多行时会撑满全宽，
            // 导致首个代码块的复制图标被推到最右边缘。
            var used = NSRect.null
            var lineCount = 0
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                used = used.union(usedRect)
                lineCount += 1
            }
            guard !used.isNull else { return }
            var card = used.insetBy(dx: -codeBlockPaddingX, dy: -codeBlockPaddingY)
            // 右侧为复制图标让出空间：图标左缘距卡片右缘 27pt，而卡片只超出文字
            // 12pt，默认会侵入文字右缘 15pt，短单行代码块上直接盖住行尾文字。
            // 外扩以可视区域为上限：文本已贴近右缘的超宽代码块保持原宽度，
            // 避免卡片与图标被裁出可视区。
            card.size.width += min(codeBlockCopyIconReserve, max(0, bounds.width - card.maxX))
            let text = textStorage.attributedSubstring(from: range).string
            result.append((card, text, lineCount == 1))
        }
        return result
    }

    /// 代码块复制图标的命中区：单行代码块垂直居中，多行代码块贴右上角
    ///（衬底到卡片右上角「顶部 / 右侧」保持等距，且落在圆角外的直线区）。
    private func codeBlockCopyIconRect(for block: (frame: NSRect, text: String, isSingleLine: Bool)) -> NSRect {
        let inset = codeBlockCornerRadius + codeBlockCopyIconBackgroundPadding
        let y = block.isSingleLine
            ? block.frame.midY - codeBlockCopyIconSize / 2
            : block.frame.minY + inset
        return NSRect(x: block.frame.maxX - inset - codeBlockCopyIconSize,
                      y: y,
                      width: codeBlockCopyIconSize,
                      height: codeBlockCopyIconSize)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let cardFill = codeBlockCardFill
        for block in codeBlockFrames() {
            let path = NSBezierPath(roundedRect: block.frame, xRadius: codeBlockCornerRadius, yRadius: codeBlockCornerRadius)
            cardFill.setFill()
            path.fill()
        }
        drawTableGrid()
    }

    /// 每个表格行的实际 frame 与行信息（画网格线、表头底色共用）。
    private func tableRowFrames() -> [(rect: NSRect, info: TableRowInfo)] {
        guard let textStorage = textStorage, let layoutManager = layoutManager, let textContainer = textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var result: [(rect: NSRect, info: TableRowInfo)] = []
        textStorage.enumerateAttribute(tableRowAttributeKey, in: fullRange, options: []) { value, range, _ in
            guard let info = value as? TableRowInfo else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            // 与 codeBlockFrames 同理：取行内各 line usedRect 的并集，单元格换行时也能框住整行。
            var used = NSRect.null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                used = used.union(usedRect)
            }
            guard !used.isNull else { return }
            result.append((used, info))
        }
        return result
    }

    /// 画表格网格：表头底色 + 顶/底边框 + 行分隔线 + 列分隔线。
    /// 单元格自动折行后，一个逻辑行会占多个段落行，先按 rowIndex 聚合回逻辑行。
    private func drawTableGrid() {
        let groups = Dictionary(grouping: tableRowFrames()) { $0.info.tableID }
        for group in groups.values {
            let lines = group.sorted { $0.rect.minY < $1.rect.minY }
            guard let first = lines.first, let last = lines.last,
                  let edges = lines.first?.info.columnEdges, !edges.isEmpty,
                  let tableRight = edges.last else { continue }

            var rowRects: [NSRect] = []
            var rowIndexes: [Int] = []
            for line in lines {
                if let previousIndex = rowIndexes.last, previousIndex == line.info.rowIndex {
                    rowRects[rowRects.count - 1] = rowRects[rowRects.count - 1].union(line.rect)
                } else {
                    rowRects.append(line.rect)
                    rowIndexes.append(line.info.rowIndex)
                }
            }

            let top = first.rect.minY - tableCellTopPadding
            let bottom = last.rect.maxY + tableCellBottomPadding

            // 行分隔线偏向上方行：距下一行文字顶部留 tableCellTopPadding（单元格
            // 顶部内边距）、距上一行文字底部留 tableCellBottomPadding；行距异常
            // （测量/折行导致留白不足）时退回中点，且不压到上一行文字。
            let separatorYs: [CGFloat] = zip(rowRects, rowRects.dropFirst()).map { previous, next in
                max(previous.maxY + 1, min(next.minY - tableCellTopPadding, (previous.maxY + next.minY) / 2))
            }

            // 表头底色：填充到表头行与首个数据行之间的分隔线处。
            if rowIndexes.first == 0 {
                let headerBottom = separatorYs.first ?? bottom
                tableHeaderBackgroundColor.setFill()
                NSRect(x: 0, y: top, width: tableRight, height: headerBottom - top).fill()
            }

            tableBorderColor.setFill()
            NSRect(x: 0, y: top, width: tableRight, height: 1).fill()
            NSRect(x: 0, y: bottom - 1, width: tableRight, height: 1).fill()
            for y in separatorYs {
                NSRect(x: 0, y: y - 0.5, width: tableRight, height: 1).fill()
            }
            for x in edges {
                NSRect(x: x - 0.5, y: top, width: 1, height: bottom - top).fill()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let blocks = codeBlockFrames()
        for (index, block) in blocks.enumerated() {
            let iconRect = codeBlockCopyIconRect(for: block)
            let background = NSBezierPath(roundedRect: iconRect.insetBy(dx: -codeBlockCopyIconBackgroundPadding, dy: -codeBlockCopyIconBackgroundPadding), xRadius: 4, yRadius: 4)
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            background.fill()
            (index == copiedBlockIndex ? checkGlyph : copyGlyph)?.draw(in: iconRect)
        }
    }

    /// 折叠/展开标题的切换回调。命中标题链接时调用；nil 时走 `clickedOnLink` 兜底。
    var onToggleCollapse: ((String) -> Void)?

    /// 双击回调（如「双击项目简介进入编辑」）。nil 时双击走默认的整词选中。
    var onDoubleClick: (() -> Void)?

    /// 任务行点击回调（参数为源 Markdown 行号）；见 mouseDown 里的连击兜底。
    var onToggleTask: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, block) in codeBlockFrames().enumerated() {
            if codeBlockCopyIconRect(for: block).contains(point) {
                copyBlock(at: index, text: block.text)
                return
            }
        }
        // 直接命中折叠标题链接：切换并消费本次点击，避免被当成文本选中而无法展开。
        if let key = collapseKey(at: point) {
            onToggleCollapse?(key)
            return
        }
        // 任务行连击兜底：AppKit 只在单击时回调 clickedOnLink，连击（同一处点第二次
        // 起）不再回调，任务行就「点一次能翻转、再点没反应」，只有挪开鼠标重新单击
        // 才行。单击仍交给 clickedOnLink，保留按下拖动选字的能力。
        if event.clickCount > 1, let line = taskLine(at: point) {
            onToggleTask?(line)
            return
        }
        if event.clickCount == 2, let onDoubleClick {
            onDoubleClick()
            return
        }
        super.mouseDown(with: event)
    }

    /// 返回 point 上任务链接对应的源 Markdown 行号（无命中则返回 nil）。
    func taskLine(at point: NSPoint) -> Int? {
        guard let url = linkURL(at: point) else { return nil }
        return MarkdownAttributedBuilder.taskLine(from: url)
    }

    /// 返回落在 point 上的折叠链接 key（若无命中链接则返回 nil）。
    private func collapseKey(at point: NSPoint) -> String? {
        guard let url = linkURL(at: point), url.host == "collapse",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let key = components.queryItems?.first(where: { $0.name == "key" })?.value else { return nil }
        return key
    }

    /// point 处字符上的内部链接（折叠标题与任务行连击兜底共用；单击由 clickedOnLink
    /// 代理处理）。
    private func linkURL(at point: NSPoint) -> URL? {
        guard let layoutManager = layoutManager, let textContainer = textContainer, let textStorage = textStorage else { return nil }
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index >= 0, index < textStorage.length else { return nil }
        guard let url = textStorage.attribute(.link, at: index, effectiveRange: nil) as? URL,
              url.scheme == DanboMarkdownConfiguration.linkScheme else { return nil }
        return url
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for block in codeBlockFrames() {
            addCursorRect(codeBlockCopyIconRect(for: block), cursor: .pointingHand)
        }
    }

    private func copyBlock(at index: Int, text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedBlockIndex = index
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copiedBlockIndex = nil
            self?.needsDisplay = true
        }
    }

    private var copiedBlockIndex: Int?
    private let codeBlockCopyIconSize: CGFloat = 14
    private let codeBlockCopyIconBackgroundPadding: CGFloat = 3

    private lazy var copyGlyph: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
        return NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")?.withSymbolConfiguration(config)
    }()

    private lazy var checkGlyph: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.systemGreen]))
        return NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已复制")?.withSymbolConfiguration(config)
    }()
}
