/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A single-quoted link title (Links) holds a `'` only when it is backslash-escaped. The spec does not say whether a
/// `\` before the last `'` that could close the title escapes it. It escapes that quote only when a later quote can
/// close the title; otherwise the `\` is a literal backslash and that quote closes the title.
@Suite("Link title backslash longest match")
struct LinkTitleBackslashLongestMatchTests {

    /// The destination ends at the line ending, which then separates it from the title `'\'`.
    @Test("empty-text link whose title backslash precedes the closing quote")
    func backslashBeforeCloseQuote() {
        #expect(TreeDump.dump("[](a\n'\\')", options: []) == """
            document
              paragraph
                link "a" "\\\\"

            """)
    }

    /// A later quote can close the title, so the `\'` is a backslash escape.
    @Test("escaped closing quote extends the title to a later quote")
    func escapedCloseQuoteExtendsTitle() {
        #expect(TreeDump.dump("[](a '\\'')", options: []) == """
            document
              paragraph
                link "a" "'"

            """)
    }

    /// No later quote can close the title, so the `\` is a literal backslash.
    @Test("a backslash before the only closing quote is literal")
    func backslashBeforeOnlyCloseQuote() {
        #expect(TreeDump.dump("[](a '\\')", options: []) == """
            document
              paragraph
                link "a" "\\\\"

            """)
    }
}
