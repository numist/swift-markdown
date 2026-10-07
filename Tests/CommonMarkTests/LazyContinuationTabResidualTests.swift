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
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules.
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// The TAB sibling of `LazyContinuationResidualTests`: the same QUIRK E lazy-continuation-residual
/// behaviour, but where the residual is a leading TAB rather than leading spaces.
///
/// A block quote's continuation line that begins with a TAB has `indent == 4`, so cmark's
/// `parse_block_quote_prefix` fails the `>`-prefix match (`indent <= 3 && first_nonspace == '>'`,
/// blocks.c:943) and the line is a LAZY continuation. cmark's `add_line` (blocks.c:244) copies from
/// `parser->offset` without advancing to the first non-space - and on a lazy line `parser->offset`
/// sits at the line start with no `partially_consumed_tab`, so the LITERAL tab is copied into the
/// paragraph buffer. A LITERAL inline (a code span, or a raw-HTML tag/comment spanning the soft break)
/// then captures that tab, while TEXT does not (the inline parser's `handle_newline` skips leading
/// spaces AND tabs after a soft break).
///
/// Flag-OFF (the shipped, spec-correct parser) strips
/// the residual - identical to a leading-space lazy continuation and to the no-block-quote controls.
@Suite("Lazy-continuation TAB residual in literal inlines")
struct LazyContinuationTabResidualTests {

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

    private func firstHTMLInline(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> String? {
        nodes.first { $0.kind == .htmlInline }?.literal
    }

    // Source shapes. Each block-quote shape's line 2 begins with a TAB (`\t`), making it a LAZY
    // continuation; the no-block-quote controls are top-level MATCHED continuations that strip the tab.
    private static let codeSpanBQ = ">\u{60}\n\t\u{60}"        // `>` `` ` `` LF TAB `` ` ``
    private static let htmlTagBQ = "><i\n\t>"                  // `>` `<i` LF TAB `>`
    private static let htmlCommentBQ = ">0<!--\n\t-->"         // `>` `0<!--` LF TAB `-->`
    private static let codeSpanTop = "\u{60}\n\t\u{60}"        // `` ` `` LF TAB `` ` `` (no block quote)
    private static let htmlTagTop = "<i\n\t>"                  // `<i` LF TAB `>` (no block quote)
    private static let htmlCommentTop = "0<!--\n\t-->"         // `0<!--` LF TAB `-->` (no block quote)

    // MARK: - Flag OFF (shipped): the residual tab is stripped - spec-correct, UNCHANGED

    @Test("flag-OFF: code span across a lazy blockquote continuation STRIPS the residual tab")
    func codeSpanLazyBlockquote_flagOff_stripsTab() throws {
        let nodes = content(Self.codeSpanBQ, Self.specOptions)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == " ")
    }

    @Test("flag-OFF: raw-HTML tag across a lazy blockquote continuation STRIPS the residual tab")
    func htmlTagLazyBlockquote_flagOff_stripsTab() throws {
        let nodes = content(Self.htmlTagBQ, Self.specOptions)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<i\n>")
    }

    @Test("flag-OFF: raw-HTML comment across a lazy blockquote continuation STRIPS the residual tab")
    func htmlCommentLazyBlockquote_flagOff_stripsTab() throws {
        let nodes = content(Self.htmlCommentBQ, Self.specOptions)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<!--\n-->")
    }

    // MARK: - Controls: no block quote => a MATCHED top-level continuation strips the tab under BOTH flags

    @Test("control: no-blockquote code span strips the tab identically under both flags")
    func codeSpanTopLevel_bothFlags_stripTab() throws {
        let nodes = content(Self.codeSpanTop, Self.specOptions)
        let literal = try #require(firstCodeInline(nodes), "fixture must contain a code span")
        #expect(literal == " ")
    }

    @Test("control: no-blockquote raw-HTML tag strips the tab identically under both flags")
    func htmlTagTopLevel_bothFlags_stripTab() throws {
        let nodes = content(Self.htmlTagTop, Self.specOptions)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<i\n>")
    }

    @Test("control: no-blockquote raw-HTML comment strips the tab identically under both flags")
    func htmlCommentTopLevel_bothFlags_stripTab() throws {
        let nodes = content(Self.htmlCommentTop, Self.specOptions)
        let literal = try #require(firstHTMLInline(nodes), "fixture must contain inline HTML")
        #expect(literal == "<!--\n-->")
    }

    // MARK: - TEXT is stripped either way (the carried tab must not bleed into a text node)

    @Test("plain text across the tab lazy continuation stays stripped (both flags)")
    func plainTextLazyBlockquoteTab_staysStripped() {
        // "> a" then "\tb" (lazy continuation, leading tab). The residual tab must NOT reach the second
        // text node: the inline whitespace-skip strips a leading tab from text flow.
        let nodes = content(">a\n\tb", Self.specOptions)
        let texts = nodes.filter { $0.kind == .text }.map { $0.literal }
        #expect(texts == ["a", "b"])
    }
}
