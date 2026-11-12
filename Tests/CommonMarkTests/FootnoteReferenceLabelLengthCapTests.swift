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
/// literal text. A multibyte character counts as one character, and so does a NUL, which is replaced by U+FFFD
/// (Insecure characters). Each over-cap reference here whose label holds no whitespace has a footnote definition within
/// the cap whose label matches it after case folding, which turns each `ß` into `ss` (Links).
@Suite("Footnote reference label length cap")
struct FootnoteReferenceLabelLengthCapTests {
    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [.sourcePosition, .footnotes])
    }

    private func referenceAndDefinition(_ label: String) -> String {
        "x[^\(label)]\n\n[^\(label)]: note"
    }

    private func literalParagraph(_ text: String) -> String {
        "document\n  paragraph\n    text \"\(text)\"\n"
    }

    /// The tree of `referenceAndDefinition` when the reference resolves to the definition labeled `label`.
    private func resolvedReference(_ label: String) -> String {
        "document\n  paragraph\n    text \"x\"\n    footnote_reference \"1\"\n  footnote_definition \"\(label)\"\n    paragraph\n      text \"note\"\n"
    }

    @Test(arguments: [
        (String(repeating: "a", count: 999), String(repeating: "a", count: 999)),
        (String(repeating: "\u{E9}", count: 999), String(repeating: "\u{E9}", count: 999)),
        (String(repeating: "a", count: 998) + "\u{0}", String(repeating: "a", count: 998) + "\u{FFFD}"),
    ])
    func labelOf999CharactersResolves(_ label: String, _ replaced: String) {
        #expect(tree(referenceAndDefinition(label)) == resolvedReference(replaced))
    }

    @Test(arguments: [
        (
            String(repeating: "s", count: 1000),
            String(repeating: "\u{DF}", count: 500),
            String(repeating: "s", count: 1000)
        ),
        (
            String(repeating: "\u{E9}", count: 998) + "ss",
            String(repeating: "\u{E9}", count: 998) + "\u{DF}",
            String(repeating: "\u{E9}", count: 998) + "ss"
        ),
        (
            String(repeating: "s", count: 999) + "\u{0}",
            String(repeating: "\u{DF}", count: 499) + "s\u{0}",
            String(repeating: "s", count: 999) + "\u{FFFD}"
        ),
        (
            String(repeating: "s", count: 1001),
            String(repeating: "\u{DF}", count: 500) + "s",
            String(repeating: "s", count: 1001)
        ),
    ] as [(String, String, String)])
    func labelOverCapStaysLiteral(_ label: String, _ definitionLabel: String, _ replaced: String) {
        #expect(tree("x[^\(label)]\n\n[^\(definitionLabel)]: note") == literalParagraph("x[^\(replaced)]"))
    }

    /// A bracket whose label is over the cap is ordinary paragraph text, so its entity reference decodes.
    @Test func overCapDecodesEntity() {
        let label = String(repeating: "s", count: 996) + "&amp;"
        let definitionLabel = String(repeating: "\u{DF}", count: 498) + "&amp;"
        let decoded = String(repeating: "s", count: 996) + "&"
        #expect(tree("x[^\(label)]\n\n[^\(definitionLabel)]: note") == literalParagraph("x[^\(decoded)]"))
    }

    @Test func imageShapedOpener() {
        let atCap = String(repeating: "a", count: 999)
        #expect(tree("x![^\(atCap)]\n\n[^\(atCap)]: note")
            == "document\n  paragraph\n    text \"x!\"\n    footnote_reference \"1\"\n  footnote_definition \"\(atCap)\"\n    paragraph\n      text \"note\"\n")
        let overCap = String(repeating: "s", count: 1000)
        let definitionLabel = String(repeating: "\u{DF}", count: 500)
        #expect(tree("x![^\(overCap)]\n\n[^\(definitionLabel)]: note") == literalParagraph("x![^\(overCap)]"))
    }

    @Test func referenceInBlockQuote() {
        let atCap = String(repeating: "a", count: 999)
        #expect(tree("> x[^\(atCap)]\n\n[^\(atCap)]: note")
            == "document\n  block_quote\n    paragraph\n      text \"x\"\n      footnote_reference \"1\"\n  footnote_definition \"\(atCap)\"\n    paragraph\n      text \"note\"\n")
        let overCap = String(repeating: "s", count: 1000)
        let definitionLabel = String(repeating: "\u{DF}", count: 500)
        #expect(tree("> x[^\(overCap)]\n\n[^\(definitionLabel)]: note") == "document\n  block_quote\n    paragraph\n      text \"x[^\(overCap)]\"\n")
    }

    @Test func repeatedReferenceOverCapStaysLiteral() {
        let label = String(repeating: "s", count: 1000)
        let definitionLabel = String(repeating: "\u{DF}", count: 500)
        #expect(tree("x[^\(label)] y[^\(label)]\n\n[^\(definitionLabel)]: note") == literalParagraph("x[^\(label)] y[^\(label)]"))
    }

    /// A footnote definition's label holds no whitespace, so a footnote-shaped bracket with a line ending between two
    /// non-whitespace characters after its caret is a link label, and the cap counts its characters before whitespace
    /// is collapsed for matching: `^`, 499 `a`, a line ending and 498 `b` are 999 characters, and a space before the
    /// line ending makes 1000.
    @Test func crossLineLabelIsLinkLabelUpToCap() {
        let first = String(repeating: "a", count: 499)
        let second = String(repeating: "b", count: 498)
        #expect(tree("x[^\(first) \n\(second)]\ny[^\(first)\n\(second)]\n\n[^\(first) \(second)]: /u") == """
            document
              paragraph
                text "x[^\(first)"
                softbreak
                text "\(second)]"
                softbreak
                text "y"
                link "/u" ""
                  text "^\(first)"
                  softbreak
                  text "\(second)"

            """)
    }

    /// `^`, 498 `a` and `é` are 500 characters but 501 bytes, so with a line ending and 498 `b` the label holds 999
    /// characters in 1000 bytes.
    @Test func crossLineLabelCountsMultibyteCharacterOnce() {
        let first = String(repeating: "a", count: 498) + "\u{E9}"
        let second = String(repeating: "b", count: 498)
        #expect(tree("x[^\(first)\n\(second)]\n\n[^\(first) \(second)]: /u") == """
            document
              paragraph
                text "x"
                link "/u" ""
                  text "^\(first)"
                  softbreak
                  text "\(second)"

            """)
    }

    /// A footnote definition label cannot hold an unescaped `[` (Links), so `[^a[b]: note` is paragraph text and
    /// `x[^a[b]` stays literal.
    @Test func caretBracketStaysLiteral() {
        #expect(tree("x[^a[b]\n\n[^a[b]: note") == literalParagraph("x[^a[b]") + "  paragraph\n    text \"[^a[b]: note\"\n")
    }
}
