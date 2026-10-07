/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A footnote reference whose label exceeds cmark's lookup length cap stays literal.
///
/// Ground truth is cmark-gfm (flag-ON). Footnote references resolve through the same `cmark_map_lookup`
/// as links, which rejects a label over 1000 bytes; the reference turns back into literal `[^…]` text and
/// its (now unreferenced) definition is dropped. Labels of 999 and 1000 bytes resolve.
class FootnoteReferenceLabelLengthCapTests: XCTestCase {
    private func surface(_ markdown: String, bugCompatible: Bool = true) -> String {
        var options = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))
        if bugCompatible {
            options.insert(.cmarkBugCompatibility)
        }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private func surface(_ labelLength: Int) -> String {
        surface(referenceAndDefinition(String(repeating: "a", count: labelLength)))
    }

    /// `x[^label]` followed by the definition `[^label]: note`.
    private func referenceAndDefinition(_ label: String) -> String {
        "x[^\(label)]\n\n[^\(label)]: note"
    }

    private func literalParagraph(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(text)\""
    }

    /// The surface of `referenceAndDefinition(label)` when the reference resolves.
    private func resolvedReference(_ label: String) -> String {
        "Document\n├─ Paragraph\n│  ├─ Text \"x\"\n│  └─ FootnoteReference label: \"\(label)\" index: 1\n└─ FootnoteDefinition label: \"\(label)\"\n   └─ Paragraph\n      └─ Text \"note\""
    }

    func testAtCapResolves() {
        XCTAssertTrue(surface(1000).contains("FootnoteReference"))
        XCTAssertTrue(surface(999).contains("FootnoteReference"))
    }

    func testOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"x[^\(label)]\"", surface(1001))
    }

    // MARK: What cmark measures

    /// cmark measures the reference's literal (the bytes between `^` and `]`), so a 2-byte `é` weighs 2.
    func testMultibyteCountsBytes() {
        let atCap = String(repeating: "\u{E9}", count: 500)
        XCTAssertTrue(surface(referenceAndDefinition(atCap)).contains("FootnoteReference"))
        let overCap = atCap + "a"
        XCTAssertEqual(literalParagraph("x[^\(overCap)]"), surface(referenceAndDefinition(overCap)))
    }

    /// A NUL counts as the 3-byte U+FFFD cmark substitutes for it before inline parsing.
    func testNULCountsReplacementBytes() {
        let atCap = String(repeating: "a", count: 997) + "\u{0}"
        XCTAssertTrue(surface(referenceAndDefinition(atCap)).contains("FootnoteReference"))
        let overCap = String(repeating: "a", count: 998)
        XCTAssertEqual(literalParagraph("x[^\(overCap)\u{FFFD}]"), surface(referenceAndDefinition(overCap + "\u{0}")))
    }

    /// An over-cap reference turns back into its raw source text, so an entity in it stays undecoded.
    func testOverCapKeepsRawText() {
        let label = String(repeating: "a", count: 996) + "&amp;"
        XCTAssertEqual(literalParagraph("x[^\(label)]"), surface(referenceAndDefinition(label)))
    }

    /// An image-shaped opener `![^…]` is a `!` then a footnote reference, measured from past the `^`.
    func testImageShapedOpenerMeasuresFromCaret() {
        let atCap = String(repeating: "a", count: 1000)
        XCTAssertTrue(surface("x![^\(atCap)]\n\n[^\(atCap)]: note").contains("FootnoteReference"))
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("x![^\(label)]"), surface("x![^\(label)]\n\n[^\(label)]: note"))
    }

    /// The cap applies to a reference nested in a container.
    func testReferenceInBlockQuoteOverCapStaysLiteral() {
        let atCap = String(repeating: "a", count: 1000)
        XCTAssertTrue(surface("> x[^\(atCap)]\n\n[^\(atCap)]: note").contains("FootnoteReference"))
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"x[^\(label)]\"",
            surface("> x[^\(label)]\n\n[^\(label)]: note")
        )
    }

    /// Every reference to an over-cap label stays literal, so none claims the definition.
    func testRepeatedReferenceOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(
            literalParagraph("x[^\(label)] y[^\(label)]"),
            surface("x[^\(label)] y[^\(label)]\n\n[^\(label)]: note")
        )
    }

    /// A reference whose `]` is on a later line captures `colOf(]) - colOf([) - 2` bytes from past the
    /// `^`; cmark looks that captured label up, so the cap applies to the captured length.
    func testCrossLineCapturedLabelOverCapStaysLiteral() {
        let crossLine = { (length: Int) in
            let label = String(repeating: "a", count: length)
            return "[^\(label)\n" + String(repeating: "b", count: length + 2) + "]\n\n[^\(label)]: note"
        }
        XCTAssertTrue(surface(crossLine(1000)).contains("FootnoteReference"))
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("[^\(label)]"), surface(crossLine(1001)))
    }

    /// A cross-line capture that cuts a multi-byte character is measured at its cut length: a
    /// 1000-byte capture ending in `é`'s lead byte resolves, although its U+FFFD repair is 1002 bytes.
    func testCrossLineCapturedLabelMeasuresCutLength() {
        let label = String(repeating: "a", count: 999)
        let markdown = "[^\(label)\u{E9}\n" + String(repeating: "b", count: 1002) + "]\n\n[^\(label)\u{FFFD}]: note"
        XCTAssertTrue(surface(markdown).contains("FootnoteReference"))
    }

    /// A `[^[…]]` opener collapses to `[^[` whatever its captured label's length: cmark never resolves
    /// it, so the cap has no effect there. A guard, not a boundary.
    func testCaretBracketCollapseOverCapIsUnchanged() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("x[^["), surface("x[^[\(label)]]\n\n[^\(label)]: note"))
    }

    // MARK: Spec (flag-off): at most 999 characters, as for a link label

    func testSpecCapAt999Characters() {
        let resolves = { (label: String) in
            self.surface(self.referenceAndDefinition(label), bugCompatible: false).contains("FootnoteReference")
        }
        XCTAssertTrue(resolves(String(repeating: "a", count: 999)))
        XCTAssertFalse(resolves(String(repeating: "a", count: 1000)))
        XCTAssertTrue(resolves(String(repeating: "\u{E9}", count: 999)))
        XCTAssertFalse(resolves(String(repeating: "\u{E9}", count: 1000)))
        XCTAssertTrue(resolves(String(repeating: "a", count: 998) + "\u{0}"))
        XCTAssertFalse(resolves(String(repeating: "a", count: 999) + "\u{0}"))
    }

    func testSpecOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1000)
        XCTAssertEqual(literalParagraph("x[^\(label)]"), surface(referenceAndDefinition(label), bugCompatible: false))
    }

    /// Flag-off (shipped): a footnote label holds at most 999 characters, so a 1000-byte label stays literal
    /// where cmark-gfm's 1000-byte lookup cap resolves it.
    func testFlagOffAtCap() {
        let label999 = String(repeating: "a", count: 999)
        XCTAssertEqual(resolvedReference(label999), surface(referenceAndDefinition(label999), bugCompatible: false))
        let label1000 = String(repeating: "a", count: 1000)
        XCTAssertEqual(literalParagraph("x[^\(label1000)]"), surface(referenceAndDefinition(label1000), bugCompatible: false))
    }

    func testFlagOffOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("x[^\(label)]"), surface(referenceAndDefinition(label), bugCompatible: false))
    }

    /// Flag-off (shipped): the cap counts characters, so 501 `é` (1002 bytes) resolve where cmark-gfm's
    /// byte count leaves them literal.
    func testFlagOffMultibyteCountsCharacters() {
        let atCap = String(repeating: "\u{E9}", count: 500)
        XCTAssertEqual(resolvedReference(atCap), surface(referenceAndDefinition(atCap), bugCompatible: false))
        let overCap = atCap + "a"
        XCTAssertEqual(resolvedReference(overCap), surface(referenceAndDefinition(overCap), bugCompatible: false))
    }

    /// Flag-off (shipped): a NUL is one character (the U+FFFD it becomes), so a 999-character label ending
    /// in one resolves where cmark-gfm counts the replacement's 3 bytes and leaves it literal.
    func testFlagOffNULCountsOneCharacter() {
        let atCap = String(repeating: "a", count: 997)
        XCTAssertEqual(resolvedReference(atCap + "\u{FFFD}"), surface(referenceAndDefinition(atCap + "\u{0}"), bugCompatible: false))
        let overCap = String(repeating: "a", count: 998)
        XCTAssertEqual(resolvedReference(overCap + "\u{FFFD}"), surface(referenceAndDefinition(overCap + "\u{0}"), bugCompatible: false))
    }

    /// Flag-off (shipped): an over-cap reference is ordinary paragraph text, so its entity decodes, where
    /// cmark-gfm restores the reference's undecoded source text.
    func testFlagOffOverCapDecodesEntity() {
        let label = String(repeating: "a", count: 996) + "&amp;"
        XCTAssertEqual(literalParagraph("x[^\(String(repeating: "a", count: 996))&]"), surface(referenceAndDefinition(label), bugCompatible: false))
    }

    /// Flag-off (shipped): the 999-character cap applies after an image-shaped `!`, so a 1000-byte label
    /// stays literal where cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffImageShapedOpener() {
        let atCap = String(repeating: "a", count: 1000)
        XCTAssertEqual(literalParagraph("x![^\(atCap)]"), surface("x![^\(atCap)]\n\n[^\(atCap)]: note", bugCompatible: false))
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("x![^\(label)]"), surface("x![^\(label)]\n\n[^\(label)]: note", bugCompatible: false))
    }

    /// Flag-off (shipped): the 999-character cap applies in a block quote, so a 1000-byte label stays
    /// literal where cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffReferenceInBlockQuote() {
        let atCap = String(repeating: "a", count: 1000)
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"x[^\(atCap)]\"",
            surface("> x[^\(atCap)]\n\n[^\(atCap)]: note", bugCompatible: false)
        )
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"x[^\(label)]\"",
            surface("> x[^\(label)]\n\n[^\(label)]: note", bugCompatible: false)
        )
    }

    func testFlagOffRepeatedReferenceOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(
            literalParagraph("x[^\(label)] y[^\(label)]"),
            surface("x[^\(label)] y[^\(label)]\n\n[^\(label)]: note", bugCompatible: false)
        )
    }

    /// Flag-off (shipped): a label spanning the line break holds both lines' characters, over the cap, so it
    /// stays literal text around a soft break, where cmark-gfm measures a column-captured slice of the
    /// first line and resolves or collapses that.
    func testFlagOffCrossLineLabelStaysLiteral() {
        for length in [1000, 1001] {
            let label = String(repeating: "a", count: length)
            let second = String(repeating: "b", count: length + 2)
            XCTAssertEqual(
                "Document\n└─ Paragraph\n   ├─ Text \"[^\(label)\"\n   ├─ SoftBreak\n   └─ Text \"\(second)]\"",
                surface("[^\(label)\n\(second)]\n\n[^\(label)]: note", bugCompatible: false)
            )
        }
    }

    /// Flag-off (shipped): the cross-line label ending in `é` holds both lines' characters, over the cap, so
    /// it stays literal where cmark-gfm resolves the cut first-line capture.
    func testFlagOffCrossLineCutLabelStaysLiteral() {
        let label = String(repeating: "a", count: 999)
        let second = String(repeating: "b", count: 1002)
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"[^\(label)\u{E9}\"\n   ├─ SoftBreak\n   └─ Text \"\(second)]\"",
            surface("[^\(label)\u{E9}\n\(second)]\n\n[^\(label)\u{FFFD}]: note", bugCompatible: false)
        )
    }

    /// Flag-off (shipped): a footnote label cannot hold an unescaped `[`, so the whole `[^[…]]` run stays
    /// literal text, where cmark-gfm collapses it to `[^[`.
    func testFlagOffCaretBracketStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        XCTAssertEqual(literalParagraph("x[^[\(label)]]"), surface("x[^[\(label)]]\n\n[^\(label)]: note", bugCompatible: false))
    }
}
