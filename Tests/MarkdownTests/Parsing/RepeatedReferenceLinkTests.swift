/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Uses of link reference definitions resolve until their destinations and titles, after backslash escapes and
/// character references are resolved, reach the 100,000-byte reference expansion budget; later uses stay text.
class RepeatedReferenceLinkTests: XCTestCase {
    /// A definition of `label` whose destination is `/` followed by `length` copies of `a`.
    private static func definition(_ label: String, length: Int = 2000) -> String {
        "[\(label)]: /" + String(repeating: "a", count: length) + "\n\n"
    }

    private static func uses(_ use: String, _ count: Int) -> String {
        Array(repeating: use, count: count).joined(separator: " ")
    }

    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    private func count(_ needle: String, in tree: String) -> Int {
        tree.components(separatedBy: needle).count - 1
    }

    private func links(_ markdown: String) -> Int {
        count("Link destination:", in: tree(markdown))
    }

    func testUsesResolveUntilTheBudget() {
        XCTAssertEqual(49, links(Self.definition("bar") + Self.uses("[bar]", 1000)))
    }

    func testLabelsShareTheBudget() {
        let markdown = Self.definition("a", length: 1999) + Self.definition("b")
            + Self.uses("[a]", 1000) + " [b] [a] [a]"
        let result = tree(markdown)
        XCTAssertEqual(50, count("Link destination:", in: result))
        XCTAssertEqual(0, count("Link destination: \"/" + String(repeating: "a", count: 2000) + "\"", in: result))
    }

    /// A full reference past the budget stays text rather than resolving its link text as a shortcut reference.
    func testFullReferencePastTheBudgetStaysText() {
        let markdown = Self.definition("a", length: 1999) + Self.definition("b")
            + Self.uses("[a]", 1000) + " [a][b] [a] [a]"
        let result = tree(markdown)
        XCTAssertEqual(50, count("Link destination:", in: result))
        XCTAssertEqual(1, count("[a][b]", in: result))
        XCTAssertEqual(0, count("Link destination: \"/" + String(repeating: "a", count: 2000) + "\"", in: result))
    }

    func testFullAndCollapsedFormsShareTheBudget() {
        let markdown = Self.definition("bar")
            + Self.uses("[bar]", 1000) + " " + Self.uses("[bar][]", 1000) + " " + Self.uses("[t][bar]", 1000)
        let result = tree(markdown)
        XCTAssertEqual(49, count("Link destination:", in: result))
        XCTAssertEqual(1000, count("[]", in: result))
    }

    func testImageReferencesShareTheBudget() {
        let images = Self.definition("bar") + Self.uses("![bar]", 1000)
        XCTAssertEqual(49, count("Image source:", in: tree(images)))
        let mixed = Self.definition("bar") + Self.uses("[bar] ![bar]", 1000)
        let result = tree(mixed)
        XCTAssertEqual(25, count("Link destination:", in: result))
        XCTAssertEqual(24, count("Image source:", in: result))
    }

    func testTitleIsCharged() {
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + String(repeating: "t", count: 1000) + "\"\n\n"
            + Self.uses("[bar]", 1000)
        XCTAssertEqual(50, links(markdown))
    }

    func testDestinationIsChargedAfterCharacterReferences() {
        let markdown = "[bar]: /" + String(repeating: "&amp;", count: 1999) + "\n\n" + Self.uses("[bar]", 1000)
        XCTAssertEqual(50, links(markdown))
    }

    func testTitleIsChargedAfterBackslashEscapesAndCharacterReferences() {
        let title = String(repeating: "\\*", count: 500) + String(repeating: "&eacute;", count: 250)
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + title + "\"\n\n"
            + Self.uses("[bar]", 1000)
        XCTAssertEqual(50, links(markdown))
    }

    func testNULInDestinationIsChargedAsTheReplacementCharacter() {
        let markdown = "[bar]: /" + String(repeating: "\u{0}", count: 666) + "a\n\n" + Self.uses("[bar]", 1000)
        XCTAssertEqual(50, links(markdown))
    }

    /// `[bar]` names no inline attribute definition, so after each `^[t]` it is dropped.
    func testAttributeLookupOfLinkReference() {
        let markdown = Self.definition("bar") + Self.uses("^[t][bar]", 10) + " " + Self.uses("[bar]", 30)
        let result = tree(markdown)
        XCTAssertEqual(0, count("InlineAttributes", in: result))
        XCTAssertEqual(30, count("Link destination:", in: result))
    }

    /// Each `^[t](a)` forms inline attributes, and every `[bar]` is a link.
    func testAttributeLookupAfterInlineForm() {
        let markdown = Self.definition("bar") + Self.uses("^[t](a)[bar]", 10) + " " + Self.uses("[bar]", 30)
        let result = tree(markdown)
        XCTAssertEqual(10, count("InlineAttributes", in: result))
        XCTAssertEqual(40, count("Link destination:", in: result))
    }

    func testBlocksShareTheBudgetInDocumentOrder() {
        let markdown = Self.definition("bar") + "# " + Self.uses("[bar]", 500) + "\n\n" + Self.uses("[bar]", 500)
        let result = tree(markdown)
        let paragraph = result.components(separatedBy: "Paragraph").last!
        XCTAssertEqual(49, count("Link destination:", in: result))
        XCTAssertEqual(0, count("Link destination:", in: paragraph))
    }
}
