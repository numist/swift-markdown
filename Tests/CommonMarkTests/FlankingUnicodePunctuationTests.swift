/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Inline delimiter flanking (CommonMark 0.30 §6.2) classifies the characters bordering a `*`/`_`
/// or smart-quote (`'`/`"`) run as "Unicode whitespace" or a "Unicode punctuation character". cmark-gfm
/// decodes the full UTF-8 scalar bordering the run (`scan_delims` in `src/inlines.c`, via
/// `cmark_utf8proc_is_space` / `cmark_utf8proc_is_punctuation` - the P[cdefios] classes and an ASCII
/// punctuation mark), so a NON-ASCII Unicode punctuation neighbour (e.g. U+055E Armenian question mark,
/// U+00A1 inverted exclamation, U+2014 em dash) counts as punctuation for flanking. These tests pin that
/// behaviour against cmark for the smart-quote and emphasis surfaces.
@Suite("Inline flanking - Unicode punctuation neighbours")
struct FlankingUnicodePunctuationTests {

    /// Render the document as a flat string that carries both content and emphasis/strong structure:
    /// `.text` nodes contribute their literal, `.emphasis` wraps its children in `<em>...</em>`, and
    /// `.strong` in `<strong>...</strong>`. When a `*`/`_` run forms emphasis, cmark consumes the
    /// delimiter characters into the node, so the presence or absence of the wrapper distinguishes a
    /// paired run from a literal one - which is exactly what the flanking bug flips.
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

    private func render(_ source: String, options: MarkdownDocument.ParseOptions = []) throws -> String {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            render(doc)
        }
    }

    /// Fixture sanity: the renderer must actually distinguish a paired emphasis run from literal text
    /// and a smart quote from a straight one, or every assertion below could pass vacuously.
    @Test("renderer distinguishes structure and smart rewrites")
    func rendererSanity() throws {
        #expect(try render("*a*") == "<em>a</em>")
        #expect(try render("plain") == "plain")
        #expect(try render("'x'", options: .smart) == "\u{2018}x\u{2019}")
    }

    // MARK: - Smart quotes

    /// A quote run adjacent to a non-ASCII Unicode punctuation character must classify that neighbour
    /// as punctuation, so the trailing quote becomes a closer (right curly) and pairs with the opener.
    @Test("single-quote run before Unicode punctuation opens then closes")
    func singleQuoteBeforeUnicodePunct() throws {
        // U+055E (Armenian question mark, Po), U+00A1 (inverted exclamation, Po), U+2014 (em dash, Pd).
        #expect(try render("''\u{055E}", options: .smart) == "\u{2018}\u{2019}\u{055E}")
        #expect(try render("''\u{00A1}", options: .smart) == "\u{2018}\u{2019}\u{00A1}")
        #expect(try render("''\u{2014}", options: .smart) == "\u{2018}\u{2019}\u{2014}")
    }

    @Test("a further trailing quote after Unicode punctuation stays a right curly")
    func trailingQuoteAfterUnicodePunct() throws {
        #expect(try render("''\u{055E}'", options: .smart) == "\u{2018}\u{2019}\u{055E}\u{2019}")
    }

    @Test("double-quote run before Unicode punctuation opens then closes")
    func doubleQuoteBeforeUnicodePunct() throws {
        #expect(try render("\"\"\u{055E}", options: .smart) == "\u{201C}\u{201D}\u{055E}")
    }

    // MARK: - Smart-quote controls (must not regress)

    @Test("quote run before a letter stays two right curlies")
    func quoteRunBeforeLetter() throws {
        #expect(try render("''a", options: .smart) == "\u{2019}\u{2019}a")
    }

    @Test("lone single quote before Unicode punctuation stays a right curly")
    func loneQuoteBeforeUnicodePunct() throws {
        #expect(try render("'\u{055E}", options: .smart) == "\u{2019}\u{055E}")
    }

    @Test("letter-preceded quote run before Unicode punctuation stays two right curlies")
    func letterPrecededQuoteRun() throws {
        #expect(try render("x''\u{055E}", options: .smart) == "x\u{2019}\u{2019}\u{055E}")
    }

    @Test("quote run before ASCII punctuation across a space opens then closes")
    func quoteRunBeforeASCIIPunct() throws {
        #expect(try render("'' .", options: .smart) == "\u{2018}\u{2019} .")
    }

    // MARK: - Emphasis (shares the flanking machinery)

    /// A `*` run whose only non-space neighbour is a Unicode punctuation character must NOT pair into
    /// emphasis: the inner `*` sees punctuation on the inside and a letter/space outside, so it is
    /// left-flanking only (cannot close), matching cmark. The rewrite formerly treated the raw
    /// continuation/lead byte of the multibyte punctuation as a non-punct, non-space byte, which made
    /// the inner `*` right-flanking and spuriously formed emphasis.
    @Test("emphasis does not form around Unicode punctuation with an outer letter")
    func emphasisAroundUnicodePunctNoPair() throws {
        #expect(try render("*\u{055E}*a") == "*\u{055E}*a")
        #expect(try render("a*\u{055E}*") == "a*\u{055E}*")
    }

    // MARK: - Emphasis controls (must not regress)

    @Test("emphasis forms when a Unicode punctuation char precedes the whole run")
    func emphasisWithUnicodePunctBefore() throws {
        #expect(try render("\u{055E} *a*") == "\u{055E} <em>a</em>")
    }

    @Test("underscore run around Unicode punctuation with an outer letter does not pair")
    func underscoreAroundUnicodePunctNoPair() throws {
        #expect(try render("_\u{055E}_a") == "_\u{055E}_a")
    }

    @Test("emphasis forms around an em dash followed by a space")
    func emphasisAroundEmDash() throws {
        #expect(try render("*\u{2014}* x") == "<em>\u{2014}</em> x")
    }

    @Test("strong forms around Unicode punctuation")
    func strongAroundUnicodePunct() throws {
        #expect(try render("**\u{055E}**") == "<strong>\u{055E}</strong>")
    }

    @Test("emphasis does not form around ASCII punctuation with an outer letter")
    func emphasisAroundASCIIPunctNoPair() throws {
        #expect(try render("*.*a") == "*.*a")
    }
}
