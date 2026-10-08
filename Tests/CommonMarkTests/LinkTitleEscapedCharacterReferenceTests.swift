/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Link titles with a backslash before a character reference.
///
/// A backslash before `&` escapes it, so what follows is literal text rather than a character reference (Backslash
/// escapes, Entity and numeric character references). An escaped backslash leaves the reference after it to be
/// decoded.
@Suite("Link title character references after a backslash")
struct LinkTitleEscapedCharacterReferenceTests {

    static let cases: [(title: String, expected: String)] = [
        ("'\\&#65;'", "&#65;"),
        ("'\\&#x41;'", "&#x41;"),
        ("'\\&Auml;'", "&Auml;"),
        ("'\\&amp;'", "&amp;"),
        ("'\\&#3;'", "&#3;"),
        ("'\\&#0;'", "&#0;"),
        ("'\\&#32;'", "&#32;"),
        ("\"\\&#65;\"", "&#65;"),
        ("(\\&#65;)", "&#65;"),
        ("'x\\&#65;y'", "x&#65;y"),
        ("'\\\\&#65;'", "\\A"),
        ("'\\&#65'", "&#65"),
        ("'\\&foo;'", "&foo;"),
        ("'&#3;'", "\u{3}"),
    ]

    @Test("inline link", arguments: cases)
    func inlineLink(_ testCase: (title: String, expected: String)) {
        let markdown = "[](a \(testCase.title))"
        #expect(titles(markdown) == [testCase.expected], "\(markdown.debugDescription)")
    }

    @Test("inline image", arguments: cases)
    func inlineImage(_ testCase: (title: String, expected: String)) {
        let markdown = "![](a \(testCase.title))"
        #expect(titles(markdown) == [testCase.expected], "\(markdown.debugDescription)")
    }

    @Test("reference definition", arguments: cases)
    func referenceDefinition(_ testCase: (title: String, expected: String)) {
        let markdown = "[a]\n\n[a]: b \(testCase.title)"
        #expect(titles(markdown) == [testCase.expected], "\(markdown.debugDescription)")
    }

    @Test("reference definition used by an image", arguments: cases)
    func referenceDefinitionImage(_ testCase: (title: String, expected: String)) {
        let markdown = "![a]\n\n[a]: b \(testCase.title)"
        #expect(titles(markdown) == [testCase.expected], "\(markdown.debugDescription)")
    }

    private func titles(_ markdown: String) -> [String] {
        MarkdownDocument.withParsedDocument(markdown, options: []) { document in
            var titles: [String] = []
            collectTitles(document.root, into: &titles)
            return titles
        }
    }

    private func collectTitles(_ node: borrowing MarkdownNode, into titles: inout [String]) {
        if let title = node.title() { titles.append(title) }
        node.children.forEach { collectTitles($0, into: &titles) }
    }
}
