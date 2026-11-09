/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only mode has no footnote definitions, so a footnote-shaped bracket is text.
@Suite("Footnote-shaped brackets in inline-only mode")
struct InlineOnlyFootnoteShapedBracketTests {

    static let modes: [MarkdownDocument.ParseOptions] = [
        [.sourcePosition, .footnotes, .inlineOnly],
        [.sourcePosition, .footnotes, .preserveWhitespace],
    ]

    static let cases: [(markdown: String, expected: String)] = [
        ("[^\n\u{FFFD}]", """
            document
              paragraph
                text "[^\\n\u{FFFD}]"

            """),
        ("[^[]\n]", """
            document
              paragraph
                text "[^[]\\n]"

            """),
        ("[^[\n]]", """
            document
              paragraph
                text "[^[\\n]]"

            """),
        ("[\\^\nx]", """
            document
              paragraph
                text "[^\\nx]"

            """),
        ("![\\^x]", """
            document
              paragraph
                text "![^x]"

            """),
        (">[^\n\u{FFFD}]", """
            document
              paragraph
                text ">[^\\n\u{FFFD}]"

            """),
        ("[^\n\u{FFFD}p]", """
            document
              paragraph
                text "[^\\n\u{FFFD}p]"

            """),
        ("a[^x\ny]b", """
            document
              paragraph
                text "a[^x\\ny]b"

            """),
        ("[^a\r\nb]", """
            document
              paragraph
                text "[^a\\nb]"

            """),
        // The line ending inside the code span becomes a space (Code spans).
        ("[^`a\nb`\nc]", """
            document
              paragraph
                text "[^"
                code "a b"
                text "\\nc]"

            """),
        ("[\\^abcdef\nxxxxx]", """
            document
              paragraph
                text "[^abcdef\\nxxxxx]"

            """),
        ("![\\^a\nb]", """
            document
              paragraph
                text "![^a\\nb]"

            """),
        ("![\\^x]\n", """
            document
              paragraph
                text "![^x]\\n"

            """),
    ]

    @Test(arguments: cases, modes)
    func bracketIsText(_ testCase: (markdown: String, expected: String), _ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(testCase.markdown, options: options) == testCase.expected)
    }
}
