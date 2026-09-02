/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Deliverable (flag-OFF) source-position coverage for every BLOCK construct crossed with the
/// Unicode encoding classes that stress byte-column bookkeeping. Source columns are 1-based UTF-8
/// **byte** offsets, so a multi-byte scalar before or inside a construct's content must advance the
/// reported column by its byte count (2 for `é`/`U+00E9`, 3 for `€`/`U+20AC`, 4 for `😀`/`U+1F600`,
/// 3 for a combining sequence `e` + `U+0301`, 3 for `U+FFFD`) while a TAB counts as one byte (no
/// expansion). Every asserted value is the flag-OFF surface (`dump --new-off`, the shipped parser
/// with `[.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]` and NO
/// `.cmarkBugCompatibility`); each was confirmed against `dump --ref` (cmark-gfm) and, where the two
/// disagree, the flag-OFF value is spec-correct by byte-offset reasoning and cmark's is a quirk
/// (marked `// cmark differs`).
@Suite("Block source positions — Unicode encodings")
struct BlockPositionEncodingTests {

    fileprivate typealias Pos = MarkdownNode.SourcePosition

    /// The deliverable option set: source positions + smart punctuation + the GFM extensions the
    /// `Markdown` layer always enables. This equals `dump --new-off` (options byte `0x00`), whose
    /// `Markdown.ParseOptions(rawValue: 0)` maps to exactly these `CommonMark` options.
    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    /// One collected node: its kind (which carries heading level / list info / checkbox / code-fence
    /// metadata as associated values), the literal it exposes (text run, code-block body, HTML-block
    /// body), the code-block info string, and its source range.
    ///
    /// `fileprivate` (not `private`) so the file-scope `collect(_:into:)` — required because a
    /// `~Escapable` `MarkdownNode` can't be captured by an instance-method closure — can name it.
    fileprivate struct Collected {
        let kind: MarkdownNode.Kind
        let literal: String?
        let info: String?
        let range: Range<Pos>?
    }

    /// DFS pre-order collect of every node.
    private func parse(_ src: String) throws -> [Collected] {
        var out: [Collected] = []
        try MarkdownDocument.withParsedDocument(src, options: Self.opts) { doc in
            collect(doc.root, into: &out)
        }
        return out
    }

    // MARK: - Paragraph

    @Test("paragraph — byte columns track multibyte, combining, replacement, and tab bytes")
    func paragraph() throws {
        // ASCII baseline: 11 bytes → end column 12 (last byte column + 1).
        do {
            let out = try parse("hello world")
            try #require(shape(out) == ["document", "paragraph", "text"])
            #expect(out[0].range == r(1, 1, 1, 12))
            #expect(out[1].range == r(1, 1, 1, 12))
            #expect(out[2].range == r(1, 1, 1, 12))
            #expect(out[2].literal == "hello world")
        }
        // é (U+00E9, 2 bytes) then " x": 4 bytes → end column 5.
        try oneLineParagraph("\u{E9} x", endColumn: 5)
        // € (U+20AC, 3 bytes) then " x": 5 bytes → end column 6.
        try oneLineParagraph("\u{20AC} x", endColumn: 6)
        // 😀 (U+1F600, 4 bytes) then " x": 6 bytes → end column 7.
        try oneLineParagraph("\u{1F600} x", endColumn: 7)
        // e + combining acute (U+0301): "e"(1) + combining(2) = 3 bytes, then " x": 5 bytes → col 6.
        try oneLineParagraph("e\u{301} x", endColumn: 6)
        // U+FFFD replacement (3 bytes) then " x": 5 bytes → end column 6. Doubles as the invalid-repair
        // byte-accounting case: a repaired sequence is the 3-byte U+FFFD, so it counts as 3 columns.
        try oneLineParagraph("\u{FFFD} x", endColumn: 6)
        // TAB is a single byte, not expanded: "a\tb" = 3 bytes → end column 4.
        try oneLineParagraph("a\tb", endColumn: 4)
        // Multibyte INSIDE the run (not leading): "x" + é + " y" = 5 bytes → end column 6.
        try oneLineParagraph("x\u{E9} y", endColumn: 6)

        // Multi-line paragraph: the second line's columns reset to line-relative byte offsets.
        // "é" (2 bytes, @1:1-1:3), softbreak, "€" (3 bytes, @2:1-2:4).
        do {
            let out = try parse("\u{E9}\n\u{20AC}")
            try #require(shape(out) == ["document", "paragraph", "text", "softBreak", "text"])
            #expect(out[0].range == r(1, 1, 2, 4))   // document
            #expect(out[1].range == r(1, 1, 2, 4))   // paragraph
            #expect(out[2].range == r(1, 1, 1, 3))   // "é" on line 1
            #expect(out[2].literal == "\u{E9}")
            #expect(out[3].range == nil)             // soft break carries no range (both sides)
            #expect(out[4].range == r(2, 1, 2, 4))   // "€" resets to line-2 column 1
            #expect(out[4].literal == "\u{20AC}")
        }
    }

