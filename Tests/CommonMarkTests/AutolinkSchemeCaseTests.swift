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
// AutolinkSchemePrecedingCharTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// A GFM `://`-scheme autolink recognizes its scheme (`http`/`https`/`ftp`) case-INSENSITIVELY, and
/// preserves the source case in both the link destination and the visible text.
///
/// cmark-gfm's `sd_autolink_issafe` (`extensions/autolink.c`) validates the rewound scheme run with
/// `strncasecmp`, so `HTTP://`, `Http://`, `hTTp://`, `HTTPS://`, `FTP://` are all recognized. The
/// destination and text come straight from the source chunk (`cmark_chunk_dup`), so the mixed case is
/// preserved verbatim — cmark links the literal text as-is.
@Suite("GFM scheme autolink case-insensitive scheme")
struct AutolinkSchemeCaseTests {

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

    /// Assert that `src` parses to a lone `Link(link)` at the paragraph level whose visible text is `link`
    /// (no preceding `.text` node), i.e. the whole source is one autolink with case preserved.
    private func expectWholeSourceLinks(_ src: String, link: String) throws {
        let ns = try nodes(in: src, options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, link])
        #expect(ns.compactMap(\.url) == [link])
    }

    // MARK: - The fix: the scheme literal matches case-insensitively, source case preserved

    @Test("upper-case `HTTP://` links, preserving case")
    func upperHTTP() throws {
        try expectWholeSourceLinks("HTTP://e", link: "HTTP://e")
    }

    @Test("title-case `Http://` links, preserving case")
    func titleHTTP() throws {
        try expectWholeSourceLinks("Http://e", link: "Http://e")
    }

    @Test("mixed-case `hTTp://` links, preserving case")
    func mixedHTTP() throws {
        try expectWholeSourceLinks("hTTp://e", link: "hTTp://e")
    }

    @Test("upper-case `HTTPS://` links, preserving case")
    func upperHTTPS() throws {
        try expectWholeSourceLinks("HTTPS://x.io", link: "HTTPS://x.io")
    }

    @Test("upper-case `FTP://` links, preserving case")
    func upperFTP() throws {
        try expectWholeSourceLinks("FTP://x.io", link: "FTP://x.io")
    }

    // MARK: - Guards

    @Test("guard: lower-case `http://` still links")
    func lowerHTTP() throws {
        try expectWholeSourceLinks("http://e", link: "http://e")
    }

    @Test("guard: an unrecognized scheme (`xttp://`) does NOT link, case aside")
    func unrecognizedSchemeNoLink() throws {
        // `xttp` is not `http`/`https`/`ftp` in any case, so the scheme is unsafe and nothing links.
        let ns = try nodes(in: "xttp://e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "xttp://e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: the `www.` form stays case-SENSITIVE (`WWW.` does not link)")
    func wwwStaysCaseSensitive() throws {
        // Only the `://`-scheme literal folds case. cmark's `www_match` matches `"www."` with `memcmp`
        // (case-sensitive), so upper-case `WWW.e.f` must NOT autolink even though `www.e.f` does. This
        // pins the asymmetry the fix preserves: `bytesEqual`'s default stays exact for the `www.` caller.
        let ns = try nodes(in: "WWW.e.f", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "WWW.e.f"])
        #expect(ns.compactMap(\.url) == [])
    }
}
