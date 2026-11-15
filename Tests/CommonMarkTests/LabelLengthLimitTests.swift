/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `maxLinkLabelCharacters` and `maxLinkLabelBytes` bound the label inside the brackets of a link reference definition,
/// an attribute definition, a full reference, and the bracket text a collapsed or shortcut reference takes as its label.
/// `maxFootnoteLabelCharacters` and `maxFootnoteLabelBytes` bound a footnote reference's label; a footnote
/// definition's label has no limit. A label past either of its limits is no label: a definition stays paragraph text
/// and a reference stays text.
///
/// Bytes are those of the label's block content: container prefixes are not counted, and a NUL counts as the three
/// bytes of the U+FFFD that replaces it (Insecure characters).
@Suite("Label length limits")
struct LabelLengthLimitTests {

    private func linkLimits(characters: Int = 999, bytes: Int = .max) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxLinkLabelCharacters = characters
        limits.maxLinkLabelBytes = bytes
        return limits
    }

    private func footnoteLimits(characters: Int = 999, bytes: Int = .max) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxFootnoteLabelCharacters = characters
        limits.maxFootnoteLabelBytes = bytes
        return limits
    }

    // MARK: - Link label characters

    @Test("a link reference definition's label fits at the character limit but not past it")
    func definitionCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("[abc]: /u", options: [], limits: limits) == """
            document

            """)
        #expect(TreeDump.dump("[abcd]: /u", options: [], limits: limits) == """
            document
              paragraph
                text "[abcd]: /u"

            """)
    }

    /// The reference's label normalizes to the defined `a b`, so only its own length keeps it from resolving.
    @Test("a full reference's label resolves at the character limit but not past it")
    func fullReferenceCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("[a b]: /u\n\n[t][a b]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "t"

            """)
        #expect(TreeDump.dump("[a b]: /u\n\n[t][a  b]", options: [], limits: limits) == """
            document
              paragraph
                text "[t][a  b]"

            """)
    }

    @Test("a collapsed reference's text resolves at the character limit but not past it")
    func collapsedReferenceCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("[a b]: /u\n\n[a b][]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "a b"

            """)
        #expect(TreeDump.dump("[a b]: /u\n\n[a  b][]", options: [], limits: limits) == """
            document
              paragraph
                text "[a  b][]"

            """)
    }

    @Test("a shortcut reference's text resolves at the character limit but not past it")
    func shortcutReferenceCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("[a b]: /u\n\n[a b]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "a b"

            """)
        #expect(TreeDump.dump("[a b]: /u\n\n[a  b]", options: [], limits: limits) == """
            document
              paragraph
                text "[a  b]"

            """)
    }

    @Test("a multibyte label is counted in characters")
    func multibyteCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("[ééé]: /u\n\n[ééé]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "ééé"

            """)
        #expect(TreeDump.dump("[éééé]: /u\n\n[éééé]", options: [], limits: limits) == """
            document
              paragraph
                text "[éééé]: /u"
              paragraph
                text "[éééé]"

            """)
    }

    @Test("an attribute definition's label fits at the character limit but not past it")
    func attributeDefinitionCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("^[abc]: c\n\n^[x][abc]", options: .attributes, limits: limits) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
        #expect(TreeDump.dump("^[abcd]: c\n\n^[x][abcd]", options: .attributes, limits: limits) == """
            document
              paragraph
                text "^[abcd]: c"
              paragraph
                text "^[x][abcd]"

            """)
    }

    @Test("an inline attribute's label resolves at the character limit but not past it")
    func attributeReferenceCharacters() {
        let limits = linkLimits(characters: 3)
        #expect(TreeDump.dump("^[a b]: c\n\n^[x][a b]", options: .attributes, limits: limits) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
        #expect(TreeDump.dump("^[a b]: c\n\n^[x][a  b]", options: .attributes, limits: limits) == """
            document
              paragraph
                text "^[x][a  b]"

            """)
    }

    // MARK: - Link label bytes

    @Test("a link reference definition's label fits at the byte limit but not past it")
    func definitionBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("[abc]: /u", options: [], limits: limits) == """
            document

            """)
        #expect(TreeDump.dump("[abcd]: /u", options: [], limits: limits) == """
            document
              paragraph
                text "[abcd]: /u"

            """)
    }

    @Test("a multibyte label is counted in bytes")
    func multibyteBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("[aé]: /u\n\n[aé]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "aé"

            """)
        #expect(TreeDump.dump("[éé]: /u\n\n[éé]", options: [], limits: limits) == """
            document
              paragraph
                text "[éé]: /u"
              paragraph
                text "[éé]"

            """)
    }

    @Test("a NUL counts as the three bytes of U+FFFD")
    func nulBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("[\0]: /u\n\n[\0]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "\u{FFFD}"

            """)
        #expect(TreeDump.dump("[a\0]: /u\n\n[a\0]", options: [], limits: limits) == """
            document
              paragraph
                text "[a\u{FFFD}]: /u"
              paragraph
                text "[a\u{FFFD}]"

            """)
    }

    @Test("a backslash escape counts both its bytes")
    func backslashBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("[a\\*]: /u\n\n[a\\*]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "a*"

            """)
        #expect(TreeDump.dump("[ab\\*]: /u\n\n[ab\\*]", options: [], limits: limits) == """
            document
              paragraph
                text "[ab*]: /u"
              paragraph
                text "[ab*]"

            """)
    }

    /// The label `a`, line ending, `b` is three bytes of the block quote's content.
    @Test("a label across a line ending in a block quote counts no block quote marker")
    func containerPrefixBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("> [a\n> b]: /u\n\n[a b]", options: [], limits: limits) == """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "a b"

            """)
        #expect(TreeDump.dump("> [ab\n> b]: /u\n\n[ab b]", options: [], limits: limits) == """
            document
              block_quote
                paragraph
                  text "[ab"
                  softbreak
                  text "b]: /u"
              paragraph
                text "[ab b]"

            """)
    }

    @Test("a reference's label resolves at the byte limit but not past it")
    func referenceBytes() {
        let limits = linkLimits(bytes: 3)
        #expect(TreeDump.dump("[a b]: /u\n\n[t][a b] [a b][] [a b]", options: [], limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "t"
                text " "
                link "/u" ""
                  text "a b"
                text " "
                link "/u" ""
                  text "a b"

            """)
        #expect(TreeDump.dump("[a b]: /u\n\n[t][a  b] [a  b][] [a  b]", options: [], limits: limits) == """
            document
              paragraph
                text "[t][a  b] [a  b][] [a  b]"

            """)
    }

    // MARK: - Footnote labels

    /// `ẞ` case-folds to `ss`, so the 3-character reference `aaẞ` names the 4-character definition `aass`.
    @Test("the character limit bounds a footnote reference's label but not a footnote definition's")
    func footnoteDefinitionCharacters() {
        let limits = footnoteLimits(characters: 3)
        #expect(TreeDump.dump("x[^aéc]\n\n[^aéc]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "aéc"
                paragraph
                  text "n"

            """)
        #expect(TreeDump.dump("x[^aécd]\n\n[^aécd]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x[^aécd]"

            """)
        #expect(TreeDump.dump("x[^aaẞ]\n\n[^aass]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "aass"
                paragraph
                  text "n"

            """)
    }

    /// `ẞ` case-folds to `ss`, so both references name the definition.
    @Test("a footnote reference's label resolves at the character limit but not past it")
    func footnoteReferenceCharacters() {
        let limits = footnoteLimits(characters: 2)
        #expect(TreeDump.dump("x[^aẞ] y[^ass]\n\n[^aẞ]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
                text " y[^ass]"
              footnote_definition "aẞ"
                paragraph
                  text "n"

            """)
    }

    /// U+212A KELVIN SIGN takes 3 bytes and case-folds to `k`, so the 2-byte reference `kk` names the 6-byte
    /// definition `\u{212A}\u{212A}`.
    @Test("the byte limit bounds a footnote reference's label but not a footnote definition's")
    func footnoteDefinitionBytes() {
        let limits = footnoteLimits(bytes: 3)
        #expect(TreeDump.dump("x[^aé]\n\n[^aé]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "aé"
                paragraph
                  text "n"

            """)
        #expect(TreeDump.dump("x[^éé]\n\n[^éé]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x[^éé]"

            """)
        #expect(TreeDump.dump("x[^kk]\n\n[^\u{212A}\u{212A}]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "\u{212A}\u{212A}"
                paragraph
                  text "n"

            """)
    }

    /// `ẞ` case-folds to `ss`, so both references name the definition.
    @Test("a footnote reference's label resolves at the byte limit but not past it")
    func footnoteReferenceBytes() {
        let limits = footnoteLimits(bytes: 3)
        #expect(TreeDump.dump("x[^ass] y[^aẞ]\n\n[^ass]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
                text " y[^aẞ]"
              footnote_definition "ass"
                paragraph
                  text "n"

            """)
    }

    @Test("footnote label limits don't bound link labels, and link label limits don't bound footnote labels")
    func limitsAreSeparate() {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxFootnoteLabelCharacters = 1
        limits.maxFootnoteLabelBytes = 1
        #expect(TreeDump.dump("[abcd]: /u\n\n[abcd]", options: .footnotes, limits: limits) == """
            document
              paragraph
                link "/u" ""
                  text "abcd"

            """)
        limits = MarkdownDocument.ParseLimits()
        limits.maxLinkLabelCharacters = 1
        limits.maxLinkLabelBytes = 1
        #expect(TreeDump.dump("x[^abcd]\n\n[^abcd]: n", options: .footnotes, limits: limits) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "abcd"
                paragraph
                  text "n"

            """)
    }

    // MARK: - Out-of-range values

    @Test("a negative limit admits no label")
    func negativeLimit() {
        #expect(TreeDump.dump("[a]: /u\n\n[a]", options: [], limits: linkLimits(bytes: -1)) == """
            document
              paragraph
                text "[a]: /u"
              paragraph
                text "[a]"

            """)
        #expect(TreeDump.dump("[a]: /u\n\n[a]", options: [], limits: linkLimits(characters: -1)) == """
            document
              paragraph
                text "[a]: /u"
              paragraph
                text "[a]"

            """)
        #expect(TreeDump.dump("x[^a]\n\n[^a]: n", options: .footnotes, limits: footnoteLimits(characters: -1)) == """
            document
              paragraph
                text "x[^a]"

            """)
        #expect(TreeDump.dump("x[^a]\n\n[^a]: n", options: .footnotes, limits: footnoteLimits(bytes: -1)) == """
            document
              paragraph
                text "x[^a]"

            """)
    }

    // MARK: - Defaults

    @Test("the default limits admit the labels the tests above refuse")
    func defaultsAdmitOverLimitLabels() {
        #expect(TreeDump.dump("[éééé]: /u\n\n[t][éééé] [éééé][] [éééé]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "t"
                text " "
                link "/u" ""
                  text "éééé"
                text " "
                link "/u" ""
                  text "éééé"

            """)
        #expect(TreeDump.dump("> [ab\n> b]: /u\n\n[a\0]: /v\n\n[ab b] [a\0]", options: []) == """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "ab b"
                text " "
                link "/v" ""
                  text "a\u{FFFD}"

            """)
        #expect(TreeDump.dump("[abcd]: /u\n\n[éé]: /v\n\n[ab\\*]: /w\n\n[a]: /x\n\n[a b]: /y\n\n[abcd] [éé] [ab\\*] [a] [t][a  b] [a  b][] [a  b]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "abcd"
                text " "
                link "/v" ""
                  text "éé"
                text " "
                link "/w" ""
                  text "ab*"
                text " "
                link "/x" ""
                  text "a"
                text " "
                link "/y" ""
                  text "t"
                text " "
                link "/y" ""
                  text "a  b"
                text " "
                link "/y" ""
                  text "a  b"

            """)
        #expect(TreeDump.dump("^[abcd]: c\n\n^[a b]: d\n\n^[x][abcd] ^[y][a  b]", options: .attributes) == """
            document
              paragraph
                attribute "c"
                  text "x"
                text " "
                attribute "d"
                  text "y"

            """)
        #expect(TreeDump.dump("x[^aécd] y[^aẞ] z[^ass] w[^éé]\n\n[^aécd]: n\n\n[^ass]: m\n\n[^éé]: o", options: .footnotes) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
                text " y"
                footnote_reference "2"
                text " z"
                footnote_reference "2"
                text " w"
                footnote_reference "3"
              footnote_definition "aécd"
                paragraph
                  text "n"
              footnote_definition "ass"
                paragraph
                  text "m"
              footnote_definition "éé"
                paragraph
                  text "o"

            """)
    }
}
