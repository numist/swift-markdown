/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Whitespace (Characters and lines) includes line tabulation and form feed, so they count wherever the spec speaks
/// of whitespace: in link label matching and blank labels (Links), and in trimming an info string (Fenced code
/// blocks).
@Suite("Line tabulation and form feed as whitespace")
struct LineTabulationFormFeedWhitespaceTests {
    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [])
    }

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func labelWhitespaceCollapsesForMatching(_ whitespace: String, _ escaped: String) {
        #expect(surface("[a\(whitespace)b]: /u\n\n[a b]") == """
            document
              paragraph
                link "/u" ""
                  text "a b"

            """)
        #expect(surface("[a b]: /u\n\n[a\(whitespace)\(whitespace)b]") == """
            document
              paragraph
                link "/u" ""
                  text "a\(escaped)\(escaped)b"

            """)
    }

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func whitespaceOnlyLabelIsNoLabel(_ whitespace: String, _ escaped: String) {
        #expect(surface("[\(whitespace)]: /u\n\n[\(whitespace)]") == """
            document
              paragraph
                text "[\(escaped)]: /u"
              paragraph
                text "[\(escaped)]"

            """)
    }

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func whitespaceOnlyFullReferenceLabelLeavesShortcut(_ whitespace: String, _ escaped: String) {
        #expect(surface("[x][\(whitespace)]\n\n[x]: /u") == """
            document
              paragraph
                link "/u" ""
                  text "x"
                text "[\(escaped)]"

            """)
    }

    /// A footnote definition's label holds no whitespace, so, as with a space, `[^\u{B}]: x` is a link reference
    /// definition whose label is `^` and a line tabulation.
    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func footnoteDefinitionLabelWithWhitespaceIsLinkReferenceDefinition(_ whitespace: String, _ escaped: String) {
        #expect(TreeDump.dump("[^\(whitespace)]: x\n\n[^\(whitespace)]", options: [.footnotes]) == """
            document
              paragraph
                link "x" ""
                  text "^\(escaped)"

            """)
        #expect(TreeDump.dump("[^\\\(whitespace)]: x\n\n[^\\\(whitespace)]", options: [.footnotes]) == """
            document
              paragraph
                link "x" ""
                  text "^\\\\\(escaped)"

            """)
        #expect(TreeDump.dump("[^a\(whitespace)b]: x\n\n[^a b]", options: [.footnotes]) == """
            document
              paragraph
                link "x" ""
                  text "^a b"

            """)
    }

    @Test(arguments: ["\u{0B}", "\u{0C}"])
    func infoStringIsTrimmedOfWhitespace(_ whitespace: String) {
        #expect(surface("```\(whitespace)js\(whitespace) \n```") == """
            document
              code_block "js" ""

            """)
    }
}
