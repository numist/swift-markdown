/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An HTML comment (Raw HTML) is `<!--`, text not containing `-->`, and `-->`, so `<!----->` is a comment whose text
/// is `-`.
@Suite("Inline HTML comments made of dashes")
struct InlineHTMLCommentDashesTests {

    @Test("`<!----->` (five dashes) is an inline HTML comment")
    func fiveDashesRecognized() {
        #expect(TreeDump.dump("F<!----->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!----->"

            """)
    }

    @Test("`<!---->` (four dashes) is a comment")
    func fourDashesRecognized() {
        #expect(TreeDump.dump("F<!---->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!---->"

            """)
    }

    @Test("`<!--->` (three dashes, empty form) is a comment")
    func threeDashesRecognized() {
        #expect(TreeDump.dump("F<!--->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!--->"

            """)
    }

    @Test("`<!-->` (two dashes, empty form) is a comment")
    func twoDashesRecognized() {
        #expect(TreeDump.dump("F<!-->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!-->"

            """)
    }

    @Test("`<!--x-->` is a comment")
    func normalCommentRecognized() {
        #expect(TreeDump.dump("F<!--x-->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!--x-->"

            """)
    }

    @Test("`<!-- -->` is a comment")
    func spaceCommentRecognized() {
        #expect(TreeDump.dump("F<!-- -->", options: []) == """
            document
              paragraph
                text "F"
                html_inline "<!-- -->"

            """)
    }
}
