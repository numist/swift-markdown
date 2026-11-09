/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An absolute URI excludes ASCII control characters (Autolinks), including DEL (U+007F), so a `<…>` containing
/// one is literal text.
@Suite("URI autolink control characters")
struct URIAutolinkControlCharacterTests {

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [])
    }

    @Test("`<tp:\\u{7F}>` is literal text")
    func delNotLink() {
        #expect(tree("<tp:\u{7F}>") == """
            document
              paragraph
                text "<tp:\\u{7F}>"

            """)
    }

    @Test("`<http://a\\u{7F}>` is literal text")
    func delInHttpNotLink() {
        #expect(tree("<http://a\u{7F}>") == """
            document
              paragraph
                text "<http://a\\u{7F}>"

            """)
    }

    @Test("`<tp:a\\u{7F}b>` is literal text")
    func delMidBodyNotLink() {
        #expect(tree("<tp:a\u{7F}b>") == """
            document
              paragraph
                text "<tp:a\\u{7F}b>"

            """)
    }

    @Test("`<tp:x>` is a link")
    func plainURILinks() {
        #expect(tree("<tp:x>") == """
            document
              paragraph
                link "tp:x" ""
                  text "tp:x"

            """)
    }

    @Test("`<tp:\\u{1F}>` is literal text")
    func c0ControlNotLink() {
        #expect(tree("<tp:\u{1F}>") == """
            document
              paragraph
                text "<tp:\\u{1F}>"

            """)
    }

    @Test("`<tp:\\u{0B}>` is literal text")
    func vtControlNotLink() {
        #expect(tree("<tp:\u{0B}>") == """
            document
              paragraph
                text "<tp:\\u{B}>"

            """)
    }
}
