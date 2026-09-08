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

/// A GFM `://`-scheme autolink fires after ANY non-alpha preceding character, not just the small
/// `www.` boundary set.
///
/// cmark-gfm's `url_match` (`extensions/autolink.c`) recognizes a `scheme://…` autolink by rewinding
/// over the ASCII-alpha scheme letters immediately before `://` (`while (rewind < max_rewind &&
/// cmark_isalpha(data[-rewind-1])) rewind++;`) and then validating the rewound run as a safe scheme
/// (`sd_autolink_issafe` → `http`/`https`/`ftp`). The scheme is simply delimited by the first non-alpha
/// byte, so the character *before* the scheme may be ANYTHING that is not an ASCII letter — a digit,
/// punctuation, a byte of a non-ASCII character, or the content start. Only an ASCII letter blocks the
/// match, because it would extend the rewind and make the scheme unsafe.
///
/// This is stricter for the `www.` form (`www_match`) and the email form (`postprocess_text`), which do
/// restrict the preceding character; those are covered elsewhere and must not change here. `cmark_isalpha`
/// is ASCII-only (ctype class 4 = `a`–`z`/`A`–`Z`), so a non-ASCII byte ends the scheme rewind and the
/// autolink still fires.
@Suite("GFM scheme autolink preceding-character")
struct AutolinkSchemePrecedingCharTests {

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

    /// Assert that `src` parses to a leading `.text` node with literal `prefix` followed by a
    /// `Link(http://e)` whose visible text is `http://e`.
    private func expectPrefixThenLink(_ src: String, prefix: String) throws {
        let ns = try nodes(in: src, options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, prefix, nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    // MARK: - The fix: any non-alpha char before the scheme still autolinks

    @Test("scheme autolinks after `!`")
    func afterBang() throws {
        try expectPrefixThenLink("!http://e", prefix: "!")
    }

    @Test("scheme autolinks after `.`")
    func afterDot() throws {
        try expectPrefixThenLink(".http://e", prefix: ".")
    }

    @Test("scheme autolinks after a digit")
    func afterDigit() throws {
        // A digit is non-alpha, so it ends the scheme rewind — cmark links.
        try expectPrefixThenLink("9http://e", prefix: "9")
    }

    @Test("scheme autolinks after `-`")
    func afterHyphen() throws {
        try expectPrefixThenLink("-http://e", prefix: "-")
    }

    @Test("scheme autolinks after `/`")
    func afterSlash() throws {
        try expectPrefixThenLink("/http://e", prefix: "/")
    }

    @Test("scheme autolinks after a non-ASCII letter")
    func afterNonASCIILetter() throws {
        // cmark's `cmark_isalpha` is ASCII-only, so the non-ASCII bytes of `é` end the scheme rewind.
        try expectPrefixThenLink("éhttp://e", prefix: "é")
    }

    @Test("scheme autolinks after a NUL (replaced with U+FFFD)")
    func afterNUL() throws {
        // NUL → U+FFFD before inline scanning; U+FFFD's last byte is non-alpha, so the rewind stops and the
        // autolink fires. The `before` text node carries the replacement character.
        try expectPrefixThenLink("\u{0}http://e", prefix: "\u{FFFD}")
    }

    // MARK: - Guards: an ASCII letter before the scheme still blocks the match

    @Test("guard: an ASCII letter before the scheme does NOT autolink")
    func alphaBeforeSchemeNoLink() throws {
        // `xhttp://e` — the `x` is ASCII-alpha, so cmark's rewind swallows it into the scheme (`xhttp`),
        // which is not a safe scheme, so no link. Whole thing stays plain text.
        let ns = try nodes(in: "xhttp://e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "xhttp://e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: scheme autolinks after `(` (was already allowed)")
    func afterParen() throws {
        try expectPrefixThenLink("(http://e", prefix: "(")
    }

    @Test("guard: scheme autolinks after a leading space (was already allowed)")
    func afterLeadingSpace() throws {
        // The paragraph's leading space is stripped, so the scheme sits at the content start (no `before`
        // text node). It must still link.
        let ns = try nodes(in: " http://e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    // MARK: - Guard: the `www.` form keeps its narrow preceding-char restriction

    @Test("guard: `www.` form does not autolink after `!` (only the scheme form relaxed)")
    func wwwAfterBangUnchanged() throws {
        // `!www.e.f` — `www_match` restricts its preceding char to the `*_~(`/whitespace set, so `!` blocks
        // the `www.` autolink. This must be untouched by relaxing the scheme form.
        let ns = try nodes(in: "!www.e.f", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "!www.e.f"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: `www.` form still autolinks after `(`")
    func wwwAfterParenUnchanged() throws {
        let ns = try nodes(in: "(www.e.f", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "(", nil, "www.e.f"])
        #expect(ns.compactMap(\.url) == ["http://www.e.f"])
    }
}
