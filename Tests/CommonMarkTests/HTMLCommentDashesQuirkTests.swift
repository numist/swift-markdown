/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark-gfm scans an inline HTML comment with the stricter grammar in `scanners.re`
/// (`htmlcomment = "--" ([^\x00-]+ | "-" [^\x00-] | "--" [^\x00>])* "-->"`, via `_scan_html_comment`),
/// which is narrower than CommonMark 0.31 "`<!--`, then any run not containing `-->`, then `-->`". The
/// two disagree on `<!----->`: 0.31 reads the body as `-` (containing no `-->`) closed by `-->`, so the
/// deliverable recognizes a comment; cmark's grammar cannot decompose the three interior dashes into a
/// body element that leaves a lone `-->` closer, so it rejects it and the text stays literal.
///
/// The shipped deliverable (flag OFF) stays spec-correct (0.31): `<!----->` is an
/// inline HTML comment. These tests parse without `.sourcePosition`.
@Suite("HTML comment cmark stricter-dash-rule quirk")
struct HTMLCommentDashesQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []

    /// Parse `src` and return the first `.htmlInline` literal (or nil if none) plus the concatenated
    /// `.text` literals of the first paragraph. The leading `F` in every fixture must survive as text, so
    /// a degenerate (empty) tree fails the sanity `#require` instead of passing vacuously.
    private func parse(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (html: String?, text: String) {
        let inlines: [(kind: MarkdownNode.Kind, literal: String?)] =
            MarkdownDocument.withParsedDocument(src, options: options) { doc in
                paragraphInlines(doc)
            }
        let text = inlines.filter { $0.kind == .text }.compactMap(\.literal).joined()
        try #require(text.contains("F"), "fixture vacuous: leading text 'F' not parsed")
        let html = inlines.first { $0.kind == .htmlInline }.flatMap(\.literal)
        return (html, text)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (CommonMark 0.31)

    @Test("flag OFF: `<!----->` (five dashes) IS an inline HTML comment")
    func flagOffFiveDashesRecognized() throws {
        #expect(try parse("F<!----->", options: Self.flagOff).html == "<!----->")
    }

    // MARK: Agreeing controls

    @Test("both flags: `<!---->` (four dashes) is a comment")
    func fourDashesRecognized() throws {
        #expect(try parse("F<!---->", options: Self.flagOff).html == "<!---->")
    }

    @Test("both flags: `<!--->` (three dashes, empty form) is a comment")
    func threeDashesRecognized() throws {
        #expect(try parse("F<!--->", options: Self.flagOff).html == "<!--->")
    }

    @Test("both flags: `<!-->` (two dashes, empty form) is a comment")
    func twoDashesRecognized() throws {
        #expect(try parse("F<!-->", options: Self.flagOff).html == "<!-->")
    }

    @Test("both flags: `<!--x-->` is a comment")
    func normalCommentRecognized() throws {
        #expect(try parse("F<!--x-->", options: Self.flagOff).html == "<!--x-->")
    }

    @Test("both flags: `<!-- -->` is a comment")
    func spaceCommentRecognized() throws {
        #expect(try parse("F<!-- -->", options: Self.flagOff).html == "<!-- -->")
    }
}
