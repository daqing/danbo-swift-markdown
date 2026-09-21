# danbo-swift-markdown

A native macOS Markdown parsing and rendering library. It renders Markdown as a
fully laid-out `NSAttributedString` inside an `NSTextView`, keeping standard
Markdown semantics (links, emphasis, strikethrough, inline code) while adding
layout for common block types.

The package is macOS-only (AppKit + SwiftUI), requires macOS 15+, and uses the
Swift 5 language mode.

## Features

- **Block layout**: headings (collapsible sections), paragraphs, ordered and
  unordered lists, task lists (`- [ ]` / `- [x]`), quotes, fenced code blocks
  (rounded card with a copy button), dividers, images, and GFM tables (grid
  lines, header shading, per-column alignment, automatic cell wrapping).
- **Inline rendering** via Foundation's `AttributedString(markdown:)`, plus
  automatic link detection.
- **Custom syntax**: `__text__` renders as green emphasis instead of bold.
- **Interactive**: collapsible heading sections, clickable task checkboxes
  (the callback carries the source line number), text highlighting, and
  measured-height callbacks for SwiftUI integration.
- **Headless measurement**: `MarkdownTextMeasurer` reproduces the exact
  rendering pipeline without a window, which powers the regression tests.
- **Standalone lexer/parser** (`Lexer` / `Parser`): a small token-based
  Markdown lexer that predates the rendering pipeline, kept as a public API.

## Public API

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `MarkdownRenderer` | SwiftUI `View` | Renders a Markdown string; supports collapse requests, task toggling, double-click, highlight, and measured-height callbacks. |
| `MarkdownCollapseRequest` | struct | Collapse/expand-all signal for `MarkdownRenderer`. |
| `MarkdownTextMeasurer` | enum | Windowless layout measurement: `height(markdown:width:)`, `height(markdowns:width:)`, `height(_:)`, `debugLineLayout(markdown:width:)`. |
| `DanboMarkdownConfiguration` | enum | Global configuration: `bodyFontSize` (default 15) and `linkScheme` (default `"danbo-swift-markdown"`, used for internal collapse/task links). |
| `Lexer`, `Parser`, `Token`, `TokenType`, `Row`, `TextRow` | — | Standalone token-based lexer/parser. |

## Usage

Add the package as a local dependency and import the module:

```swift
import DanboSwiftMarkdown

// Optional, once at app startup: match the host app's identity.
DanboMarkdownConfiguration.bodyFontSize = 15
DanboMarkdownConfiguration.linkScheme = "myapp"

struct NoteView: View {
    let content: String

    var body: some View {
        MarkdownRenderer(
            markdown: content,
            onToggleTask: { line in
                // Flip the checkbox on `line` in the source Markdown.
            },
            onMeasuredHeight: { height in
                // Full laid-out height, independent of any display-level clipping.
            }
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

Notes:

- The whole pipeline is main-thread/AppKit only, like `NSTextView` itself.
- `linkScheme` should be set once at startup; internal links (section
  collapse, task checkboxes) are generated and recognized with this scheme.

## Development

```sh
swift build
swift test
```

The test suite (`Tests/DanboSwiftMarkdownTests`) covers the height-measurement
contract: content rewritten in place must re-measure correctly, cross-width
builds must match fresh renders, images must rescale to the real container
width, and code-block cards must not overlap adjacent paragraphs.
