/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Links may not contain other links (Links), so an email address in link text is not an extended email
/// autolink.
@Suite("Extended email autolinks in link text")
struct AutolinkEmailInLinkTextTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test("an email address inside link text is text")
    func bareEmailInLinkText() {
        #expect(tree("[x B@b.c]()") == """
            document
              paragraph
                link "" ""
                  text "x B@b.c"

            """)
    }

    @Test("an email address in paragraph text autolinks")
    func bareEmailInPlainText() {
        #expect(tree("x B@b.B y") == """
            document
              paragraph
                text "x "
                link "mailto:B@b.B" ""
                  text "B@b.B"
                text " y"

            """)
    }
}
