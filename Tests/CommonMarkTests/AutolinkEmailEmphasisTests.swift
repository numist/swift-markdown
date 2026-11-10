/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Extended email autolinks (Autolinks (extension)) are recognized in text after emphasis is resolved, so a `_`
/// that delimits no emphasis may be part of an address's local part.
@Suite("Extended email autolinks next to emphasis delimiters")
struct AutolinkEmailEmphasisTests {

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [.gfmAutolink])
    }

    // MARK: - A `_` outside emphasis joins the local part

    @Test("`_@b.c`: the flanking `_` is the local part, not text before the link")
    func leadingUnderscore() {
        #expect(tree("_@b.c") == """
            document
              paragraph
                link "mailto:_@b.c" ""
                  text "_@b.c"

            """)
    }

    @Test("`a_@b.c`: local part is `a_`, whole thing links")
    func wordThenUnderscore() {
        #expect(tree("a_@b.c") == """
            document
              paragraph
                link "mailto:a_@b.c" ""
                  text "a_@b.c"

            """)
    }

    @Test("`x _@b.c`: the space bounds the local part; `x ` is text before the link")
    func spaceThenUnderscore() {
        #expect(tree("x _@b.c") == """
            document
              paragraph
                text "x "
                link "mailto:_@b.c" ""
                  text "_@b.c"

            """)
    }

    // MARK: - An email inside a resolved emphasis run

    @Test("`_a@b.c_`: the email autolinks inside the emphasis")
    func emailInsideEmphasis() {
        #expect(tree("_a@b.c_") == """
            document
              paragraph
                emph
                  link "mailto:a@b.c" ""
                    text "a@b.c"

            """)
    }

    // MARK: - Emphasis consumes the delimiters, leaving an empty local part

    @Test("`_a_@b.c`: emphasis consumes both `_`, so `@b.c` has no local part and is text")
    func emphasisConsumesUnderscores() {
        #expect(tree("_a_@b.c") == """
            document
              paragraph
                emph
                  text "a"
                text "@b.c"

            """)
    }

    // MARK: - Several addresses in one text node

    @Test("`a@b.c x@y.z`: both emails link, with the ` ` between them")
    func twoEmailsInOneRun() {
        #expect(tree("a@b.c x@y.z") == """
            document
              paragraph
                link "mailto:a@b.c" ""
                  text "a@b.c"
                text " "
                link "mailto:x@y.z" ""
                  text "x@y.z"

            """)
    }
}
