/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A CDATA section (Raw HTML) runs to the first `]]>`, so content ending in `]` before the closer, as in
/// `<![CDATA[x]]]>`, is part of the section.
@Suite("Inline CDATA section ending in a bracket")
struct InlineCDATATrailingBracketTests {

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
        try #require(text.contains("o"), "fixture vacuous: leading text 'o' not parsed")
        let html = inlines.first { $0.kind == .htmlInline }.flatMap(\.literal)
        return (html, text)
    }

    @Test("`<![CDATA[]]]>` (empty content + trailing `]`) is inline HTML")
    func emptyTrailingBracketRecognized() throws {
        #expect(try parse("o<![CDATA[]]]>", options: Self.options).html == "<![CDATA[]]]>")
    }

    @Test("`<![CDATA[x]]]>` (content ending in `]`) is inline HTML")
    func contentTrailingBracketRecognized() throws {
        #expect(try parse("o<![CDATA[x]]]>", options: Self.options).html == "<![CDATA[x]]]>")
    }

    @Test("`<![CDATA[xx]]>` (normal) is inline HTML")
    func normalCDATARecognized() throws {
        #expect(try parse("o<![CDATA[xx]]>", options: Self.options).html == "<![CDATA[xx]]>")
    }

    @Test("`<![CDATA[]]>` (empty content) is inline HTML")
    func emptyCDATARecognized() throws {
        #expect(try parse("o<![CDATA[]]>", options: Self.options).html == "<![CDATA[]]>")
    }
}
