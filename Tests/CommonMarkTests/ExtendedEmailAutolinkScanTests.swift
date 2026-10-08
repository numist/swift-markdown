/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An extended email autolink's local part is the run of ASCII alphanumerics, `.`, `+`, `-` and `_` before the `@`,
/// reaching back through a lowercase `mailto:` or `xmpp:` scheme that follows a non-alphanumeric character. A second
/// `@` in the domain restarts the address after the first `@`, keeping the scheme and the periods already scanned.
@Suite("Extended email autolink scan")
struct ExtendedEmailAutolinkScanTests {
    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func localPartStopsAtOtherCharacter() {
        #expect(surface("a!b@c.d") == """
            document
              paragraph
                text "a!"
                link "mailto:b@c.d" ""
                  text "b@c.d"

            """)
    }

    @Test func secondAtSignRestartsAddress() {
        #expect(surface("a@b.c@d.e") == """
            document
              paragraph
                text "a@"
                link "mailto:b.c@d.e" ""
                  text "b.c@d.e"

            """)
    }

    @Test func restartedAddressKeepsScheme() {
        #expect(surface("mailto:a@b.c@d.e") == """
            document
              paragraph
                text "mailto:a@"
                link "b.c@d.e" ""
                  text "b.c@d.e"

            """)
    }

    @Test func schemeAfterPunctuationJoinsLocalPart() {
        #expect(surface("a.mailto:x@b.c") == """
            document
              paragraph
                link "a.mailto:x@b.c" ""
                  text "a.mailto:x@b.c"

            """)
    }

    @Test func domainEndsBeforePeriodWithoutAlphanumeric() {
        #expect(surface("a@x.y.-5") == """
            document
              paragraph
                link "mailto:a@x.y" ""
                  text "a@x.y"
                text ".-5"

            """)
    }

    @Test func domainSegmentStartingWithHyphenAfterPeriodIsText() {
        #expect(surface("a@b.-c") == text("a@b.-c"))
    }

    @Test func xmppAddressEndingInSlashIsText() {
        #expect(surface("xmpp:a@b.c/") == text("xmpp:a@b.c/"))
    }

    @Test func xmppAddressWithResourceIsLink() {
        #expect(surface("xmpp:a@b.c/d") == """
            document
              paragraph
                link "xmpp:a@b.c/d" ""
                  text "xmpp:a@b.c/d"

            """)
    }
}
