/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An extended url or www autolink (Autolinks (extension)) doesn't form while an unclosed `[` or `![` opener
/// precedes it in the same inline content.
@Suite("Extended autolinks after an unclosed bracket")
struct AutolinkBracketOpenerTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    @Test("unclosed `[` before a URL leaves it as text")
    func openBracketSuppressesURLAutolink() {
        #expect(TreeDump.dump("[http://t.t", options: Self.options) == """
            document
              paragraph
                text "[http://t.t"

            """)
    }

    @Test("unclosed `![` before a URL leaves it as text")
    func openImageBracketSuppressesURLAutolink() {
        #expect(TreeDump.dump("![http://t.t", options: Self.options) == """
            document
              paragraph
                text "![http://t.t"

            """)
    }

    @Test("a URL with no leading `[` autolinks")
    func bareURLAutolinks() {
        #expect(TreeDump.dump("http://t.t", options: Self.options) == """
            document
              paragraph
                link "http://t.t" ""
                  text "http://t.t"

            """)
    }

    @Test("`[x](http://t.t)` is an inline link")
    func closedLinkParses() {
        #expect(TreeDump.dump("[x](http://t.t)", options: Self.options) == """
            document
              paragraph
                link "http://t.t" ""
                  text "x"

            """)
    }

    @Test("a URL after a closed `[…]` autolinks")
    func afterClosedBracketAutolinks() {
        #expect(TreeDump.dump("[a] http://t.t", options: Self.options) == """
            document
              paragraph
                text "[a] "
                link "http://t.t" ""
                  text "http://t.t"

            """)
    }
}
