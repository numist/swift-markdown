/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind, text literal, and (for links) destination URL. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// AutolinkEmailPrecedingCharTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// A GFM bare-URL autolink (`://`-scheme, `www.`) is NOT recognized while an unclosed `[`/`![`
/// link/image opener is on the bracket stack.
///
/// cmark-gfm's autolink extension declines to match in this context: `match` (`extensions/autolink.c`)
/// bails with `if (cmark_inline_parser_in_bracket(inline_parser, false) ||
/// cmark_inline_parser_in_bracket(inline_parser, true)) return NULL;`, so a `://`-scheme (or `www.`)
/// autolink is suppressed whenever a LINK (`[`) or IMAGE (`![`) bracket opener is still open on the
/// delimiter/bracket stack. An unclosed `[` therefore keeps `http://t` as plain text — even though the
/// bare `http://t` on its own autolinks fine, and even though cmark otherwise accepts a non-alpha
/// preceding character for scheme autolinks. The `^[` (ATTRIBUTE) opener does not suppress; only
/// LINK/IMAGE do. The email post-pass (`postprocess_text`) is a separate path and runs after brackets
/// have collapsed to literal text, so it is unaffected.
@Suite("GFM autolink suppressed inside open bracket")
struct AutolinkBracketOpenerTests {

    /// The shipped configuration: GFM autolink on, bug-compatibility deliberately off.
    private static let flagOff: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - The fix: an unclosed `[` opener suppresses the scheme autolink

    @Test("unclosed `[` before a scheme URL leaves it as plain text (no link)")
    func openBracketSuppressesSchemeAutolink() throws {
        // The fuzzer finding: `[http://t` — the `[` pushes a LINK opener that never closes, so cmark's
        // autolink extension declines. The whole run is one plain text node; NO link is produced.
        let ns = try nodes(in: "[http://t", options: Self.flagOff)
        // Fixture sanity: a degenerate/empty tree (e.g. just `[.document]`) must not pass vacuously.
        #expect(ns.count == 3)
        #expect(!ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "[http://t"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("unclosed `![` image opener also suppresses the scheme autolink")
    func openImageBracketSuppressesSchemeAutolink() throws {
        // `![` pushes an IMAGE opener; cmark checks `in_bracket(IMAGE)` too.
        let ns = try nodes(in: "![http://t", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "![http://t"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Controls: the fix must not kill legitimate autolinks

    @Test("control: a bare scheme URL with no leading `[` still autolinks")
    func bareSchemeStillAutolinks() throws {
        let ns = try nodes(in: "http://t", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://t"])
        #expect(ns.compactMap(\.url) == ["http://t"])
    }

    @Test("control: a normal closed link `[x](http://t)` still parses as a link")
    func closedLinkStillParses() throws {
        let ns = try nodes(in: "[x](http://t)", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "x"])
        #expect(ns.compactMap(\.url) == ["http://t"])
    }

    @Test("control: once the `[…]` closes, a following scheme URL autolinks again")
    func afterClosedBracketAutolinks() throws {
        // `[a] http://t` — the bracket closes (as literal `[a]`, no matching def), so the opener is popped
        // before the `:` is reached and the autolink is no longer suppressed.
        let ns = try nodes(in: "[a] http://t", options: Self.flagOff)
        #expect(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://t"])
    }
}
