# danbo-swift-markdown

一个原生的 macOS Markdown 解析与渲染库。它把 Markdown 渲染成完整排版的
`NSAttributedString`，承载于 `NSTextView` 之中，既保留标准 Markdown 语义
（链接、强调、删除线、行内代码），又为常见块级类型提供排版。

本包仅支持 macOS（AppKit + SwiftUI），要求 macOS 15+，使用 Swift 5 语言模式。

## 功能

- **块级排版**：标题（可折叠的章节）、段落、有序/无序列表、任务列表
  （`- [ ]` / `- [x]`）、引用、围栏代码块（圆角卡片 + 复制按钮）、分隔线、
  图片，以及 GFM 表格（网格线、表头底色、逐列对齐、单元格自动折行）。
- **行内渲染**：基于 Foundation 的 `AttributedString(markdown:)`，并自动检测链接。
- **自定义语法**：`__文字__` 渲染为绿色强调，而不是加粗。
- **交互能力**：可折叠的标题章节、可点击的任务 checkbox（回调携带源行号）、
  文本高亮，以及用于 SwiftUI 集成的测高回写。
- **无窗口测量**：`MarkdownTextMeasurer` 在无窗口环境复现完全相同的渲染管线，
  回归测试由此驱动。
- **独立的词法/语法分析器**（`Lexer` / `Parser`）：一个小巧的、基于 token 的
  Markdown 词法器，早于渲染管线存在，作为公开 API 保留。

## 公开 API

| 符号 | 类型 | 用途 |
| --- | --- | --- |
| `MarkdownRenderer` | SwiftUI `View` | 渲染 Markdown 字符串；支持折叠请求、任务切换、双击、高亮与测高回写。 |
| `MarkdownCollapseRequest` | struct | 传给 `MarkdownRenderer` 的全部折叠/展开信号。 |
| `MarkdownTextMeasurer` | enum | 无窗口排版测量：`height(markdown:width:)`、`height(markdowns:width:)`、`height(_:)`、`debugLineLayout(markdown:width:)`。 |
| `DanboMarkdownConfiguration` | enum | 全局配置：`bodyFontSize`（默认 15）与 `linkScheme`（默认 `"danbo-swift-markdown"`，用于内部折叠/任务链接）。 |
| `Lexer`、`Parser`、`Token`、`TokenType`、`Row`、`TextRow` | — | 独立的、基于 token 的词法/语法分析器。 |

## 使用

把本包作为本地依赖添加，然后导入模块：

```swift
import DanboSwiftMarkdown

// 可选，App 启动时设置一次：与宿主 App 的标识保持一致。
DanboMarkdownConfiguration.bodyFontSize = 15
DanboMarkdownConfiguration.linkScheme = "myapp"

struct NoteView: View {
    let content: String

    var body: some View {
        MarkdownRenderer(
            markdown: content,
            onToggleTask: { line in
                // 在源 Markdown 中翻转第 line 行的勾选状态。
            },
            onMeasuredHeight: { height in
                // 全文的实际排版高度，与展示层裁剪无关。
            }
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

注意：

- 与 `NSTextView` 本身一样，整条管线只能在主线程/AppKit 环境使用。
- `linkScheme` 应在启动时设置一次；内部链接（章节折叠、任务 checkbox）
  都按该 scheme 生成与识别。

## 开发

```sh
swift build
swift test
```

测试套件（`Tests/DanboSwiftMarkdownTests`）覆盖测高契约：内容原地改写后必须
重新测量、跨宽度构建必须与全新渲染一致、图片必须按真实容器宽度重新缩放、
代码块卡片不得与相邻段落重叠。
