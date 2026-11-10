/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Code spans and raw HTML bind more tightly than the brackets in link text (Links), and likewise than a
/// footnote-shaped bracket: with no matching link reference definition, one enclosing a code span, raw HTML or image
/// that spans a line ending is literal text around it. A backslash before the line ending there is literal, not a hard
/// line break (Hard line breaks).
@Suite("Footnote-shaped bracket around a code span, raw HTML or image spanning a line ending")
struct FootnoteRawInlineCrossLineTests {

    static let cases: [(markdown: String, expected: String)] = [
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
        ("[^<!--\n-->]", """
            document
              paragraph
                text "[^"
                html_inline "<!--\\n-->"
                text "]"

            """),
        ("[^x\n`y\nz`]", """
            document
              paragraph
                text "[^x"
                softbreak
                code "y z"
                text "]"

            """),
    ]

    @Test(arguments: cases)
    func bracketStaysLiteral(_ markdown: String, _ expected: String) {
        #expect(TreeDump.dump(markdown, options: [.sourcePosition, .footnotes]) == expected)
    }
}
