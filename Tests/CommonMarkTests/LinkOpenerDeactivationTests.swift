/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Links may not contain other links (Links), so once a link or autolink forms, no `[` opened before it forms a link,
/// whatever brackets open between them. Image and attribute openers still form around it.
@Suite("Link openers before a link or autolink")
struct LinkOpenerDeactivationTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.attributes])
    }

    @Test("a link inside an image keeps an enclosing `[` from forming a link")
    func linkInsideImage() {
        #expect(tree("[a ![b [c](d)](e)](f)") == """
            document
              paragraph
                text "[a "
                image "e" ""
                  text "b "
                  link "d" ""
                    text "c"
                text "](f)"

            """)
    }

    @Test("a link inside an attribute keeps an enclosing `[` from forming a link")
    func linkInsideAttribute() {
        #expect(tree("[a ^[b [c](d)](e)](f)") == """
            document
              paragraph
                text "[a "
                attribute "e"
                  text "b "
                  link "d" ""
                    text "c"
                text "](f)"

            """)
    }

    @Test("an autolink inside an image keeps an enclosing `[` from forming a link")
    func autolinkInsideImage() {
        #expect(tree("[a ![<http://c>](e)](f)") == """
            document
              paragraph
                text "[a "
                image "e" ""
                  link "http://c" ""
                    text "http://c"
                text "](f)"

            """)
    }

    @Test("a `[` opened after a link forms a link")
    func openerAfterLink() {
        #expect(tree("[a [b](c) [d](e)](f)") == """
            document
              paragraph
                text "[a "
                link "c" ""
                  text "b"
                text " "
                link "e" ""
                  text "d"
                text "](f)"

            """)
    }
}
