# danbo-swift-markdown

一个原生的 macOS Markdown 解析与渲染库。解析由 Apple 官方的
[swift-markdown](https://github.com/swiftlang/swift-markdown)（CommonMark + GFM）完成；
本包把得到的 AST 渲染成完整排版的 `NSAttributedString`，承载于 `NSTextView` 之中，
既保留标准 Markdown 语义（链接、强调、删除线、行内代码），又为常见块级类型提供排版。

本包仅支持 macOS（AppKit + SwiftUI），要求 macOS 15+，使用 Swift 5 语言模式。

## 功能

- **块级排版**：标题（可折叠的章节）、段落、有序/无序列表、任务列表
  （`- [ ]` / `- [x]`）、引用、围栏代码块（圆角卡片 + 复制按钮）、分隔线、
  图片，以及 GFM 表格（网格线、表头底色、逐列对齐、单元格自动折行）。
- **行内渲染**：强调、加粗、删除线、行内代码、链接、图片、软/硬换行，
  全部由 swift-markdown 的 AST 遍历产出，并自动检测裸链接。
- **自定义语法**：`__文字__` 渲染为绿色强调，而不是加粗。CommonMark 把它解析成
  与 `**文字**` 相同的节点，因此原始分隔符要靠源码 range 回查区分。`[文字]`
  整段（含方括号）渲染为蓝色加粗；代码块与行内代码里的方括号保持字面。
- **交互能力**：可折叠的标题章节、可点击的任务行（点 checkbox 或该行任意文字都
  翻转勾选状态，回调携带源行号）、文本高亮，以及用于 SwiftUI 集成的测高回写。
- **代码高亮**：围栏代码块由 [danbo-swift-highlight](../danbo-swift-highlight)
  分词，按 base16 配色着色。token 只改颜色，绝不动字体、字号与字重——所以
  开关高亮前后的折行与测高结果逐位相同。卡片底色与代码正文取自同一套配色，
  深色配色落在浅色页面上依然可读。
- **无窗口测量**：`MarkdownTextMeasurer` 在无窗口环境复现完全相同的渲染管线，
  回归测试由此驱动。

## 公开 API

| 符号 | 类型 | 用途 |
| --- | --- | --- |
| `MarkdownRenderer` | SwiftUI `View` | 渲染 Markdown 字符串；支持折叠请求、任务切换、双击、高亮、测高回写，以及逐实例的 `highlightTheme`。 |
| `MarkdownCollapseRequest` | struct | 传给 `MarkdownRenderer` 的全部折叠/展开信号。 |
| `MarkdownTextMeasurer` | enum | 无窗口排版测量：`height(markdown:width:)`、`height(markdowns:width:)`、`height(_:)`、`debugLineLayout(markdown:width:)`。 |
| `DanboMarkdownConfiguration` | enum | 全局配置：`bodyFontSize`（默认 15）、`linkScheme`（默认 `"danbo-swift-markdown"`，用于内部折叠/任务链接）与 `highlightTheme`（默认 `nil`，代码块保持单色）。 |

## 使用

把本包作为本地依赖添加，然后导入模块：

```swift
import DanboSwiftMarkdown
import DanboSwiftHighlight

// 可选，App 启动时设置一次：与宿主 App 的标识保持一致。
DanboMarkdownConfiguration.bodyFontSize = 15
DanboMarkdownConfiguration.linkScheme = "myapp"

// 围栏代码块按语法着色。"default" 解析到 default-light / default-dark 这一对，
// 因此颜色跟随系统外观切换，不需要重建任何东西。
DanboMarkdownConfiguration.highlightTheme = .paired("default")

struct NoteView: View {
    let content: String

    var body: some View {
        MarkdownRenderer(
            markdown: content,
            onToggleTask: { line in
                // 在源 Markdown 中翻转第 line 行的勾选状态（点 checkbox 或该行文字都会触发）。
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
- `linkScheme` 应在启动时设置一次；内部链接（章节折叠、任务行）
  都按该 scheme 生成与识别。
- `highlightTheme` 在每次重建时读取一次，配色的 `id` 也进了渲染指纹，所以换配色
  会触发重渲染。需要给单个实例单独指定时，用 `MarkdownRenderer` 自己的
  `highlightTheme` 覆盖全局值。
- 没有语言标记（或语言认不出）的围栏代码块保持单色；本库从不猜语言。

## 开发

除了 [swift-markdown](https://github.com/swiftlang/swift-markdown)（`>= 0.8.0`，
连带拉入 `swift-cmark`），本包还依赖本地包 `../danbo-swift-highlight`。
克隆后先把依赖解析齐：

```sh
swift package resolve
swift build
swift test
```

测试套件（`Tests/DanboSwiftMarkdownTests`）覆盖两件事。一是测高契约：内容原地改写后
必须重新测量、跨宽度构建必须与全新渲染一致、图片必须按真实容器宽度重新缩放、
代码块卡片不得与相邻段落重叠。二是 AST 解析喂给渲染器的语法：`**粗体**` 与
`__绿色__` 的区分、`[蓝色标记]`（含跨行内样式的标记，以及代码里必须保持字面的
方括号）、任务项的 0 基源行号、带逐列对齐的 GFM 表格，以及行内图片。
代码高亮也在覆盖范围内：认得出的语言染上对应的 token 色、无语言标记与认不出的
语言保持单色、卡片底色跟随主题、换配色触发重建而同配色不重建，以及开启高亮后
测高结果一个点都不动。

## 授权协议

MIT，详见 [LICENSE](LICENSE)。
