/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind and owned literal content (nil for structural nodes). File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see `dfsRanges`).
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// A LAZY paragraph continuation (a container prefix failed to match — a block quote with no `>`, or a
/// list line indented below its content column) keeps the residual leading whitespace after the last
/// matched prefix in cmark's paragraph buffer: `add_line` copies from `parser->offset` without advancing
/// to the first non-space (blocks.c:1408), unlike a MATCHED continuation (blocks.c:1465). A LITERAL inline
/// — a code span — then captures that residual, while TEXT does not (cmark's inline `handle_newline`
/// strips leading whitespace after a soft break).
///
/// The spec skips leading whitespace on every paragraph continuation line, so the shipped parser stays
/// spec-correct (residual stripped). TEXT is stripped either way. This suite is the deliverable-facing spec assertion.
@Suite("Lazy-continuation residual in code-span content")
struct LazyContinuationResidualTests {

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func content(_ src: String, _ options: MarkdownDocument.ParseOptions) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc in
            var out: [(kind: MarkdownNode.Kind, literal: String?)] = []
            dfsContent(doc.root, into: &out)
            return out
        }
    }

    private func firstCodeInline(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> String? {
        nodes.first { if case .codeInline = $0.kind { return true } else { return false } }?.literal
    }

    @Test("flag-OFF (shipped): two residual spaces are stripped — spec-correct")
    func codeSpanLazyBlockquote_flagOff_twoSpaces() throws {
        // The deliverable strips the residual leading
        // whitespace regardless of its width, so the span content is `x` + (newline→space) + `y`.
        let nodes = content("> `x\n  y`", Self.specOptions)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("flag-OFF (shipped): the lazy LIST continuation residual is stripped — spec-correct")
    func codeSpanLazyList_flagOff_stripsResidual() throws {
        // Same spec-correct stripping as the block-quote
        // case, over a LIST container: `x` + (newline→space) + `y`.
        let nodes = content("- `x\n y`", Self.specOptions)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("flag-OFF (shipped): the residual is stripped — spec-correct")
    func codeSpanLazyBlockquote_flagOff_stripsResidual() {
        // The deliverable parser skips leading whitespace on every continuation line (spec), so the code
        // span content is the same as if line 2 began at its first non-space: `x` + (newline→space) + `y`.
        let nodes = content("> `x\n y`", Self.specOptions)
        #expect(firstCodeInline(nodes) == "x y")
    }

    @Test("plain text across the same lazy continuation stays stripped (both flags)")
    func plainTextLazyContinuation_staysStripped() {
        // "> a" then " b" (lazy continuation, one leading space). The residual must NOT bleed into the
        // second text node: TEXT is `a`, a soft break, then `b` (not " b").
        let nodes = content("> a\n b", Self.specOptions)
        let texts = nodes.filter { $0.kind == .text }.map { $0.literal }
        #expect(texts == ["a", "b"])
    }
}
