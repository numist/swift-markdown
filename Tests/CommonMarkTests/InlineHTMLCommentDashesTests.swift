/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// An HTML comment (Raw HTML) is `<!--`, text not containing `-->`, and `-->`, so `<!----->` is a comment whose text
/// is `-`.
@Suite("Inline HTML comments made of dashes")
struct InlineHTMLCommentDashesTests {

    private static let options: MarkdownDocument.ParseOptions = []

    /// The first raw HTML literal in the first paragraph, if any, and the paragraph's concatenated text.
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

    @Test("`<!----->` (five dashes) is an inline HTML comment")
    func fiveDashesRecognized() throws {
        #expect(try parse("F<!----->", options: Self.options).html == "<!----->")
    }

    @Test("`<!---->` (four dashes) is a comment")
    func fourDashesRecognized() throws {
        #expect(try parse("F<!---->", options: Self.options).html == "<!---->")
    }

    @Test("`<!--->` (three dashes, empty form) is a comment")
    func threeDashesRecognized() throws {
        #expect(try parse("F<!--->", options: Self.options).html == "<!--->")
    }

    @Test("`<!-->` (two dashes, empty form) is a comment")
    func twoDashesRecognized() throws {
        #expect(try parse("F<!-->", options: Self.options).html == "<!-->")
    }

    @Test("`<!--x-->` is a comment")
    func normalCommentRecognized() throws {
        #expect(try parse("F<!--x-->", options: Self.options).html == "<!--x-->")
    }

    @Test("`<!-- -->` is a comment")
    func spaceCommentRecognized() throws {
        #expect(try parse("F<!-- -->", options: Self.options).html == "<!-- -->")
    }
}
