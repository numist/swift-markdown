/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An extended autolink ending in `;` excludes a trailing `&`, one or more ASCII letters and the `;`. Any other
/// character before the `;` leaves the `;` alone excluded.
@Suite("Entity-like tail of an extended autolink")
struct ExtendedAutolinkEntityTailTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func testLetterTailIsExcluded() {
        #expect(surface("www.a.b/x&ab;") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://www.a.b/x" "" @1:1-1:10
                  text "www.a.b/x" @1:1-1:10
                text "&ab;" @1:10-1:14

            """)
    }

    @Test func testLetterThenDigitTailExcludesOnlySemicolon() {
        #expect(surface("www.a.b/x&a1;") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://www.a.b/x&a1" "" @1:1-1:13
                  text "www.a.b/x&a1" @1:1-1:13
                text ";" @1:13-1:14

            """)
    }

    @Test func testDigitOnlyTailExcludesOnlySemicolon() {
        #expect(surface("https://a.b/?q=1&2;") == """
            document @1:1-1:20
              paragraph @1:1-1:20
                link "https://a.b/?q=1&2" "" @1:1-1:19
                  text "https://a.b/?q=1&2" @1:1-1:19
                text ";" @1:19-1:20

            """)
    }

    @Test func testNumberSignTailExcludesOnlySemicolon() {
        #expect(surface("www.a.b/x&#1;") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://www.a.b/x&#1" "" @1:1-1:13
                  text "www.a.b/x&#1" @1:1-1:13
                text ";" @1:13-1:14

            """)
    }
}
