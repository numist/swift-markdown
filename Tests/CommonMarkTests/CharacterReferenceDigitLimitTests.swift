/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `maxDecimalCharacterReferenceDigits` and `maxHexadecimalCharacterReferenceDigits` bound the digits of a numeric
/// character reference, leading zeros included, wherever references decode: text, link destinations and titles, code
/// fence info strings and attribute definitions. A reference past its limit is literal text. A reference within its
/// limit whose code point is invalid decodes to U+FFFD.
@Suite("Numeric character reference digit limits")
struct CharacterReferenceDigitLimitTests {

    private func limits(decimal: Int = 7, hexadecimal: Int = 6) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxDecimalCharacterReferenceDigits = decimal
        limits.maxHexadecimalCharacterReferenceDigits = hexadecimal
        return limits
    }

    // MARK: - Text

    @Test("a decimal reference in text decodes at the digit limit but not past it")
    func decimalText() {
        let limits = limits(decimal: 3)
        #expect(TreeDump.dump("&#065;", options: [], limits: limits) == """
            document
              paragraph
                text "A"

            """)
        #expect(TreeDump.dump("&#0065;", options: [], limits: limits) == """
            document
              paragraph
                text "&#0065;"

            """)
    }

    @Test("a hexadecimal reference in text decodes at the digit limit but not past it")
    func hexadecimalText() {
        let limits = limits(hexadecimal: 3)
        #expect(TreeDump.dump("&#x041;&#X041;", options: [], limits: limits) == """
            document
              paragraph
                text "AA"

            """)
        #expect(TreeDump.dump("&#x0041;&#X0041;", options: [], limits: limits) == """
            document
              paragraph
                text "&#x0041;&#X0041;"

            """)
    }

    @Test("each limit bounds only its own kind of reference")
    func limitsAreIndependent() {
        #expect(TreeDump.dump("&#0065; &#x0041;", options: [], limits: limits(decimal: 3)) == """
            document
              paragraph
                text "&#0065; A"

            """)
        #expect(TreeDump.dump("&#0065; &#x0041;", options: [], limits: limits(hexadecimal: 3)) == """
            document
              paragraph
                text "A &#x0041;"

            """)
    }

    @Test("a reference within raised limits whose code point is past U+10FFFF decodes to U+FFFD")
    func outOfRangeWithinRaisedLimits() {
        let limits = limits(decimal: 8, hexadecimal: 8)
        #expect(TreeDump.dump("&#00000065; &#99999999; &#x00000041; &#xFFFFFFFF;", options: [], limits: limits) == """
            document
              paragraph
                text "A \u{FFFD} A \u{FFFD}"

            """)
        #expect(TreeDump.dump("&#000000065; &#x000000041;", options: [], limits: limits) == """
            document
              paragraph
                text "&#000000065; &#x000000041;"

            """)
    }

    @Test("unlimited digits decode a long reference, to U+FFFD when its value is past U+10FFFF")
    func unlimitedDigits() {
        let limits = limits(decimal: .max, hexadecimal: .max)
        let zeros = String(repeating: "0", count: 40)
        let nines = String(repeating: "9", count: 40)
        let effs = String(repeating: "f", count: 40)
        #expect(TreeDump.dump("&#\(zeros)65; &#\(nines); &#x\(zeros)41; &#x\(effs); &#4294967361; &#x100000041;", options: [], limits: limits) == """
            document
              paragraph
                text "A \u{FFFD} A \u{FFFD} \u{FFFD} \u{FFFD}"

            """)
    }

    @Test("a limit below one leaves every numeric reference literal")
    func limitBelowOne() {
        #expect(TreeDump.dump("&#6; &#x6; &amp;", options: [], limits: limits(decimal: 0, hexadecimal: -1)) == """
            document
              paragraph
                text "&#6; &#x6; &"

            """)
    }

    // MARK: - Destinations and titles

    @Test("an inline link's destination and title decode references at the digit limit but not past it")
    func inlineLink() {
        let limits = limits(decimal: 3, hexadecimal: 3)
        #expect(TreeDump.dump("[l](&#065; \"&#x041;\")", options: [], limits: limits) == """
            document
              paragraph
                link "A" "A"
                  text "l"

            """)
        #expect(TreeDump.dump("[l](&#0065; \"&#x0041;\")", options: [], limits: limits) == """
            document
              paragraph
                link "&#0065;" "&#x0041;"
                  text "l"

            """)
    }

    @Test("a link reference definition's destination and title decode references at the digit limit but not past it")
    func referenceDefinition() {
        let limits = limits(decimal: 3, hexadecimal: 3)
        #expect(TreeDump.dump("[l]: &#x041; '&#065;'\n\n[l]", options: [], limits: limits) == """
            document
              paragraph
                link "A" "A"
                  text "l"

            """)
        #expect(TreeDump.dump("[l]: &#x0041; '&#0065;'\n\n[l]", options: [], limits: limits) == """
            document
              paragraph
                link "&#x0041;" "&#0065;"
                  text "l"

            """)
    }

    @Test("an autolink's destination and text decode references at the digit limit but not past it")
    func autolink() {
        let limits = limits(decimal: 3)
        #expect(TreeDump.dump("<http://a&#065;>", options: [], limits: limits) == """
            document
              paragraph
                link "http://aA" ""
                  text "http://aA"

            """)
        #expect(TreeDump.dump("<http://a&#0065;>", options: [], limits: limits) == """
            document
              paragraph
                link "http://a&#0065;" ""
                  text "http://a&#0065;"

            """)
    }

    // MARK: - Info strings and attributes

    @Test("a code fence's info string decodes references at the digit limit but not past it")
    func infoString() {
        let limits = limits(decimal: 3, hexadecimal: 3)
        #expect(TreeDump.dump("```&#065;&#x041;\n```", options: [], limits: limits) == """
            document
              code_block "AA" ""

            """)
        #expect(TreeDump.dump("```&#0065;&#x0041;\n```", options: [], limits: limits) == """
            document
              code_block "&#0065;&#x0041;" ""

            """)
    }

    @Test("an attribute definition's attributes decode references at the digit limit but not past it")
    func attributeDefinition() {
        let limits = limits(decimal: 3, hexadecimal: 3)
        #expect(TreeDump.dump("^[b]: &#065;&#x041;\n\n^[x][b]", options: [.attributes], limits: limits) == """
            document
              paragraph
                attribute "AA"
                  text "x"

            """)
        #expect(TreeDump.dump("^[b]: &#0065;&#x0041;\n\n^[x][b]", options: [.attributes], limits: limits) == """
            document
              paragraph
                attribute "&#0065;&#x0041;"
                  text "x"

            """)
    }

    // MARK: - Defaults

    /// The inputs past the small limits above decode at the default limits, so those cases test the limits alone.
    @Test("the default limits decode the references past the small limits")
    func defaultsDecodeOverLimitInputs() {
        #expect(TreeDump.dump("&#0065;&#x0041;&#X0041;", options: []) == """
            document
              paragraph
                text "AAA"

            """)
        #expect(TreeDump.dump("[l](&#0065; \"&#x0041;\")", options: []) == """
            document
              paragraph
                link "A" "A"
                  text "l"

            """)
        #expect(TreeDump.dump("[l]: &#x0041; '&#0065;'\n\n[l]\n\n<http://a&#0065;>\n\n```&#0065;&#x0041;\n```", options: []) == """
            document
              paragraph
                link "A" "A"
                  text "l"
              paragraph
                link "http://aA" ""
                  text "http://aA"
              code_block "AA" ""

            """)
        #expect(TreeDump.dump("^[b]: &#0065;&#x0041;\n\n^[x][b]", options: [.attributes]) == """
            document
              paragraph
                attribute "AA"
                  text "x"

            """)
    }
}
