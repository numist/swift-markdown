/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// The footnote label limits bound footnote references, not footnote definitions: a `[^label]:` opener begins a
/// definition however long its label, and a definition that no reference resolves to is dropped, as every unreferenced
/// definition is.
@Suite("Footnote definition label length")
struct FootnoteDefinitionLabelLengthTests {
    private static let kelvinSign = "\u{212A}"

    /// Footnote labels of up to 1,000 bytes, with no character limit.
    private static var thousandByteLimits: MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxFootnoteLabelCharacters = .max
        limits.maxFootnoteLabelBytes = 1000
        return limits
    }

    // MARK: - Default limits

    @Test("a definition whose label has 1,000 characters is dropped when unreferenced")
    func unreferencedDefinitionOverCharacterLimitIsDropped() {
        let label = String(repeating: "a", count: 1000)
        #expect(TreeDump.dump("[^\(label)]: x\n", options: .footnotes) == """
            document

            """)
    }

    @Test("a reference whose label has 1,000 characters stays text and its definition is dropped")
    func referenceAndDefinitionOverCharacterLimit() {
        let label = String(repeating: "a", count: 1000)
        #expect(TreeDump.dump("x[^\(label)]\n\n[^\(label)]: x\n", options: .footnotes) == """
            document
              paragraph
                text "x[^\(label)]"

            """)
    }

    @Test("an opener whose label has 999 characters interrupts a paragraph")
    func openerAtCharacterLimitInterruptsParagraph() {
        let label = String(repeating: "a", count: 999)
        #expect(TreeDump.dump("x[^\(label)]\n[^\(label)]: note\n", options: .footnotes) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "note"

            """)
    }

    @Test("an opener whose label has 1,000 characters interrupts a paragraph")
    func openerOverCharacterLimitInterruptsParagraph() {
        let label = String(repeating: "a", count: 1000)
        #expect(TreeDump.dump("x[^\(label)]\n[^\(label)]: note\n", options: .footnotes) == """
            document
              paragraph
                text "x[^\(label)]"

            """)
    }

    /// `ß` case-folds to `ss`, so a 500-character reference names a 1,000-character definition.
    @Test("a reference within the character limit resolves to a definition over it")
    func referenceResolvesToDefinitionOverCharacterLimit() {
        let reference = String(repeating: "ß", count: 500)
        let label = String(repeating: "s", count: 1000)
        #expect(TreeDump.dump("x[^\(reference)]\n\n[^\(label)]: x\n", options: .footnotes) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "x"

            """)
    }

    // MARK: - A 1,000-byte limit

    @Test("a definition whose label has 1,001 bytes is dropped when unreferenced")
    func unreferencedDefinitionOverByteLimitIsDropped() {
        let label = String(repeating: "a", count: 1001)
        #expect(TreeDump.dump("[^\(label)]: x\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document

            """)
    }

    @Test("a reference whose label has 1,001 bytes stays text and its definition is dropped")
    func referenceAndDefinitionOverByteLimit() {
        let label = String(repeating: "a", count: 1001)
        #expect(TreeDump.dump("x[^\(label)]\n\n[^\(label)]: x\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                text "x[^\(label)]"

            """)
    }

    @Test("an opener whose label has 1,001 bytes interrupts a paragraph")
    func openerOverByteLimitInterruptsParagraph() {
        let label = String(repeating: "a", count: 1001)
        #expect(TreeDump.dump("x[^\(label)]\n[^\(label)]: note\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                text "x[^\(label)]"

            """)
    }

    /// U+212A KELVIN SIGN takes 3 bytes and case-folds to `k`, so a 334-byte reference names a 1,002-byte definition.
    @Test("a reference within the byte limit resolves to a definition over it")
    func referenceResolvesToDefinitionOverByteLimit() {
        let reference = String(repeating: "k", count: 334)
        let label = String(repeating: Self.kelvinSign, count: 334)
        #expect(TreeDump.dump("[^\(reference)]\n\n[^\(label)]: x\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "x"

            """)
    }

    @Test("the same label within the character limit resolves at the default limits")
    func kelvinSignLabelResolvesAtDefaultLimits() {
        let reference = String(repeating: "k", count: 334)
        let label = String(repeating: Self.kelvinSign, count: 334)
        #expect(TreeDump.dump("[^\(reference)]\n\n[^\(label)]: x\n", options: .footnotes) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "x"

            """)
    }

    @Test("a reference over the byte limit stays text though it matches a definition")
    func referenceOverByteLimitMatchingDefinition() {
        let label = String(repeating: Self.kelvinSign, count: 334)
        #expect(TreeDump.dump("[^\(label)]\n\n[^\(label)]: x\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                text "[^\(label)]"

            """)
    }

    /// The opener begins a footnote definition, not a link reference definition with the label `^…`, though the link
    /// label limits admit that label.
    @Test("an opener over the byte limit whose content looks like a link destination begins a footnote definition")
    func openerOverByteLimitIsNoLinkReferenceDefinition() {
        let label = String(repeating: Self.kelvinSign, count: 334)
        #expect(TreeDump.dump("[^\(label)]\n\n[^\(label)]: /u\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                text "[^\(label)]"

            """)
        let reference = String(repeating: "k", count: 334)
        #expect(TreeDump.dump("[^\(reference)]\n\n[^\(label)]: /u\n", options: .footnotes, limits: Self.thousandByteLimits) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "/u"

            """)
    }
}
