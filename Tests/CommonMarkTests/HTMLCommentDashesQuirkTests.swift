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
/// This is a `[ref-b4b]` quirk reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). The shipped deliverable (flag OFF) stays spec-correct (0.31): `<!----->` is an
/// inline HTML comment. Comment recognition is STRUCTURAL (an `.htmlInline` node vs literal `.text`), so
/// it is gated on the flag alone; these tests parse without `.sourcePosition`. Smart punctuation is left
/// OFF so the rejected form stays plain literal text (not smart dashes), isolating the recognition change.
@Suite("HTML comment cmark stricter-dash-rule quirk")
struct HTMLCommentDashesQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    /// Parse `src` and return the first `.htmlInline` literal (or nil if none) plus the concatenated
    /// `.text` literals of the first paragraph. The leading `F` in every fixture must survive as text, so
    /// a degenerate (empty) tree fails the sanity `#require` instead of passing vacuously.
    private func parse(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (html: String?, text: String) {
        let inlines: [(kind: MarkdownNode.Kind, literal: String?)] =
            try MarkdownDocument.withParsedDocument(src, options: options) { doc in
                paragraphInlines(doc)
            }
        let text = inlines.filter { $0.kind == .text }.compactMap(\.literal).joined()
        try #require(text.contains("F"), "fixture vacuous: leading text 'F' not parsed")
        let html = inlines.first { $0.kind == .htmlInline }.flatMap(\.literal)
        return (html, text)
    }

    // MARK: Flag ON — reproduce cmark's rejection of `<!----->`

    @Test("flag ON: `<!----->` (five dashes) is NOT a comment; stays literal text")
    func flagOnFiveDashesRejected() throws {
        let result = try parse("F<!----->", options: Self.flagOn)
        #expect(result.html == nil)
        #expect(result.text.contains("<!----->"))
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (CommonMark 0.31)

    @Test("flag OFF: `<!----->` (five dashes) IS an inline HTML comment")
    func flagOffFiveDashesRecognized() throws {
        #expect(try parse("F<!----->", options: Self.flagOff).html == "<!----->")
    }

    // MARK: Agreeing controls — recognized identically under BOTH flags

    @Test("both flags: `<!---->` (four dashes) is a comment", arguments: [Self.flagOff, Self.flagOn])
    func fourDashesRecognized(options: MarkdownDocument.ParseOptions) throws {
        #expect(try parse("F<!---->", options: options).html == "<!---->")
    }

    @Test("both flags: `<!--->` (three dashes, empty form) is a comment", arguments: [Self.flagOff, Self.flagOn])
    func threeDashesRecognized(options: MarkdownDocument.ParseOptions) throws {
        #expect(try parse("F<!--->", options: options).html == "<!--->")
    }

    @Test("both flags: `<!-->` (two dashes, empty form) is a comment", arguments: [Self.flagOff, Self.flagOn])
    func twoDashesRecognized(options: MarkdownDocument.ParseOptions) throws {
        #expect(try parse("F<!-->", options: options).html == "<!-->")
    }

    @Test("both flags: `<!--x-->` is a comment", arguments: [Self.flagOff, Self.flagOn])
    func normalCommentRecognized(options: MarkdownDocument.ParseOptions) throws {
        #expect(try parse("F<!--x-->", options: options).html == "<!--x-->")
    }

    @Test("both flags: `<!-- -->` is a comment", arguments: [Self.flagOff, Self.flagOn])
    func spaceCommentRecognized(options: MarkdownDocument.ParseOptions) throws {
        #expect(try parse("F<!-- -->", options: options).html == "<!-- -->")
    }
}
