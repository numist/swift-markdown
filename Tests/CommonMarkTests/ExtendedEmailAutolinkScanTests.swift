/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An extended email autolink's local part is the run of ASCII alphanumerics, `.`, `+`, `-` and `_` before the `@`.
/// A lowercase `mailto:` or `xmpp:` directly before the local part, and not directly after an ASCII letter or digit, is
/// part of the autolink, as are the local-part characters before it, and the destination is then the link text with
/// no `mailto:` added. With such a scheme the local part may be empty, and after `xmpp:` the domain may hold `/`,
/// though not as its last character. A second `@` in the domain restarts the address after the first `@`; a scheme
/// before the first `@`, and a period in the domain before the second, still count for the restarted address.
@Suite("Extended email autolink scan")
struct ExtendedEmailAutolinkScanTests {
    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func plainAddressGetsMailtoDestination() {
        #expect(tree("a@b.c") == """
            document
              paragraph
                link "mailto:a@b.c" ""
                  text "a@b.c"

            """)
    }

    @Test func localPartStopsAtOtherCharacter() {
        #expect(tree("a!b@c.d") == """
            document
              paragraph
                text "a!"
                link "mailto:b@c.d" ""
                  text "b@c.d"

            """)
    }

    @Test func secondAtSignRestartsAddress() {
        #expect(tree("a@b.c@d.e") == """
            document
              paragraph
                text "a@"
                link "mailto:b.c@d.e" ""
                  text "b.c@d.e"

            """)
    }

    @Test func restartedAddressAfterSchemeGetsNoMailtoDestination() {
        #expect(tree("mailto:a@b.c@d.e") == """
            document
              paragraph
                text "mailto:a@"
                link "b.c@d.e" ""
                  text "b.c@d.e"

            """)
    }

    @Test func periodBeforeSecondAtSignCountsForRestartedAddress() {
        #expect(tree("a@b.c@d") == """
            document
              paragraph
                text "a@"
                link "mailto:b.c@d" ""
                  text "b.c@d"

            """)
        #expect(tree("a@bc@d") == text("a@bc@d"))
    }

    @Test func domainEndsBeforePeriodWithoutAlphanumeric() {
        #expect(tree("a@x.y.-5") == """
            document
              paragraph
                link "mailto:a@x.y" ""
                  text "a@x.y"
                text ".-5"

            """)
    }

    @Test func domainSegmentStartingWithHyphenAfterPeriodIsText() {
        #expect(tree("a@b.-c") == text("a@b.-c"))
    }

    // MARK: - Schemes

    @Test func mailtoSchemeIsPartOfLink() {
        #expect(tree("mailto:x@a.b") == """
            document
              paragraph
                link "mailto:x@a.b" ""
                  text "mailto:x@a.b"

            """)
    }

    @Test func xmppSchemeIsPartOfLink() {
        #expect(tree("xmpp:x@a.b") == """
            document
              paragraph
                link "xmpp:x@a.b" ""
                  text "xmpp:x@a.b"

            """)
    }

    @Test func xmppDomainHoldsSlash() {
        #expect(tree("xmpp:x@a.b/c") == """
            document
              paragraph
                link "xmpp:x@a.b/c" ""
                  text "xmpp:x@a.b/c"

            """)
    }

    @Test func xmppAddressWithResourceIsLink() {
        #expect(tree("xmpp:a@b.c/d") == """
            document
              paragraph
                link "xmpp:a@b.c/d" ""
                  text "xmpp:a@b.c/d"

            """)
    }

    @Test func xmppAddressEndingInSlashIsText() {
        #expect(tree("xmpp:a@b.c/") == text("xmpp:a@b.c/"))
    }

    @Test func schemeAllowsEmptyLocalPart() {
        #expect(tree("mailto:@a.b") == """
            document
              paragraph
                link "mailto:@a.b" ""
                  text "mailto:@a.b"

            """)
        #expect(tree("@a.b") == text("@a.b"))
    }

    @Test func schemeAfterText() {
        #expect(tree("x mailto:a@b.c") == """
            document
              paragraph
                text "x "
                link "mailto:a@b.c" ""
                  text "mailto:a@b.c"

            """)
    }

    @Test func localPartCharacterBeforeSchemeJoinsLink() {
        #expect(tree(".mailto:x@a.b") == """
            document
              paragraph
                link ".mailto:x@a.b" ""
                  text ".mailto:x@a.b"

            """)
    }

    @Test func schemeAfterPunctuationJoinsLocalPart() {
        #expect(tree("a.mailto:x@b.c") == """
            document
              paragraph
                link "a.mailto:x@b.c" ""
                  text "a.mailto:x@b.c"

            """)
    }

    @Test func uppercaseSchemeEndsLocalPart() {
        #expect(tree("MAILTO:x@a.b") == """
            document
              paragraph
                text "MAILTO:"
                link "mailto:x@a.b" ""
                  text "x@a.b"

            """)
    }

    @Test func otherSchemeEndsLocalPart() {
        #expect(tree("foo:x@a.b") == """
            document
              paragraph
                text "foo:"
                link "mailto:x@a.b" ""
                  text "x@a.b"

            """)
    }

    @Test func schemeAfterLetterEndsLocalPart() {
        #expect(tree("amailto:x@a.b") == """
            document
              paragraph
                text "amailto:"
                link "mailto:x@a.b" ""
                  text "x@a.b"

            """)
    }
}
