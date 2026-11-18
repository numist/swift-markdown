/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Inline flanking - Unicode punctuation neighbours")
struct FlankingUnicodePunctuationTests {

    private func render(_ doc: borrowing MarkdownDocument) -> String {
        var out = ""
        func walk(_ node: borrowing MarkdownNode) {
            switch node.kind {
            case .text:
                out += node.literal() ?? ""
            case .emphasis:
                out += "<em>"
                node.children.forEach { walk($0) }
                out += "</em>"
            case .strong:
                out += "<strong>"
                node.children.forEach { walk($0) }
                out += "</strong>"
            default:
                node.children.forEach { walk($0) }
            }
        }
        walk(doc.root)
        return out
    }

    private func render(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            render(doc)
        }
    }

    @Test("renderer distinguishes structure and smart quotes")
    func rendererSanity() {
        #expect(render("*a*") == "<em>a</em>")
        #expect(render("plain") == "plain")
        #expect(render("'x'", options: .smart) == "\u{2018}x\u{2019}")
    }

    @Test("single-quote run before Unicode punctuation opens then closes")
    func singleQuoteBeforeUnicodePunct() {
        #expect(render("''\u{055E}", options: .smart) == "\u{2018}\u{2019}\u{055E}")
        #expect(render("''\u{00A1}", options: .smart) == "\u{2018}\u{2019}\u{00A1}")
        #expect(render("''\u{2014}", options: .smart) == "\u{2018}\u{2019}\u{2014}")
    }

    @Test("a later quote after Unicode punctuation does not pair with the second quote")
    func laterQuoteDoesNotPairWithSecondQuote() {
        #expect(render("''\u{055E}'", options: .smart) == "\u{2018}\u{2019}\u{055E}\u{2019}")
    }

    @Test("double-quote run before Unicode punctuation opens then closes")
    func doubleQuoteBeforeUnicodePunct() {
        #expect(render("\"\"\u{055E}", options: .smart) == "\u{201C}\u{201D}\u{055E}")
    }

    @Test("quote run before a letter stays two right curlies")
    func quoteRunBeforeLetter() {
        #expect(render("''a", options: .smart) == "\u{2019}\u{2019}a")
    }

    @Test("single quote after Unicode punctuation opens")
    func singleQuoteAfterUnicodePunct() {
        #expect(render("\u{055E}'a'", options: .smart) == "\u{055E}\u{2018}a\u{2019}")
    }

    @Test("no quote in a letter-preceded run before Unicode punctuation opens")
    func letterPrecededQuoteRun() {
        #expect(render("x''\u{055E}'", options: .smart) == "x\u{2019}\u{2019}\u{055E}\u{2019}")
    }

    @Test("quote run before a space opens then closes")
    func quoteRunBeforeSpace() {
        #expect(render("'' a", options: .smart) == "\u{2018}\u{2019} a")
    }

    @Test("emphasis does not form around Unicode punctuation with an outer letter")
    func emphasisAroundUnicodePunctNoPair() {
        #expect(render("*\u{055E}*a") == "*\u{055E}*a")
        #expect(render("a*\u{055E}*") == "a*\u{055E}*")
    }

    @Test("underscore emphasis opens after Unicode punctuation")
    func underscoreEmphasisAfterUnicodePunct() {
        #expect(render("\u{055E}_a_") == "\u{055E}<em>a</em>")
    }

    @Test("underscore emphasis closes before Unicode punctuation")
    func underscoreEmphasisBeforeUnicodePunct() {
        #expect(render("_a_\u{055E}") == "<em>a</em>\u{055E}")
    }

    @Test("underscore emphasis forms around an em dash between em dashes")
    func emphasisAroundEmDash() {
        #expect(render("\u{2014}_\u{2014}_\u{2014}") == "\u{2014}<em>\u{2014}</em>\u{2014}")
    }

    @Test("strong emphasis opens after Unicode punctuation")
    func strongAfterUnicodePunct() {
        #expect(render("\u{055E}__a__") == "\u{055E}<strong>a</strong>")
    }

    @Test("emphasis does not form around ASCII punctuation with an outer letter")
    func emphasisAroundASCIIPunctNoPair() {
        #expect(render("*.*a") == "*.*a")
    }

    @Test("emphasis does not form around other Unicode punctuation with an outer letter")
    func emphasisAroundOtherUnicodePunctNoPair() {
        #expect(TreeDump.dump("*\u{2E43}*a", options: []) == """
            document
              paragraph
                text "*\u{2E43}*a"

            """)
        #expect(TreeDump.dump("*\u{1E95E}*a", options: []) == """
            document
              paragraph
                text "*\u{1E95E}*a"

            """)
    }

    // U+166D is in category So, so it is not a punctuation character (Characters and lines).
    @Test("emphasis forms around a symbol with an outer letter")
    func emphasisAroundSymbol() {
        #expect(TreeDump.dump("*\u{166D}*a", options: []) == """
            document
              paragraph
                emph
                  text "\u{166D}"
                text "a"

            """)
    }
}
