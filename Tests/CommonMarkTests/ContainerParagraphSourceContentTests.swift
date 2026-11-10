/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A plain paragraph that continues across container prefixes (`> `, list indentation) is stored as one source
/// segment per line, with no copy of its text.
@Suite("Multi-line container paragraphs keep source content")
struct ContainerParagraphSourceContentTests {

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test(arguments: [
        ("> a\n> b\n> c\n", """
            "a" source
            "b" source
            "c" source

            """),
        ("- a\n  b\n  c\n", """
            "a" source
            "b" source
            "c" source

            """),
        ("> a b\n> c d\n> e f\n\n- x y\n  z w\n", """
            "a b" source
            "c d" source
            "e f" source
            "x y" source
            "z w" source

            """),
    ])
    func linesStayInSource(_ source: String, _ text: String) {
        #expect(SourceBackedText.describe(source, options: []) == text)
        #expect(SourceBackedText.describe(source, options: [.tables, .tasklist, .footnotes, .attributes]) == text)
    }

    @Test(arguments: [
        "> a\n> b\n> c\n",
        "- a\n  b\n  c\n",
        "> a b\n> c d\n> e f\n\n- x y\n  z w\n",
        "> a\n> b\n> c\n> d\n",
        "> a\n> |-\n",
        "> a | b | c\n> --|--\n",
    ])
    func noMaterializedCopy(_ source: String) {
        // The materialized string buffer holds only the shared newline.
        #expect(MarkdownDocument.withParsedDocument(source, options: []) { $0._materializedStringSize } == 1)
        #expect(MarkdownDocument.withParsedDocument(source, options: [.tables]) { $0._materializedStringSize } == 1)
    }
}
