/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Text holding two `@`s, where an extended email autolink's domain would run into the second `@`, and addresses with
/// one `@` to compare against.
///
/// An address can't span both `@`s, so the run between them is the local part of an address after the first `@`. A
/// period between the two `@`s counts as the period that address's domain needs.
@Suite("Extended email autolink candidate with a second `@`")
struct AutolinkEmailTrailingAtTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    @Test("an email links with a `mailto:` destination", arguments: [
        ("a@b.c", """
            document
              paragraph
                link "mailto:a@b.c" ""
                  text "a@b.c"

            """),
        ("o@e.e", """
            document
              paragraph
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """),
        ("o@e.ex", """
            document
              paragraph
                link "mailto:o@e.ex" ""
                  text "o@e.ex"

            """),
    ])
    func emailLinks(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: Self.options) == tree)
    }

    @Test("`o@e.e `: the email links with no text after it")
    func emailTrailingSpaceLinks() {
        // A paragraph's final spaces are stripped before inline parsing (Paragraphs).
        #expect(TreeDump.dump("o@e.e ", options: Self.options) == """
            document
              paragraph
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    // MARK: - Nothing follows the last `@`

    /// The address after the first `@` has an empty domain.
    @Test("a run ending in `@` is text", arguments: [
        ("o@.e@", """
            document
              paragraph
                text "o@.e@"

            """),
        ("d@.d@", """
            document
              paragraph
                text "d@.d@"

            """),
        ("o@.o@", """
            document
              paragraph
                text "o@.o@"

            """),
        ("a@.d@", """
            document
              paragraph
                text "a@.d@"

            """),
    ])
    func trailingAtIsText(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: Self.options) == tree)
    }

    // MARK: - The address after the first `@`

    @Test("`o@.e@b`: `.e@b` links, using the period of `.e`")
    func addressAfterFirstAtUsesLocalPartPeriod() {
        #expect(TreeDump.dump("o@.e@b", options: Self.options) == """
            document
              paragraph
                text "o@"
                link "mailto:.e@b" ""
                  text ".e@b"

            """)
    }

    @Test("`a@b.c@d`: `b.c@d` links, using the period of `b.c`")
    func addressAfterValidPrefixUsesLocalPartPeriod() {
        #expect(TreeDump.dump("a@b.c@d", options: Self.options) == """
            document
              paragraph
                text "a@"
                link "mailto:b.c@d" ""
                  text "b.c@d"

            """)
    }

    @Test("`a@b@c.d`: `b@c.d` links")
    func addressAfterFirstAtLinks() {
        #expect(TreeDump.dump("a@b@c.d", options: Self.options) == """
            document
              paragraph
                text "a@"
                link "mailto:b@c.d" ""
                  text "b@c.d"

            """)
    }

    @Test("`o@.e@ x@y.z`: the valid email after a text run ending in `@` links")
    func textRunThenValidEmail() {
        #expect(TreeDump.dump("o@.e@ x@y.z", options: Self.options) == """
            document
              paragraph
                text "o@.e@ "
                link "mailto:x@y.z" ""
                  text "x@y.z"

            """)
    }

    @Test("`@e.e`: an `@` with an empty local part is text")
    func emptyLocalPartIsText() {
        #expect(TreeDump.dump("@e.e", options: Self.options) == """
            document
              paragraph
                text "@e.e"

            """)
    }

    // MARK: - Addresses whose domain has no period

    @Test("an address alone whose domain has no period is text", arguments: [
        (".e@b", """
            document
              paragraph
                text ".e@b"

            """),
        ("e@b", """
            document
              paragraph
                text "e@b"

            """),
        ("b.c@d", """
            document
              paragraph
                text "b.c@d"

            """),
        ("b@d", """
            document
              paragraph
                text "b@d"

            """),
    ])
    func domainWithoutPeriodIsText(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: Self.options) == tree)
    }
}
