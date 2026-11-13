/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Extended email autolinks are recognized left to right. When a candidate address is rejected, the next address's
/// local part starts no earlier than the character that ended the candidate's domain: `+`, or a `.` not followed by
/// an alphanumeric, ends a domain, while `-`, `_`, alphanumerics and a `.` followed by an alphanumeric continue it.
/// A second `@` in a domain restarts the address just past the first `@`.
@Suite("Extended email autolink local part after a rejected candidate")
struct ExtendedEmailAutolinkAfterRejectedCandidateTests {

    // MARK: - `+` ends a domain

    @Test("`l@o+@b.b`: the `+` bounds the second local part")
    func plusBoundsLocalPart() {
        // `l@o` is rejected (its domain has no period), and its domain ends at `+`.
        #expect(TreeDump.dump("l@o+@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@o"
                link "mailto:+@b.b" ""
                  text "+@b.b"

            """)
    }

    @Test("`l@oo+@b.b`: the `+` bounds the second local part")
    func plusBoundsLocalPartTwoChars() {
        #expect(TreeDump.dump("l@oo+@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@oo"
                link "mailto:+@b.b" ""
                  text "+@b.b"

            """)
    }

    @Test("`a@b+c@d.d`: the `+` bounds the second local part to `+c`")
    func plusBoundsLocalPartWithTrailingAlnum() {
        #expect(TreeDump.dump("a@b+c@d.d", options: .gfmAutolink) == """
            document
              paragraph
                text "a@b"
                link "mailto:+c@d.d" ""
                  text "+c@d.d"

            """)
    }

    @Test("`a@b_+c@d.e`: the `+` bounds the second local part to `+c`")
    func plusBoundsLocalPartAfterUnderscore() {
        #expect(TreeDump.dump("a@b_+c@d.e", options: .gfmAutolink) == """
            document
              paragraph
                text "a@b_"
                link "mailto:+c@d.e" ""
                  text "+c@d.e"

            """)
    }

    @Test("`l@+@b.b`: the local part after the rejected `l@` is `+`")
    func plusAtStart() {
        #expect(TreeDump.dump("l@+@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@"
                link "mailto:+@b.b" ""
                  text "+@b.b"

            """)
    }

    // MARK: - `.`, `-`, `_` and alphanumerics continue a domain

    @Test("`l@o.p@b.b`: the second `@` restarts the address at `o.p`")
    func dotContinuesDomain() {
        #expect(TreeDump.dump("l@o.p@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@"
                link "mailto:o.p@b.b" ""
                  text "o.p@b.b"

            """)
    }

    @Test("`l@o-p@b.b`: the second `@` restarts the address at `o-p`")
    func hyphenContinuesDomain() {
        #expect(TreeDump.dump("l@o-p@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@"
                link "mailto:o-p@b.b" ""
                  text "o-p@b.b"

            """)
    }

    @Test("`l@o_p@b.b`: the second `@` restarts the address at `o_p`")
    func underscoreContinuesDomain() {
        #expect(TreeDump.dump("l@o_p@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@"
                link "mailto:o_p@b.b" ""
                  text "o_p@b.b"

            """)
    }

    @Test("`l@abc@b.b`: the second `@` restarts the address at `abc`")
    func alnumContinuesDomain() {
        #expect(TreeDump.dump("l@abc@b.b", options: .gfmAutolink) == """
            document
              paragraph
                text "l@"
                link "mailto:abc@b.b" ""
                  text "abc@b.b"

            """)
    }

    @Test("`xy@ab@c.c`: the second `@` restarts the address at `ab`")
    func alnumFirstLocalPart() {
        #expect(TreeDump.dump("xy@ab@c.c", options: .gfmAutolink) == """
            document
              paragraph
                text "xy@"
                link "mailto:ab@c.c" ""
                  text "ab@c.c"

            """)
    }

    // MARK: - A `.` not followed by an alphanumeric ends a domain

    @Test("`a@b.+@c.c`: the local part after the rejected `a@b` is `.+`")
    func dotThenPlusBoundary() {
        #expect(TreeDump.dump("a@b.+@c.c", options: .gfmAutolink) == """
            document
              paragraph
                text "a@b"
                link "mailto:.+@c.c" ""
                  text ".+@c.c"

            """)
    }

    @Test("`a@b_.+@c.c`: the local part after the rejected `a@b_` is `.+`")
    func dotThenPlusBoundaryAfterUnderscore() {
        #expect(TreeDump.dump("a@b_.+@c.c", options: .gfmAutolink) == """
            document
              paragraph
                text "a@b_"
                link "mailto:.+@c.c" ""
                  text ".+@c.c"

            """)
    }

    @Test("`a@b..c@d.d`: the local part after the rejected `a@b` is `..c`")
    func doubledDotBoundary() {
        #expect(TreeDump.dump("a@b..c@d.d", options: .gfmAutolink) == """
            document
              paragraph
                text "a@b"
                link "mailto:..c@d.d" ""
                  text "..c@d.d"

            """)
    }
}
