/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends each node's kind and literal content, `nil` for a container, to `out` in document order.
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// A paragraph's raw content strips each line's initial whitespace (Paragraphs), including a tab that begins a lazy
/// continuation line (Block quotes), so a code span or raw HTML that crosses the line ending holds no tab.
@Suite("Leading tab of a lazy continuation line in literal inlines")
struct LazyContinuationTabResidualTests {

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

    private func firstHTMLInline(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> String? {
        nodes.first { $0.kind == .htmlInline }?.literal
    }

    // Line 2 of each input begins with a tab. In a block quote it is a lazy continuation line; at the top level it
    // is an ordinary paragraph continuation line.
    private static let codeSpanBQ = ">\u{60}\n\t\u{60}"        // `>` `` ` `` LF TAB `` ` ``
    private static let htmlTagBQ = "><i\n\t>"                  // `>` `<i` LF TAB `>`
    private static let htmlCommentBQ = ">0<!--\n\t-->"         // `>` `0<!--` LF TAB `-->`
    private static let codeSpanTop = "\u{60}\n\t\u{60}"        // `` ` `` LF TAB `` ` `` (no block quote)
    private static let htmlTagTop = "<i\n\t>"                  // `<i` LF TAB `>` (no block quote)
    private static let htmlCommentTop = "0<!--\n\t-->"         // `0<!--` LF TAB `-->` (no block quote)

    // MARK: - Lazy continuation lines

    @Test("a code span across a lazy continuation line drops the leading tab")
    func codeSpanAcrossLazyLine_stripsTab() throws {
        let nodes = content(Self.codeSpanBQ, Self.options)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == " ")
    }

    @Test("a raw HTML tag across a lazy continuation line drops the leading tab")
    func htmlTagAcrossLazyLine_stripsTab() throws {
        let nodes = content(Self.htmlTagBQ, Self.options)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<i\n>")
    }

    @Test("a raw HTML comment across a lazy continuation line drops the leading tab")
    func htmlCommentAcrossLazyLine_stripsTab() throws {
        let nodes = content(Self.htmlCommentBQ, Self.options)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<!--\n-->")
    }

    // MARK: - Top-level continuation lines

    @Test("a top-level code span across a line ending drops the leading tab")
    func codeSpanTopLevel_stripsTab() throws {
        let nodes = content(Self.codeSpanTop, Self.options)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == " ")
    }

    @Test("a top-level raw HTML tag across a line ending drops the leading tab")
    func htmlTagTopLevel_stripsTab() throws {
        let nodes = content(Self.htmlTagTop, Self.options)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<i\n>")
    }

    @Test("a top-level raw HTML comment across a line ending drops the leading tab")
    func htmlCommentTopLevel_stripsTab() throws {
        let nodes = content(Self.htmlCommentTop, Self.options)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<!--\n-->")
    }

    // MARK: - Text

    @Test("text on a lazy continuation line drops the leading tab")
    func plainTextLazyBlockquoteTab_staysStripped() {
        let nodes = content(">a\n\tb", Self.options)
        let texts = nodes.filter { $0.kind == .text }.map { $0.literal }
        #expect(texts == ["a", "b"])
    }
}
