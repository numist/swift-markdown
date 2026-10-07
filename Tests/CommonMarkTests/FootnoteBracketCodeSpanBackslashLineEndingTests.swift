/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A cross-line footnote-shaped bracket whose line ending sits inside a code span after a backslash.
@Suite("Footnote-shaped bracket around a code span holding a backslash and a line ending")
struct FootnoteBracketCodeSpanBackslashLineEndingTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink, .footnotes]

    /// With no footnote definition, the bracket is literal text around the code span, raw HTML or image it holds. A
    /// backslash before a line ending there is literal, not a hard line break (Hard line breaks).
    @Test func testBracketStaysLiteral() {
        let cases: [(markdown: String, expected: String)] = [
            ("[^`\\\n`]", """
                document
                  paragraph
                    text "[^"
                    code "\\\\ "
                    text "]"

                """),
            ("[^`a\\\nb`]", """
                document
                  paragraph
                    text "[^"
                    code "a\\\\ b"
                    text "]"

                """),
            ("[^a`\\\n`]", """
                document
                  paragraph
                    text "[^a"
                    code "\\\\ "
                    text "]"

                """),
            ("[^`\\\n`] x", """
                document
                  paragraph
                    text "[^"
                    code "\\\\ "
                    text "] x"

                """),
            ("[^`\\\r\n`]", """
                document
                  paragraph
                    text "[^"
                    code "\\\\ "
                    text "]"

                """),
            ("[^`\\\r`]", """
                document
                  paragraph
                    text "[^"
                    code "\\\\ "
                    text "]"

                """),
            ("[^`\n`]", """
                document
                  paragraph
                    text "[^"
                    code " "
                    text "]"

                """),
            ("[^``\\\n``]", """
                document
                  paragraph
                    text "[^"
                    code "\\\\ "
                    text "]"

                """),
            ("[^`a  \n`]", """
                document
                  paragraph
                    text "[^"
                    code "a   "
                    text "]"

                """),
            ("[^<a b=\"\\\n\">]", """
                document
                  paragraph
                    text "[^"
                    html_inline "<a b=\\"\\\\\\n\\">"
                    text "]"

                """),
            ("[^![x](/u \"a\\\nb\")]", """
                document
                  paragraph
                    text "[^"
                    image "/u" "a\\\\\\nb"
                      text "x"
                    text "]"

                """),
        ]
        for (markdown, expected) in cases {
            #expect(TreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
        }
    }
}
