/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind and text literal. File-scope + `borrowing MarkdownNode` to satisfy
// the noncopyable-borrow rules (see SourcePositionTests.dfsRanges).
internal func dfsKindsAndText(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsKindsAndText(child, into: &out)
    }
}

/// Structure of a *whitespace-only run before a soft break* when it follows a non-text inline
/// (link / emphasis / inline code).
///
/// cmark-gfm's text-flush path (`src/inlines.c` `parse_inline`) creates a `.text` node from the run,
/// then `cmark_chunk_rtrim` strips its content to empty at the line-end char but leaves the now-empty
/// node in the tree carrying its pre-strip source range. So cmark emits an empty `Text` spanning the
/// trailing whitespace between the inline and the break. That empty node is the `.cmarkBugCompatibility`
/// quirk, covered flag-on by the `emptytext-*` fuzzer regression pairs. This suite is the flag-off
/// guardrail proving the shipped (spec-correct) parser drops the whitespace-only run: no empty text
/// node survives between the inline and the soft break.
@Suite("Empty text before soft break (spec-correct)")
struct EmptyTextBeforeSoftBreakTests {

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

    @Test("emphasis + trailing space + soft break: no empty text node")
    func emphasis() throws {
        // `*x*` then a trailing space then a soft break then `y`. Spec-correct, the whitespace-only run
        // after the emphasis is dropped: Emphasis, SoftBreak, Text "y" - no empty Text in between.
        // (Flag-on the `emptytext-emph` pair asserts cmark's empty `Text @1:4-1:5` between them.)
        let ns = try nodes(in: "*x* \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["x", "y"])
    }

    @Test("inline code + trailing space + soft break: no empty text node")
    func inlineCode() throws {
        // `` `c` `` then a trailing space then a soft break then `y`. Spec-correct: InlineCode, SoftBreak,
        // Text "y" - no empty Text. (Flag-on the `emptytext-code` pair asserts the empty node.)
        let ns = try nodes(in: "`c` \ny")
        #expect(ns.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1), .softBreak, .text])
        // `literal()` reads inline-code content as text too, so the code "c" appears alongside "y";
        // the point is that no empty "" run survives between the code span and the break.
        #expect(ns.compactMap(\.text) == ["c", "y"])
    }

    @Test("link + trailing space + soft break: no empty text node")
    func link() throws {
        // A `[foo]` shortcut-reference link, a trailing space, a soft break, then `[]` on line 2.
        // Spec-correct: Link (with its "foo" text), SoftBreak, Text "[]" - no empty Text after the link.
        // (Flag-on the `emptytext-link` pair asserts the empty `Text @1:6-1:7` after the link.)
        let ns = try nodes(in: "[foo] \n[]\n\n[foo]: /url \"title\"")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .softBreak, .text])
        #expect(ns.compactMap(\.text) == ["foo", "[]"])
    }
}
