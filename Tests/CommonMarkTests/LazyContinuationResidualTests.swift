/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Appends each node's kind and literal to `out` in document order.
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// A paragraph's raw content drops each line's initial whitespace (Paragraphs), including that of a lazy continuation
/// line, so a code span crossing onto one holds no whitespace from it.
@Suite("Leading whitespace of a lazy continuation line in a code span")
struct LazyContinuationResidualTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

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

    @Test("two leading spaces on a block quote's lazy continuation line are stripped")
    func codeSpanLazyBlockquote_twoSpaces() throws {
        let nodes = content("> `x\n  y`", Self.options)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("the leading space on a list item's lazy continuation line is stripped")
    func codeSpanLazyList_stripsResidual() throws {
        let nodes = content("- `x\n y`", Self.options)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("the leading space on a block quote's lazy continuation line is stripped")
    func codeSpanLazyBlockquote_stripsResidual() {
        let nodes = content("> `x\n y`", Self.options)
        #expect(firstCodeInline(nodes) == "x y")
    }

    @Test("plain text on a lazy continuation line is stripped")
    func plainTextLazyContinuation_staysStripped() {
        let nodes = content("> a\n b", Self.options)
        let texts = nodes.filter { $0.kind == .text }.map { $0.literal }
        #expect(texts == ["a", "b"])
    }
}
