/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A backslash may NOT escape a line ending inside a link destination. In cmark's bare-URL scanner
/// (`manual_scan_link_url_2`, `src/inlines.c`) a `\` is an escape only when the FOLLOWING byte is
/// ASCII punctuation (`cmark_ispunct`); otherwise the `\` is an ordinary destination byte. A link
/// destination therefore never spans a line ending: an odd trailing `\` at the end of the line is a
/// literal destination character and the destination stops at the newline (which the scanner treats
/// as terminating whitespace). This applies identically to the reference-definition destination
/// (`[label]: dest`) and the inline-link destination `(url)`, since both go through the shared
/// `matchLinkDestination`.
///
/// Only an ODD trailing `\` triggers the divergence: an even count ends in an escaped backslash
/// (`\\`, whose second `\` IS punctuation), so the pair is consumed and nothing dangles onto the
/// next line.
@Suite("Link destination trailing backslash")
struct LinkDestinationTrailingBackslashTests {

    /// (destination url, title) of the first `.link` node in DFS order; nil fields if no link exists.
    private func firstLink(_ source: String) throws -> (url: String?, title: String?) {
        try MarkdownDocument.withParsedDocument(source) { doc -> (String?, String?) in
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

    /// Top-level block kinds followed by the inline `(kind, literal)` list of the first block.
    private func blocksAndInlines(
        _ source: String
    ) throws -> (top: [MarkdownNode.Kind], inlines: [(kind: MarkdownNode.Kind, literal: String?)]) {
        try MarkdownDocument.withParsedDocument(source) { doc in
            var top: [MarkdownNode.Kind] = []
            doc.root.children.forEach { top.append($0.kind) }
            return (top, paragraphInlines(doc))
        }
    }

    // MARK: - FIX: an odd trailing backslash does not carry the destination past the line ending

    @Test("ref-def bare trailing backslash consumes only its own line")
    func refDefBareTrailingBackslash() throws {
        // `[b]:\` + newline + `]`: the ref-def destination is a literal `\` (line 1 only); the `]` is
        // a separate paragraph. The bug consumed the `]` line into the destination → empty document.
        let (top, inlines) = try blocksAndInlines("[b]:\\\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("ref-def trailing backslash after text consumes only its own line")
    func refDefTrailingBackslashAfterText() throws {
        // `[b]:a\` + newline + `x`: destination `a\` (line 1); line 2 is its own paragraph `x`.
        let (top, inlines) = try blocksAndInlines("[b]:a\\\nx")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["x"])
    }

    @Test("ref-def trailing backslash after a slash path consumes only its own line")
    func refDefTrailingBackslashSlashPath() throws {
        // `[b]:/u\` + newline + `y`: destination `/u\` (line 1); line 2 is its own paragraph `y`.
        let (top, inlines) = try blocksAndInlines("[b]:/u\\\ny")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["y"])
    }

    @Test("inline-link trailing backslash fails the link and yields a hard break")
    func inlineTrailingBackslash() throws {
        // `[a](/u\` + newline + `x)`: the destination scan stops at the line ending, so the `(` never
        // closes and the link fails. The literal text plus the trailing `\` hard break survive.
        let (top, inlines) = try blocksAndInlines("[a](/u\\\nx)")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text, .lineBreak, .text])
        #expect(inlines.map(\.literal) == ["[a](/u", nil, "x)"])
    }

    // MARK: - GUARD: unchanged behaviors

    @Test("ref-def even trailing backslashes still escape (dest ends in a literal backslash)")
    func refDefEvenTrailingBackslashes() throws {
        // `[b]:a\\` + newline + `]`: the two backslashes are an escaped `\`, so nothing dangles; the
        // destination is `a\` (line 1) and the `]` is its own paragraph.
        let (top, inlines) = try blocksAndInlines("[b]:a\\\\\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("ref-def backslash mid-destination is unchanged")
    func refDefBackslashMidDestination() throws {
        // `[b]:a\b` + newline + `]`: the `\b` is interior; destination is `a\b` (line 1), `]` is its
        // own paragraph.
        let (top, inlines) = try blocksAndInlines("[b]:a\\b\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("ref-def with a plain destination is unchanged")
    func refDefPlainDestination() throws {
        // `[b]: x` + newline + `]`: destination `x` (line 1), `]` is its own paragraph.
        let (top, inlines) = try blocksAndInlines("[b]: x\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("ref-def with a lone trailing backslash and no next line is a valid definition")
    func refDefLoneTrailingBackslash() throws {
        // `[b]:\` with no following line: a valid ref-def (destination `\`) with no visible output.
        let (top, _) = try blocksAndInlines("[b]:\\")
        #expect(top == [])
    }

    @Test("inline link whose destination line ends in a backslash then a bare close paren")
    func inlineTrailingBackslashThenCloseParen() throws {
        // `[a](/u\` + newline + `)`: the destination stops at the line ending (`/u\`), the following
        // spacechars skip the newline, and the `)` closes the link — a link with destination `/u\`.
        #expect(try firstLink("[a](/u\\\n)").url == "/u\\")
    }
}
