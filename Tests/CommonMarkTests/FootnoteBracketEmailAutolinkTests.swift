/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("`[^[` footnote-shaped bracket next to an email autolink")
struct FootnoteBracketEmailAutolinkTests {

    private static let options: MarkdownDocument.ParseOptions = [.footnotes, .gfmAutolink, .attributes]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test("`[^[]]f@f.f` keeps the bracket literal and autolinks the email after `]`")
    func bracketThenEmail() {
        #expect(tree("[^[]]f@f.f") == """
            document
              paragraph
                text "[^[]]"
                link "mailto:f@f.f" ""
                  text "f@f.f"

            """)
    }

    @Test("`[^[]]*f@f.f` keeps the bracket literal and autolinks the email")
    func bracketThenDelimiterThenEmail() {
        #expect(tree("[^[]]*f@f.f") == """
            document
              paragraph
                text "[^[]]*"
                link "mailto:f@f.f" ""
                  text "f@f.f"

            """)
    }

    @Test("`x[^[]]y` is literal text")
    func plainTrailingTextKept() {
        #expect(tree("x[^[]]y") == """
            document
              paragraph
                text "x[^[]]y"

            """)
    }

    @Test("`f@f.f[^[]]y` autolinks the leading email and keeps the rest literal")
    func emailBeforeBracketKeepsTrailingText() {
        #expect(tree("f@f.f[^[]]y") == """
            document
              paragraph
                link "mailto:f@f.f" ""
                  text "f@f.f"
                text "[^[]]y"

            """)
    }
}
