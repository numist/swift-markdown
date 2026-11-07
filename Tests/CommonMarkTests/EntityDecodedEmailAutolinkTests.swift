/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An `@` decoded from a character reference is text like any other, so the merged text around it can hold an
/// extended email autolink (Autolinks (extension)).
@Suite("Extended email autolinks around a decoded `@`")
struct EntityDecodedEmailAutolinkTests {

    @Test("a decimal numeric reference")
    func decimalReference() {
        #expect(TreeDump.dump("foo&#64;bar.com", options: [.gfmAutolink]) == """
            document
              paragraph
                link "mailto:foo@bar.com" ""
                  text "foo@bar.com"

            """)
    }

    @Test("a named reference")
    func namedReference() {
        #expect(TreeDump.dump("a&commat;b.co", options: [.gfmAutolink]) == """
            document
              paragraph
                link "mailto:a@b.co" ""
                  text "a@b.co"

            """)
    }

    @Test("a decoded `@` after other text in the line")
    func afterOtherText() {
        #expect(TreeDump.dump("see x&#x40;y.com now", options: [.gfmAutolink]) == """
            document
              paragraph
                text "see "
                link "mailto:x@y.com" ""
                  text "x@y.com"
                text " now"

            """)
    }
}
