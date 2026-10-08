/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A non-ASCII character in the Unicode `P` categories, such as U+055E, U+00A1 or U+2014, is a punctuation
/// character (Characters and lines) when deciding whether a delimiter run is left- or right-flanking (Emphasis and
/// strong emphasis). With `.smart`, `'` and `"` runs become opening or closing quotes by the same flanking rules.
@Suite("Inline flanking - Unicode punctuation neighbours")
struct FlankingUnicodePunctuationTests {

    /// The document's text, with emphasis wrapped in `<em>...</em>` and strong emphasis in
    /// `<strong>...</strong>`. Delimiters that pair are absent from the text, so the output tells a
    /// paired run from a literal one.
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

    /// Fixture sanity: the renderer must actually distinguish a paired emphasis run from literal text
    /// and a smart quote from a straight one, or every assertion below could pass vacuously.
    @Test("renderer distinguishes structure and smart quotes")
    func rendererSanity() {
        #expect(render("*a*") == "<em>a</em>")
        #expect(render("plain") == "plain")
        #expect(render("'x'", options: .smart) == "\u{2018}x\u{2019}")
    }

    // MARK: - Smart quotes

    /// The second quote is preceded and followed by punctuation, so it is right-flanking and closes the first.
    @Test("single-quote run before Unicode punctuation opens then closes")
    func singleQuoteBeforeUnicodePunct() {
        // U+055E (Armenian question mark, Po), U+00A1 (inverted exclamation, Po), U+2014 (em dash, Pd).
        #expect(render("''\u{055E}", options: .smart) == "\u{2018}\u{2019}\u{055E}")
        #expect(render("''\u{00A1}", options: .smart) == "\u{2018}\u{2019}\u{00A1}")
        #expect(render("''\u{2014}", options: .smart) == "\u{2018}\u{2019}\u{2014}")
    }

    @Test("a further trailing quote after Unicode punctuation stays a right curly")
    func trailingQuoteAfterUnicodePunct() {
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

    @Test("lone single quote before Unicode punctuation stays a right curly")
    func loneQuoteBeforeUnicodePunct() {
        #expect(render("'\u{055E}", options: .smart) == "\u{2019}\u{055E}")
    }

    @Test("letter-preceded quote run before Unicode punctuation stays two right curlies")
    func letterPrecededQuoteRun() {
        #expect(render("x''\u{055E}", options: .smart) == "x\u{2019}\u{2019}\u{055E}")
    }

    @Test("quote run before ASCII punctuation across a space opens then closes")
    func quoteRunBeforeASCIIPunct() {
        #expect(render("'' .", options: .smart) == "\u{2018}\u{2019} .")
    }

    // MARK: - Emphasis

    /// The inner `*` has punctuation on one side and a letter on the other, so it is flanking only
    /// toward the letter: before `a` it cannot close, and after `a` it cannot open.
    @Test("emphasis does not form around Unicode punctuation with an outer letter")
    func emphasisAroundUnicodePunctNoPair() {
        #expect(render("*\u{055E}*a") == "*\u{055E}*a")
        #expect(render("a*\u{055E}*") == "a*\u{055E}*")
    }

    @Test("emphasis forms when a Unicode punctuation char precedes the whole run")
    func emphasisWithUnicodePunctBefore() {
        #expect(render("\u{055E} *a*") == "\u{055E} <em>a</em>")
    }

    @Test("underscore run around Unicode punctuation with an outer letter does not pair")
    func underscoreAroundUnicodePunctNoPair() {
        #expect(render("_\u{055E}_a") == "_\u{055E}_a")
    }

    @Test("emphasis forms around an em dash followed by a space")
    func emphasisAroundEmDash() {
        #expect(render("*\u{2014}* x") == "<em>\u{2014}</em> x")
    }

    @Test("strong forms around Unicode punctuation")
    func strongAroundUnicodePunct() {
        #expect(render("**\u{055E}**") == "<strong>\u{055E}</strong>")
    }

    @Test("emphasis does not form around ASCII punctuation with an outer letter")
    func emphasisAroundASCIIPunctNoPair() {
        #expect(render("*.*a") == "*.*a")
    }
}
