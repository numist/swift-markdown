/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An extended email autolink's local part is the run of local-part characters before the `@`, so the autolink may
/// follow any other character.
@Suite("Extended email autolink preceding character")
struct AutolinkEmailPrecedingCharTests {

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [.gfmAutolink])
    }

    @Test("email autolinks after a leading `<`")
    func emailAfterAngle() {
        // Without a `>`, the `<` is literal text.
        #expect(tree("<o@e.e") == """
            document
              paragraph
                text "<"
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("standalone email autolinks")
    func emailStandalone() {
        #expect(tree("o@e.e") == """
            document
              paragraph
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("email after text and a space autolinks")
    func emailAfterTextSpace() {
        #expect(tree("x o@e.e") == """
            document
              paragraph
                text "x "
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("email after `(` autolinks")
    func emailAfterParen() {
        #expect(tree("(o@e.e") == """
            document
              paragraph
                text "("
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    // MARK: - Local-part characters

    // An extended email autolink's local part holds only alphanumerics, `.`, `-`, `_` and `+`, unlike the email
    // address of an email autolink (Autolinks), which admits characters such as `!`.

    @Test("`<a!@e.e` is text: `!` is not a local-part character")
    func bangBeforeAtNoLink() {
        #expect(tree("<a!@e.e") == """
            document
              paragraph
                text "<a!@e.e"

            """)
    }

    @Test("`x!@e.e` at the start of a line is text")
    func bangLocalAtStartNoLink() {
        #expect(tree("x!@e.e") == """
            document
              paragraph
                text "x!@e.e"

            """)
    }

    @Test("an email autolink admits `!` in its local part")
    func angleEmailKeepsBroadLocalSet() {
        #expect(tree("<a!b@c.de>") == """
            document
              paragraph
                link "mailto:a!b@c.de" ""
                  text "a!b@c.de"

            """)
    }
}
