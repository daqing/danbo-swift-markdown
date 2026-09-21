# danbo-swift-markdown

A native macOS Markdown parsing and rendering library. Parsing is done by Apple's
[swift-markdown](https://github.com/swiftlang/swift-markdown) (CommonMark + GFM);
this package renders the resulting AST as a fully laid-out `NSAttributedString`
inside an `NSTextView`, keeping standard Markdown semantics (links, emphasis,
strikethrough, inline code) while adding layout for common block types.

The package is macOS-only (AppKit + SwiftUI), requires macOS 15+, and uses the
Swift 5 language mode.

## Features

- **Block layout**: headings (collapsible sections), paragraphs, ordered and
  unordered lists, task lists (`- [ ]` / `- [x]`), quotes, fenced code blocks
  (rounded card with a copy button), dividers, images, and GFM tables (grid
  lines, header shading, per-column alignment, automatic cell wrapping).
- **Inline rendering**: emphasis, strong, strikethrough, inline code, links,
  images, and soft/hard breaks, all walked from the swift-markdown AST, plus
  automatic detection of bare URLs.
- **Custom syntax**: `__text__` renders as green emphasis instead of bold.
  CommonMark parses it as the same node as `**text**`, so the original
  delimiters are recovered from the source range. `[text]` renders the whole
  marker, brackets included, in bold blue; brackets inside code blocks and
  inline code stay literal.
- **Interactive**: collapsible heading sections, clickable task lines (clicking
  the checkbox or any text on that line toggles it; the callback carries the
  source line number), text highlighting, and measured-height callbacks for
  SwiftUI integration.
- **Code highlighting**: fenced code blocks are tokenized by
  [danbo-swift-highlight](../danbo-swift-highlight) and colored from a base16
  scheme. Tokens change color only — never font, size or weight — so wrapping
  and measured height are bit-for-bit identical with highlighting on or off.
  The card background comes from the same scheme as the code text, which keeps
  a dark scheme readable on a light page.
- **Headless measurement**: `MarkdownTextMeasurer` reproduces the exact
  rendering pipeline without a window, which powers the regression tests.

## Public API

| Symbol | Kind | Purpose |
| --- | --- | --- |
| `MarkdownRenderer` | SwiftUI `View` | Renders a Markdown string; supports collapse requests, task toggling, double-click, highlight, measured-height callbacks, and a per-instance `highlightTheme`. |
| `MarkdownCollapseRequest` | struct | Collapse/expand-all signal for `MarkdownRenderer`. |
| `MarkdownTextMeasurer` | enum | Windowless layout measurement: `height(markdown:width:)`, `height(markdowns:width:)`, `height(_:)`, `debugLineLayout(markdown:width:)`. |
| `DanboMarkdownConfiguration` | enum | Global configuration: `bodyFontSize` (default 15), `linkScheme` (default `"danbo-swift-markdown"`, used for internal collapse/task links), and `highlightTheme` (default `nil` — code blocks stay monochrome). |

## Usage

Add the package as a local dependency and import the module:

```swift
import DanboSwiftMarkdown
import DanboSwiftHighlight

// Optional, once at app startup: match the host app's identity.
DanboMarkdownConfiguration.bodyFontSize = 15
DanboMarkdownConfiguration.linkScheme = "myapp"

// Fenced code blocks get syntax colors. "default" resolves to the
// default-light / default-dark pair, so the colors follow the system
// appearance without rebuilding anything.
DanboMarkdownConfiguration.highlightTheme = .paired("default")

struct NoteView: View {
    let content: String

    var body: some View {
        MarkdownRenderer(
            markdown: content,
            onToggleTask: { line in
                // Flip the checkbox on `line` in the source Markdown (clicking the
                // checkbox or any text on that line fires this).
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
  collapse, task lines) are generated and recognized with this scheme.
- `highlightTheme` is read on every rebuild, and the scheme's `id` is part of
  the render fingerprint, so changing it re-renders. Set `MarkdownRenderer`'s
  own `highlightTheme` to override the global one for a single instance.
- A fenced block with no language (or an unrecognized one) stays monochrome;
  languages are never guessed.

## Development

Besides [swift-markdown](https://github.com/swiftlang/swift-markdown)
(`>= 0.8.0`), which pulls in `swift-cmark`, the package depends on the local
`../danbo-swift-highlight`. Resolve everything once after cloning:

```sh
swift package resolve
swift build
swift test
```

The test suite (`Tests/DanboSwiftMarkdownTests`) covers the height-measurement
contract — content rewritten in place must re-measure correctly, cross-width
builds must match fresh renders, images must rescale to the real container
width, and code-block cards must not overlap adjacent paragraphs — plus the
syntax the AST parser feeds into the renderer: `**bold**` versus `__green__`,
`[blue]` markers (including ones spanning inline styles, and brackets that must
stay literal inside code), the 0-based source line on task items, GFM tables
with per-column alignment, and inline images. Code highlighting is covered too:
known languages get their token colors, unknown and missing ones stay
monochrome, the card fill tracks the theme, a changed scheme re-renders while an
unchanged one does not, and turning highlighting on does not move a single
measured height.

## License

MIT — see [LICENSE](LICENSE).