    /// A single-line paragraph whose sole text run spans the whole line (`@1:1-1:<endColumn>`).
    private func oneLineParagraph(_ src: String, endColumn: Int) throws {
        let out = try parse(src)
        try #require(shape(out) == ["document", "paragraph", "text"])
        #expect(out[1].range == r(1, 1, 1, endColumn))
        #expect(out[2].range == r(1, 1, 1, endColumn))
        #expect(out[2].literal == src)
    }

    // MARK: - ATX heading

    @Test("ATX heading — content starts at byte column 3 and its end tracks multibyte width")
    func atxHeading() throws {
        // "# hi": content "hi" at columns 3-4 → text @1:3-1:5; heading spans @1:1-1:5.
        do {
            let out = try parse("# hi")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].kind == .heading(level: 1))
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[2].range == r(1, 3, 1, 5))
            #expect(out[2].literal == "hi")
        }
        // é content (2 bytes): text @1:3-1:5, heading @1:1-1:5.
        try atx("# \u{E9}", literal: "\u{E9}", textEnd: 5)
        // €x (3 + 1 bytes): text @1:3-1:7, heading @1:1-1:7.
        try atx("# \u{20AC}x", literal: "\u{20AC}x", textEnd: 7)
        // "😀 y" (4 + 1 + 1 bytes): text @1:3-1:9, heading @1:1-1:9.
        try atx("# \u{1F600} y", literal: "\u{1F600} y", textEnd: 9)
        // "e" + combining + "x" (3 + 1 bytes): text @1:3-1:7.
        try atx("# e\u{301}x", literal: "e\u{301}x", textEnd: 7)
        // U+FFFD + "x" (3 + 1 bytes): text @1:3-1:7.
        try atx("# \u{FFFD}x", literal: "\u{FFFD}x", textEnd: 7)
        // TAB inside content counts as one byte: "a\tb" → text @1:3-1:6.
        try atx("# a\tb", literal: "a\tb", textEnd: 6)
        // Closing "#" sequence is not part of the content range: "# hi #" → text @1:3-1:5,
        // heading @1:1-1:5 (the trailing " #" is excluded on both sides).
        do {
            let out = try parse("# hi #")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[2].range == r(1, 3, 1, 5))
            #expect(out[2].literal == "hi")
        }
    }

    /// An ATX heading `# <content>` whose text run is `@1:3-1:<textEnd>` and heading `@1:1-1:<textEnd>`.
    private func atx(_ src: String, literal: String, textEnd: Int) throws {
        let out = try parse(src)
        try #require(shape(out) == ["document", "heading", "text"])
        #expect(out[1].range == r(1, 1, 1, textEnd))
        #expect(out[2].range == r(1, 3, 1, textEnd))
        #expect(out[2].literal == literal)
    }

    // MARK: - Setext heading

    @Test("setext heading — content on line 1, range extends over the underline line")
    func setextHeading() throws {
        // "hi\n===": level 1, text @1:1-1:3, heading extends to end of underline @1:1-2:4.
        do {
            let out = try parse("hi\n===")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].kind == .heading(level: 1))
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 1, 1, 3))
            #expect(out[2].literal == "hi")
        }
        // "ab\n---": level 2 (dash underline), text @1:1-1:3, heading @1:1-2:4.
        do {
            let out = try parse("ab\n---")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].kind == .heading(level: 2))
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 1, 1, 3))
            #expect(out[2].literal == "ab")
        }
        // é content (2 bytes): text @1:1-1:3, heading @1:1-2:4, level 1.
        do {
            let out = try parse("\u{E9}\n===")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].kind == .heading(level: 1))
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 1, 1, 3))
            #expect(out[2].literal == "\u{E9}")
        }
        // "€ x" content (3 + 1 + 1 bytes) with dash underline: text @1:1-1:6, level 2.
        do {
            let out = try parse("\u{20AC} x\n---")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].kind == .heading(level: 2))
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 1, 1, 6))
            #expect(out[2].literal == "\u{20AC} x")
        }
        // Combining content "e" + U+0301 (3 bytes): text @1:1-1:4.
        do {
            let out = try parse("e\u{301}\n===")
            try #require(shape(out) == ["document", "heading", "text"])
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 1, 1, 4))
            #expect(out[2].literal == "e\u{301}")
        }
        // Multi-line setext content: "a\nb\n===" → two text runs joined by a soft break, heading
        // extends over the underline on line 3 (@1:1-3:4).
        do {
            let out = try parse("a\nb\n===")
            try #require(shape(out) == ["document", "heading", "text", "softBreak", "text"])
            #expect(out[1].range == r(1, 1, 3, 4))
            #expect(out[2].range == r(1, 1, 1, 2))   // "a"
            #expect(out[3].range == nil)             // soft break
            #expect(out[4].range == r(2, 1, 2, 2))   // "b" on line 2
        }
    }

    // MARK: - Thematic break

    @Test("thematic break — full-marker span across the three marker styles")
    func thematicBreak() throws {
        for marker in ["***", "---", "___"] {
            let out = try parse(marker)
            try #require(shape(out) == ["document", "thematicBreak"])
            #expect(out[1].kind == .thematicBreak)
            #expect(out[1].range == r(1, 1, 1, 4))   // 3 marker bytes → end column 4
        }
    }

    // MARK: - Blockquote

    @Test("blockquote — content column 3 after `> `, tracks multibyte, nesting, and matched continuation")
    func blockQuote() throws {
        // "> hi": blockquote @1:1-1:5, paragraph/text at content column 3.
        do {
            let out = try parse("> hi")
            try #require(shape(out) == ["document", "blockQuote", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[2].range == r(1, 3, 1, 5))
            #expect(out[3].range == r(1, 3, 1, 5))
            #expect(out[3].literal == "hi")
        }
        // "> é x" (content 3 bytes + " x"): text @1:3-1:7.
        do {
            let out = try parse("> \u{E9} x")
            try #require(shape(out) == ["document", "blockQuote", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 7))
            #expect(out[3].range == r(1, 3, 1, 7))
            #expect(out[3].literal == "\u{E9} x")
        }
        // "> €" (3-byte content only): text @1:3-1:6.
        do {
            let out = try parse("> \u{20AC}")
            try #require(shape(out) == ["document", "blockQuote", "paragraph", "text"])
            #expect(out[3].range == r(1, 3, 1, 6))
            #expect(out[3].literal == "\u{20AC}")
        }
        // Nested "> > hi": inner content column 5.
        do {
            let out = try parse("> > hi")
            try #require(shape(out) == ["document", "blockQuote", "blockQuote", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 7))
            #expect(out[2].range == r(1, 3, 1, 7))
            #expect(out[3].range == r(1, 5, 1, 7))
            #expect(out[4].range == r(1, 5, 1, 7))
            #expect(out[4].literal == "hi")
        }
        // Nested with multibyte "> > é": text @1:5-1:7.
        do {
            let out = try parse("> > \u{E9}")
            try #require(shape(out) == ["document", "blockQuote", "blockQuote", "paragraph", "text"])
            #expect(out[4].range == r(1, 5, 1, 7))
            #expect(out[4].literal == "\u{E9}")
        }
        // Matched multi-line "> a\n> b": both continuation lines keep content column 3.
        do {
            let out = try parse("> a\n> b")
            try #require(shape(out) == ["document", "blockQuote", "paragraph", "text", "softBreak", "text"])
            #expect(out[1].range == r(1, 1, 2, 4))
            #expect(out[2].range == r(1, 3, 2, 4))
            #expect(out[3].range == r(1, 3, 1, 4))   // "a"
            #expect(out[4].range == nil)             // soft break
            #expect(out[5].range == r(2, 3, 2, 4))   // "b" at content column 3 on line 2
        }
        // Matched multi-line with multibyte "> é\n> €".
        do {
            let out = try parse("> \u{E9}\n> \u{20AC}")
            try #require(shape(out) == ["document", "blockQuote", "paragraph", "text", "softBreak", "text"])
            #expect(out[1].range == r(1, 1, 2, 6))
            #expect(out[3].range == r(1, 3, 1, 5))   // "é" (2 bytes) line 1
            #expect(out[5].range == r(2, 3, 2, 6))   // "€" (3 bytes) line 2
            #expect(out[3].literal == "\u{E9}")
            #expect(out[5].literal == "\u{20AC}")
        }
    }

    @Test("blockquote lazy continuation — deliverable reports the true source column (cmark re-indents)")
    func blockQuoteLazyContinuation() throws {
        // "> a\nb": line 2 "b" is a LAZY continuation (no `>` prefix). Its only source byte is at
        // line-2 column 1, so the deliverable stamps "b" @2:1-2:2 — the true byte position.
        // cmark differs: reports "b" @2:3-2:4, re-indenting the continuation to the blockquote's
        // content column (a phantom column past line 2's single byte) — quirk E (paragraph
        // continuation-line re-indent), reproduced only under .cmarkBugCompatibility.
        let out = try parse("> a\nb")
        try #require(shape(out) == ["document", "blockQuote", "paragraph", "text", "softBreak", "text"])
        #expect(out[3].range == r(1, 3, 1, 4))   // "a"
        #expect(out[5].range == r(2, 1, 2, 2))   // "b" at its true column 1
        #expect(out[5].literal == "b")
    }

    // MARK: - Unordered list

    @Test("unordered list — marker styles and content column 3, tracking multibyte and tab")
    func unorderedList() throws {
        // Marker styles: -, *, + all put content at column 3, list/item/paragraph @1:1-1:4.
        for (marker, bullet) in [("-", MarkdownNode.ListInfo.BulletMarker.hyphen),
                                 ("*", .asterisk),
                                 ("+", .plus)] {
            let out = try parse("\(marker) x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(asList(out[1].kind)?.kind == .bullet)
            #expect(asList(out[1].kind)?.bulletMarker == bullet)
            #expect(out[1].range == r(1, 1, 1, 4))   // list
            #expect(out[2].range == r(1, 1, 1, 4))   // item
            #expect(out[3].range == r(1, 3, 1, 4))   // paragraph
            #expect(out[4].range == r(1, 3, 1, 4))   // text
            #expect(out[4].literal == "x")
        }
        // "- é" (2-byte content): text @1:3-1:5, list @1:1-1:5.
        do {
            let out = try parse("- \u{E9}")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[4].range == r(1, 3, 1, 5))
            #expect(out[4].literal == "\u{E9}")
        }
        // "- € x" (3 + 1 + 1 bytes): text @1:3-1:8.
        do {
            let out = try parse("- \u{20AC} x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 8))
            #expect(out[4].range == r(1, 3, 1, 8))
            #expect(out[4].literal == "\u{20AC} x")
        }
        // TAB inside content is one byte: "- a\tb" → text @1:3-1:6.
        do {
            let out = try parse("- a\tb")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[4].range == r(1, 3, 1, 6))
            #expect(out[4].literal == "a\tb")
        }
    }

    // MARK: - Ordered list

    @Test("ordered list — start number, delimiter, and content column 4 tracking multibyte")
    func orderedList() throws {
        // "1. x": start 1, period delimiter, content column 4.
        do {
            let out = try parse("1. x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(asList(out[1].kind)?.kind == .ordered)
            #expect(asList(out[1].kind)?.start == 1)
            #expect(asList(out[1].kind)?.orderedDelimiter == .period)
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[3].range == r(1, 4, 1, 5))
            #expect(out[4].range == r(1, 4, 1, 5))
            #expect(out[4].literal == "x")
        }
        // "2) x": start 2, paren delimiter.
        do {
            let out = try parse("2) x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(asList(out[1].kind)?.start == 2)
            #expect(asList(out[1].kind)?.orderedDelimiter == .paren)
            #expect(out[1].range == r(1, 1, 1, 5))
            #expect(out[4].range == r(1, 4, 1, 5))
            #expect(out[4].literal == "x")
        }
        // "1. 😀 z" (4 + 1 + 1 bytes content): text @1:4-1:10.
        do {
            let out = try parse("1. \u{1F600} z")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[1].range == r(1, 1, 1, 10))
            #expect(out[4].range == r(1, 4, 1, 10))
            #expect(out[4].literal == "\u{1F600} z")
        }
    }

    @Test("list lazy continuation — deliverable reports the true source column (cmark re-indents)")
    func listLazyContinuation() throws {
        // "- a\nb": line 2 "b" is a LAZY continuation (indented below the item content column). The
        // deliverable stamps it at its true byte position @2:1-2:2. cmark differs: reports "b"
        // @2:3-2:4, re-indenting to the list content column — quirk E, reproduced only under
        // .cmarkBugCompatibility.
        let out = try parse("- a\nb")
        try #require(shape(out) == ["document", "list", "item", "paragraph", "text", "softBreak", "text"])
        #expect(out[4].range == r(1, 3, 1, 4))   // "a"
        #expect(out[6].range == r(2, 1, 2, 2))   // "b" at its true column 1
        #expect(out[6].literal == "b")
    }

    // MARK: - Task list

    @Test("task list — checkbox state, content column 7, tracking multibyte")
    func taskList() throws {
        // "- [ ] x": unchecked item, content after "[ ] " at column 7.
        do {
            let out = try parse("- [ ] x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[2].kind == .item(checked: false))
            #expect(out[1].range == r(1, 1, 1, 8))
            #expect(out[3].range == r(1, 7, 1, 8))
            #expect(out[4].range == r(1, 7, 1, 8))
            #expect(out[4].literal == "x")
        }
        // "- [x] x": checked item.
        do {
            let out = try parse("- [x] x")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[2].kind == .item(checked: true))
            #expect(out[4].range == r(1, 7, 1, 8))
            #expect(out[4].literal == "x")
        }
        // "- [ ] é" (2-byte content): text @1:7-1:9.
        do {
            let out = try parse("- [ ] \u{E9}")
            try #require(shape(out) == ["document", "list", "item", "paragraph", "text"])
            #expect(out[2].kind == .item(checked: false))
            #expect(out[1].range == r(1, 1, 1, 9))
            #expect(out[4].range == r(1, 7, 1, 9))
            #expect(out[4].literal == "\u{E9}")
        }
    }

    // MARK: - Indented code

    @Test("indented code — content starts at column 5, end tracks multibyte body width")
    func indentedCode() throws {
        // "    code": indented code block, content @1:5-1:9, body "code\n".
        do {
            let out = try parse("    code")
            try #require(shape(out) == ["document", "codeBlock"])
            let cb = try #require(asCode(out[1].kind))
            #expect(cb.isFenced == false)
            #expect(cb.fenceCharacter == nil)
            #expect(cb.fenceLength == 0)
            #expect(cb.fenceOffset == 0)
            #expect(out[1].range == r(1, 5, 1, 9))
            #expect(out[1].literal == "code\n")   // code-block bodies carry a trailing newline
            #expect(out[1].info == "")
        }
        // "    é code": multibyte body (é = 2 bytes) → line-1 end column 12 (11 bytes + 1).
        do {
            let out = try parse("    \u{E9} code")
            try #require(shape(out) == ["document", "codeBlock"])
            #expect(asCode(out[1].kind)?.isFenced == false)
            #expect(out[1].range == r(1, 5, 1, 12))
            #expect(out[1].literal == "\u{E9} code\n")
        }
    }

    // MARK: - Fenced code

    @Test("fenced code — fence metadata, info string, and body across encodings")
    func fencedCode() throws {
        // "```swift\nlet x = 1\n```": backtick fence, length 3, info "swift", body "let x = 1\n".
        // The code block spans fence-to-fence (@1:1-3:4).
        do {
            let out = try parse("```swift\nlet x = 1\n```")
            try #require(shape(out) == ["document", "codeBlock"])
            let cb = try #require(asCode(out[1].kind))
            #expect(cb.isFenced == true)
            #expect(cb.fenceCharacter == .backtick)
            #expect(cb.fenceLength == 3)
            #expect(cb.fenceOffset == 0)
            #expect(out[1].range == r(1, 1, 3, 4))
            #expect(out[1].info == "swift")
            #expect(out[1].literal == "let x = 1\n")
        }
        // Multibyte info string "```é": info "é", body "code\n".
        do {
            let out = try parse("```\u{E9}\ncode\n```")
            try #require(shape(out) == ["document", "codeBlock"])
            #expect(asCode(out[1].kind)?.isFenced == true)
            #expect(out[1].range == r(1, 1, 3, 4))
            #expect(out[1].info == "\u{E9}")
            #expect(out[1].literal == "code\n")
        }
        // Multibyte body with a combining sequence: empty info, body "e␁ code\n".
        do {
            let out = try parse("```\ne\u{301} code\n```")
            try #require(shape(out) == ["document", "codeBlock"])
            #expect(out[1].range == r(1, 1, 3, 4))
            #expect(out[1].info == "")
            #expect(out[1].literal == "e\u{301} code\n")
        }
        // Multibyte in both info (€) and body (😀): info "€", body "😀\n".
        do {
            let out = try parse("```\u{20AC}\n\u{1F600}\n```")
            try #require(shape(out) == ["document", "codeBlock"])
            #expect(out[1].range == r(1, 1, 3, 4))
            #expect(out[1].info == "\u{20AC}")
            #expect(out[1].literal == "\u{1F600}\n")
        }
    }

    // MARK: - HTML block

    @Test("HTML block — span covers the raw lines, body tracks multibyte content")
    func htmlBlock() throws {
        // "<div>\n</div>": HTML block @1:1-2:7, body includes both lines and a trailing newline.
        do {
            let out = try parse("<div>\n</div>")
            try #require(shape(out) == ["document", "htmlBlock"])
            #expect(out[1].kind == .htmlBlock)
            #expect(out[1].range == r(1, 1, 2, 7))
            #expect(out[1].literal == "<div>\n</div>\n")
        }
        // Multibyte in the first line "<div>é": body carries the multibyte bytes; span unchanged
        // (the block range is line-based, so the second-line end column 7 is stable).
        do {
            let out = try parse("<div>\u{E9}\n</div>")
            try #require(shape(out) == ["document", "htmlBlock"])
            #expect(out[1].range == r(1, 1, 2, 7))
            #expect(out[1].literal == "<div>\u{E9}\n</div>\n")
        }
    }

    // MARK: - Collection / assertion helpers

    /// Build a source range from 1-based line/byte-column endpoints.
    private func r(_ l1: Int, _ c1: Int, _ l2: Int, _ c2: Int) -> Range<Pos> {
        Pos(line: l1, column: c1)..<Pos(line: l2, column: c2)
    }

    /// The kind discriminators of a collected tree, in DFS order — the structural fixture-sanity key.
    private func shape(_ out: [Collected]) -> [String] {
        out.map { tag($0.kind) }
    }

    private func tag(_ k: MarkdownNode.Kind) -> String {
        switch k {
        case .document: "document"
        case .blockQuote: "blockQuote"
        case .list: "list"
        case .item: "item"
        case .codeBlock: "codeBlock"
        case .htmlBlock: "htmlBlock"
        case .customBlock: "customBlock"
        case .paragraph: "paragraph"
        case .heading: "heading"
        case .thematicBreak: "thematicBreak"
        case .footnoteDefinition: "footnoteDefinition"
        case .table: "table"
        case .tableRow: "tableRow"
        case .tableCell: "tableCell"
        case .text: "text"
        case .softBreak: "softBreak"
        case .lineBreak: "lineBreak"
        case .codeInline: "codeInline"
        case .htmlInline: "htmlInline"
        case .customInline: "customInline"
        case .emphasis: "emphasis"
        case .strong: "strong"
        case .link: "link"
        case .image: "image"
        case .footnoteReference: "footnoteReference"
        case .strikethrough: "strikethrough"
        case .attribute: "attribute"
        }
    }

    private func asList(_ k: MarkdownNode.Kind) -> MarkdownNode.ListInfo? {
        if case .list(let i) = k { return i }
        return nil
    }

    private func asCode(_ k: MarkdownNode.Kind) -> MarkdownNode.CodeBlockInfo? {
        if case .codeBlock(let i) = k { return i }
        return nil
    }
}

// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (a `MarkdownNode`
// is `~Escapable`, so it can't be captured by an instance-method closure).
private func collect(
    _ node: borrowing MarkdownNode,
    into out: inout [BlockPositionEncodingTests.Collected]
) {
    out.append(
        BlockPositionEncodingTests.Collected(
            kind: node.kind,
            literal: node.literal(),
            info: node.codeBlockInfoString(),
            range: node.sourceRange
        )
    )
    node.children.forEach { child in
        collect(child, into: &out)
    }
}
