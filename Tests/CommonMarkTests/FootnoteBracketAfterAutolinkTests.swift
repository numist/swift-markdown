/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A footnote-shaped bracket that opens on the line after an extended autolink ending in a backslash and closes on a
/// later line. With no matching definition it is literal text, split at the line ending. The autolink includes its
/// trailing backslashes (Autolinks (extension)), and a NUL in the bracket is replaced by U+FFFD.
@Suite("Cross-line footnote-shaped bracket after an extended autolink")
struct FootnoteBracketAfterAutolinkTests {

    static let options: MarkdownDocument.ParseOptions = [.footnotes, .gfmAutolink, .sourcePosition]

    @Test("a www autolink ending in a backslash")
    func wwwAutolinkEndingInBackslash() {
        #expect(TreeDump.dump("www.\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                link "http://www.\\\\" "" @1:1-1:6
                  text "www.\\\\" @1:1-1:6
                softbreak @-
                text "[^" @2:1-2:3
                softbreak @-
                text "\u{FFFD}]" @3:1-3:3

            """)
    }

    @Test("a scheme autolink ending in a backslash")
    func schemeAutolinkEndingInBackslash() {
        #expect(TreeDump.dump("http://a.b\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                link "http://a.b\\\\" "" @1:1-1:12
                  text "http://a.b\\\\" @1:1-1:12
                softbreak @-
                text "[^" @2:1-2:3
                softbreak @-
                text "\u{FFFD}]" @3:1-3:3

            """)
    }

    @Test("a www autolink ending in a run of backslashes")
    func wwwAutolinkEndingInBackslashRun() {
        #expect(TreeDump.dump("www.a.b\\\\\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                link "http://www.a.b\\\\\\\\\\\\" "" @1:1-1:11
                  text "www.a.b\\\\\\\\\\\\" @1:1-1:11
                softbreak @-
                text "[^" @2:1-2:3
                softbreak @-
                text "\u{FFFD}]" @3:1-3:3

            """)
    }

    @Test("a bracket continuing onto a line of a multi-byte character")
    func multiByteContinuation() {
        #expect(TreeDump.dump("www.\\\n[^\n\u{1F600}]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:6
              paragraph @1:1-3:6
                link "http://www.\\\\" "" @1:1-1:6
                  text "www.\\\\" @1:1-1:6
                softbreak @-
                text "[^" @2:1-2:3
                softbreak @-
                text "\u{1F600}]" @3:1-3:6

            """)
    }

    @Test("a bracket continuing onto a line of one byte")
    func oneByteContinuation() {
        #expect(TreeDump.dump("www.\\\n[^\nx]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                link "http://www.\\\\" "" @1:1-1:6
                  text "www.\\\\" @1:1-1:6
                softbreak @-
                text "[^" @2:1-2:3
                softbreak @-
                text "x]" @3:1-3:3

            """)
    }
}
