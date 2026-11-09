/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An extended autolink's sibling text nodes hold the text around it, with no empty text node where nothing
/// precedes or follows it.
@Suite("Text around extended autolinks")
struct AutolinkEmptySiblingTests {

    @Test("www autolink between text")
    func wwwMidText() {
        #expect(TreeDump.dump("x www.example.com y", options: .gfmAutolink) == """
            document
              paragraph
                text "x "
                link "http://www.example.com" ""
                  text "www.example.com"
                text " y"

            """)
    }

    @Test("scheme URL after text")
    func schemeURLAfterText() {
        #expect(TreeDump.dump("x https://y.io", options: .gfmAutolink) == """
            document
              paragraph
                text "x "
                link "https://y.io" ""
                  text "https://y.io"

            """)
    }

    @Test("www autolink alone")
    func wwwAtStart() {
        #expect(TreeDump.dump("www.example.com", options: .gfmAutolink) == """
            document
              paragraph
                link "http://www.example.com" ""
                  text "www.example.com"

            """)
    }

    @Test("email autolink alone")
    func emailAlone() {
        #expect(TreeDump.dump("o@x.x", options: .gfmAutolink) == """
            document
              paragraph
                link "mailto:o@x.x" ""
                  text "o@x.x"

            """)
    }

    @Test("scheme URL alone")
    func schemeURLAlone() {
        #expect(TreeDump.dump("https://x.io", options: .gfmAutolink) == """
            document
              paragraph
                link "https://x.io" ""
                  text "https://x.io"

            """)
    }

    @Test("email autolink before text")
    func emailTrailingText() {
        #expect(TreeDump.dump("o@x.x y", options: .gfmAutolink) == """
            document
              paragraph
                link "mailto:o@x.x" ""
                  text "o@x.x"
                text " y"

            """)
    }

    @Test("email autolink before emphasis")
    func emailBeforeEmphasis() {
        #expect(TreeDump.dump("o@x.x*a*", options: .gfmAutolink) == """
            document
              paragraph
                link "mailto:o@x.x" ""
                  text "o@x.x"
                emph
                  text "a"

            """)
    }
}
