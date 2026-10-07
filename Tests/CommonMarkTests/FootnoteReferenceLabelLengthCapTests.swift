/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote reference label holds at most 999 characters, as a link label does (Links); a longer one stays
/// literal text.
@Suite("Footnote reference label length cap")
struct FootnoteReferenceLabelLengthCapTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink, .footnotes]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    /// `x[^label]` followed by the definition `[^label]: note`.
    private func referenceAndDefinition(_ label: String) -> String {
        "x[^\(label)]\n\n[^\(label)]: note"
    }

    private func literalParagraph(_ text: String) -> String {
        "document\n  paragraph\n    text \"\(text)\"\n"
    }

    /// The surface of `referenceAndDefinition(label)` when the reference resolves.
    private func resolvedReference(_ label: String) -> String {
        "document\n  paragraph\n    text \"x\"\n    footnote_reference \"1\"\n  footnote_definition \"\(label)\"\n    paragraph\n      text \"note\"\n"
    }

    @Test func testCapAt999Characters() {
        let resolves = { (label: String) in
            self.surface(self.referenceAndDefinition(label)).contains("footnote_reference")
        }
        #expect(resolves(String(repeating: "a", count: 999)))
        #expect(!resolves(String(repeating: "a", count: 1000)))
        #expect(resolves(String(repeating: "\u{E9}", count: 999)))
        #expect(!resolves(String(repeating: "\u{E9}", count: 1000)))
        #expect(resolves(String(repeating: "a", count: 998) + "\u{0}"))
        #expect(!resolves(String(repeating: "a", count: 999) + "\u{0}"))
    }

    @Test func testOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1000)
        #expect(surface(referenceAndDefinition(label)) == literalParagraph("x[^\(label)]"))
    }

    @Test func testAtCap() {
        let label999 = String(repeating: "a", count: 999)
        #expect(surface(referenceAndDefinition(label999)) == resolvedReference(label999))
        let label1000 = String(repeating: "a", count: 1000)
        #expect(surface(referenceAndDefinition(label1000)) == literalParagraph("x[^\(label1000)]"))
    }

    @Test func test1001CharacterLabelStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        #expect(surface(referenceAndDefinition(label)) == literalParagraph("x[^\(label)]"))
    }

    /// The cap counts characters, so 500 `é` plus `a` (1001 bytes) resolve.
    @Test func testMultibyteCountsCharacters() {
        let atCap = String(repeating: "\u{E9}", count: 500)
        #expect(surface(referenceAndDefinition(atCap)) == resolvedReference(atCap))
        let overCap = atCap + "a"
        #expect(surface(referenceAndDefinition(overCap)) == resolvedReference(overCap))
    }

    /// A NUL is one character, the U+FFFD that replaces it (Insecure characters), so a 999-character label
    /// ending in one resolves.
    @Test func testNULCountsOneCharacter() {
        let prefix997 = String(repeating: "a", count: 997)
        #expect(surface(referenceAndDefinition(prefix997 + "\u{0}")) == resolvedReference(prefix997 + "\u{FFFD}"))
        let prefix998 = String(repeating: "a", count: 998)
        #expect(surface(referenceAndDefinition(prefix998 + "\u{0}")) == resolvedReference(prefix998 + "\u{FFFD}"))
    }

    /// An over-cap reference is ordinary paragraph text, so its entity reference decodes.
    @Test func testOverCapDecodesEntity() {
        let label = String(repeating: "a", count: 996) + "&amp;"
        #expect(surface(referenceAndDefinition(label)) == literalParagraph("x[^\(String(repeating: "a", count: 996))&]"))
    }

    @Test func testImageShapedOpener() {
        let atCap = String(repeating: "a", count: 1000)
        #expect(surface("x![^\(atCap)]\n\n[^\(atCap)]: note") == literalParagraph("x![^\(atCap)]"))
        let label = String(repeating: "a", count: 1001)
        #expect(surface("x![^\(label)]\n\n[^\(label)]: note") == literalParagraph("x![^\(label)]"))
    }

    @Test func testReferenceInBlockQuote() {
        let atCap = String(repeating: "a", count: 1000)
        #expect(surface("> x[^\(atCap)]\n\n[^\(atCap)]: note") == "document\n  block_quote\n    paragraph\n      text \"x[^\(atCap)]\"\n")
        let label = String(repeating: "a", count: 1001)
        #expect(surface("> x[^\(label)]\n\n[^\(label)]: note") == "document\n  block_quote\n    paragraph\n      text \"x[^\(label)]\"\n")
    }

    @Test func testRepeatedReferenceOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        #expect(surface("x[^\(label)] y[^\(label)]\n\n[^\(label)]: note") == literalParagraph("x[^\(label)] y[^\(label)]"))
    }

    /// The first line alone exceeds the cap, so the bracket stays literal text around the soft line break.
    @Test(arguments: [1000, 1001])
    func testCrossLineLabelStaysLiteral(length: Int) {
        let label = String(repeating: "a", count: length)
        let second = String(repeating: "b", count: length + 2)
        #expect(surface("[^\(label)\n\(second)]\n\n[^\(label)]: note")
            == "document\n  paragraph\n    text \"[^\(label)\"\n    softbreak\n    text \"\(second)]\"\n")
    }

    /// The first line alone holds 1000 characters, the last an `é`, so the bracket stays literal.
    @Test func testCrossLineLabelEndingInMultibyteStaysLiteral() {
        let label = String(repeating: "a", count: 999)
        let second = String(repeating: "b", count: 1002)
        #expect(surface("[^\(label)\u{E9}\n\(second)]\n\n[^\(label)\u{FFFD}]: note")
            == "document\n  paragraph\n    text \"[^\(label)\u{E9}\"\n    softbreak\n    text \"\(second)]\"\n")
    }

    /// A footnote reference label cannot hold an unescaped `[` (Links), so the whole `[^[…]]` run stays literal text.
    @Test func testCaretBracketStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        #expect(surface("x[^[\(label)]]\n\n[^\(label)]: note") == literalParagraph("x[^[\(label)]]"))
    }
}
