/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Link-destination whitespace trimming, matching cmark's `cmark_clean_url` (`src/inlines.c`):
/// "Clean a URL: remove surrounding whitespace, and remove `\` that escape punctuation." It does
/// BOTH a `cmark_chunk_trim` (strip leading/trailing whitespace) AND backslash-escape / entity
/// removal. The rewrite already did the escape removal (`unescapeURLChunk`) but not the trim, so an
/// angle-bracket destination kept its surrounding whitespace. Both destination sites — the inline
/// link `(url "title")` and the `[label]: dest` reference definition — build the destination the same
/// way, so both diverged identically.
///
/// The trim uses cmark's `cmark_isspace` set = {space, tab, `\n`, `\r`} (the `cmark_ctype_class`
/// table's class-1 bytes; it does NOT include VT/FF), matched here by the `isSpaceTabOrNewline`
/// predicate via `Chunk.trimming(using:)`. INTERIOR whitespace is preserved. Titles use
/// `cmark_clean_title`, which does NOT trim, so the title path is deliberately untouched.
@Suite("Link destination whitespace trimming")
struct LinkDestinationTrimTests {

    /// (destination url, title) of the first `.link` node in DFS order; nil fields if no link exists.
    /// Reads each node's `url()`/`title()` projection, forcing the arena/source materialization of the
    /// destination and title chunks.
    private func firstLink(
        _ source: String, options: MarkdownDocument.ParseOptions = []
    ) throws -> (url: String?, title: String?) {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> (String?, String?) in
            var found = false
            var url: String? = nil
            var title: String? = nil
            func walk(_ node: borrowing MarkdownNode) {
                if node.kind == .link, !found {
                    found = true
                    url = node.url()
                    title = node.title()
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (url, title)
        }
    }

    // MARK: - FIX: inline-link destination whitespace is trimmed

    @Test("all-whitespace angle destination trims to empty (single space)")
    func inlineAllWhitespaceSingle() throws {
        #expect(try firstLink("[](< >)").url == "")
    }

    @Test("all-whitespace angle destination trims to empty (two spaces)")
    func inlineAllWhitespaceDouble() throws {
        #expect(try firstLink("[](<  >)").url == "")
    }

    @Test("leading whitespace is trimmed")
    func inlineLeadingTrimmed() throws {
        #expect(try firstLink("[](< a>)").url == "a")
    }

    @Test("trailing whitespace is trimmed")
    func inlineTrailingTrimmed() throws {
        #expect(try firstLink("[](<a >)").url == "a")
    }

    @Test("leading whitespace is trimmed AND the escape is still removed")
    func inlineLeadingTrimAndUnescape() throws {
        // `< \!a>`: after trimming the leading space, `\!` unescapes to `!` → "!a".
        #expect(try firstLink("[](< \\!a>)").url == "!a")
    }

    // MARK: - FIX: reference-definition destination whitespace is trimmed (same helper)

    @Test("ref-def leading whitespace is trimmed")
    func refDefLeadingTrimmed() throws {
        #expect(try firstLink("[x]: < a>\n\n[x]").url == "a")
    }

    @Test("ref-def all-whitespace destination trims to empty")
    func refDefAllWhitespace() throws {
        #expect(try firstLink("[x]: < >\n\n[x]").url == "")
    }

    // MARK: - LEAVE: interior whitespace is preserved

    @Test("interior whitespace in an inline destination is kept")
    func inlineInteriorKept() throws {
        #expect(try firstLink("[](<a b>)").url == "a b")
    }

    @Test("interior whitespace in a ref-def destination is kept")
    func refDefInteriorKept() throws {
        #expect(try firstLink("[x]: <a b>\n\n[x]").url == "a b")
    }

    // MARK: - LEAVE: backslash-escape removal is unaffected

    @Test("angle destination backslash-escape removal still works")
    func angleEscapeRemoval() throws {
        // `<a\>b>`: the escaped `>` is part of the destination and unescapes to `>`.
        #expect(try firstLink("[](<a\\>b>)").url == "a>b")
    }

    @Test("bare destination backslash-escape removal still works")
    func bareEscapeRemoval() throws {
        #expect(try firstLink("[](a\\)b)").url == "a)b")
    }

    // MARK: - LEAVE: titles are NOT trimmed (cmark_clean_title has no trim)

    @Test("a title with no surrounding space is unaffected")
    func titleNoSpaceUnaffected() throws {
        let link = try firstLink("[](<a> \"t\")")
        #expect(link.url == "a")
        #expect(link.title == "t")
    }

    @Test("surrounding whitespace inside a title is preserved (trim is destination-only)")
    func titleSurroundingSpacePreserved() throws {
        // cmark_clean_title does not trim, so the title keeps its interior spaces; only the
        // destination is trimmed.
        let link = try firstLink("[](<a> \" t \")")
        #expect(link.url == "a")
        #expect(link.title == " t ")
    }
}
