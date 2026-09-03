/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Structure of a *whitespace-only run before a trailing-space hard break* (2+ spaces then a newline).
///
/// This is the hard-break counterpart of `EmptyTextBeforeSoftBreakTests`. cmark-gfm's text-flush path
/// (`src/inlines.c` `parse_inline`) creates a `.text` node from the trailing-whitespace run and
/// `cmark_chunk_rtrim` strips it to empty, leaving the empty node in the tree with its pre-strip range.
/// That flush runs BEFORE `handle_newline` classifies the break, so cmark emits the empty node the same
/// way whether the break is soft or a trailing-space hard break. When the empty node follows a text run
/// (e.g. a literal `]`) `cmark_consolidate_text_nodes` merges it in, extending the text's end column over
/// the stripped spaces; after a non-text inline it survives as a standalone empty `Text`. Both are the
/// `.cmarkBugCompatibility` quirk, covered flag-on by the `brkhb-*` fuzzer regression pairs. This suite
/// is the flag-off guardrail proving the shipped (spec-correct) parser drops the whitespace-only run: no
/// empty text node survives, and a literal `]` before the break keeps its 1-character source range.
@Suite("Empty text before hard break (spec-correct)")
struct EmptyTextBeforeHardBreakTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The `(kind, text)` of every node in DFS order when `src` is parsed spec-correct.
    private func nodes(in src: String) throws -> [(kind: MarkdownNode.Kind, text: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, text: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindsAndText(doc.root, into: &out)
            return out
        }
    }

    /// The source ranges of every text node, in DFS order, when `src` is parsed spec-correct.
    private func textRanges(in src: String) throws -> [Range<Pos>?] {
        let ranges = try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.filter { $0.kind == .text }.map { $0.range }
    }

    @Test("literal ] before a hard break keeps its 1-character range")
    func bracketLiteral() throws {
        // `]` then two trailing spaces then a hard break then `]`. Spec-correct, the whitespace-only run
        // after the `]` is dropped: the first `]` keeps its 1-character range @1:1-1:2, NOT extended over
        // the trailing spaces. (Flag-on the `brkhb-min` pair asserts cmark's @1:1-1:4, the `]` merged with
        // the empty stripped-whitespace node.)
        let ns = try nodes(in: "]  \n]")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["]", "]"])
        let texts = try textRanges(in: "]  \n]")
        try #require(texts.count == 2)
        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 1))   // first "]"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 2))   // 1-char end, spaces excluded
    }

    @Test("emphasis + trailing spaces + hard break: no empty text node")
    func emphasis() throws {
        // `*x*` then two trailing spaces then a hard break then `y`. Spec-correct: Emphasis, LineBreak,
        // Text "y" - no empty Text in between. (Flag-on the `brkhb-emph` pair asserts the empty
        // `Text @1:4-1:6` between the emphasis and the break.)
        let ns = try nodes(in: "*x*  \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["x", "y"])
    }

    @Test("inline code + trailing spaces + hard break: no empty text node")
    func inlineCode() throws {
        // `` `c` `` then two trailing spaces then a hard break then `y`. Spec-correct: InlineCode,
        // LineBreak, Text "y" - no empty Text. (Flag-on the `brkhb-code` pair asserts the empty node.)
        let ns = try nodes(in: "`c`  \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1), .lineBreak, .text])
        // `literal()` reads inline-code content as text too, so the code "c" appears alongside "y";
        // the point is that no empty "" run survives between the code span and the break.
        #expect(ns.compactMap(\.text) == ["c", "y"])
    }

    @Test("link + trailing spaces + hard break: no empty text node")
    func link() throws {
        // A `[foo]` shortcut-reference link, two trailing spaces, a hard break, then `[]` on line 2.
        // Spec-correct: Link (with its "foo" text), LineBreak, Text "[]" - no empty Text after the link.
        // (Flag-on the `brkhb-link` pair asserts the empty `Text @1:6-1:8` after the link.)
        let ns = try nodes(in: "[foo]  \n[]\n\n[foo]: /url \"title\"")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .lineBreak, .text])
        #expect(ns.compactMap(\.text) == ["foo", "[]"])
    }
}
