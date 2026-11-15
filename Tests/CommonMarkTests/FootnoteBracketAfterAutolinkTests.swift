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
/// later line. With no matching definition it is literal text, split at the line ending. With a matching definition it
/// is a footnote reference spanning the line ending. The autolink includes its trailing backslashes (Autolinks
/// (extension)), and a NUL in the bracket is replaced by U+FFFD.
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

    @Test("a www autolink ending in a backslash, with a definition")
    func wwwAutolinkEndingInBackslashWithDefinition() {
        #expect(TreeDump.dump("[^\u{0}]: d\n\nwww.\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-5:3
              paragraph @3:1-5:3
                link "http://www.\\\\" "" @3:1-3:6
                  text "www.\\\\" @3:1-3:6
                softbreak @-
                footnote_reference "1" @4:1-5:3
              footnote_definition "\u{FFFD}" @1:1-1:8
                paragraph @1:7-1:8
                  text "d" @1:7-1:8

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

    @Test("a scheme autolink ending in a backslash, with a definition")
    func schemeAutolinkEndingInBackslashWithDefinition() {
        #expect(TreeDump.dump("[^\u{0}]: d\n\nhttp://a.b\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-5:3
              paragraph @3:1-5:3
                link "http://a.b\\\\" "" @3:1-3:12
                  text "http://a.b\\\\" @3:1-3:12
                softbreak @-
                footnote_reference "1" @4:1-5:3
              footnote_definition "\u{FFFD}" @1:1-1:8
                paragraph @1:7-1:8
                  text "d" @1:7-1:8

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

    @Test("a www autolink ending in a run of backslashes, with a definition")
    func wwwAutolinkEndingInBackslashRunWithDefinition() {
        #expect(TreeDump.dump("[^\u{0}]: d\n\nwww.a.b\\\\\\\n[^\n\u{0}]", options: Self.options, sourceRanges: true) == """
            document @1:1-5:3
              paragraph @3:1-5:3
                link "http://www.a.b\\\\\\\\\\\\" "" @3:1-3:11
                  text "www.a.b\\\\\\\\\\\\" @3:1-3:11
                softbreak @-
                footnote_reference "1" @4:1-5:3
              footnote_definition "\u{FFFD}" @1:1-1:8
                paragraph @1:7-1:8
                  text "d" @1:7-1:8

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

    @Test("a bracket continuing onto a line of a multi-byte character, with a definition")
    func multiByteContinuationWithDefinition() {
        #expect(TreeDump.dump("[^\u{1F600}]: d\n\nwww.\\\n[^\n\u{1F600}]", options: Self.options, sourceRanges: true) == """
            document @1:1-5:6
              paragraph @3:1-5:6
                link "http://www.\\\\" "" @3:1-3:6
                  text "www.\\\\" @3:1-3:6
                softbreak @-
                footnote_reference "1" @4:1-5:6
              footnote_definition "\u{1F600}" @1:1-1:11
                paragraph @1:10-1:11
                  text "d" @1:10-1:11

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

    @Test("a bracket continuing onto a line of one byte, with a definition")
    func oneByteContinuationWithDefinition() {
        #expect(TreeDump.dump("[^x]: d\n\nwww.\\\n[^\nx]", options: Self.options, sourceRanges: true) == """
            document @1:1-5:3
              paragraph @3:1-5:3
                link "http://www.\\\\" "" @3:1-3:6
                  text "www.\\\\" @3:1-3:6
                softbreak @-
                footnote_reference "1" @4:1-5:3
              footnote_definition "x" @1:1-1:8
                paragraph @1:7-1:8
                  text "d" @1:7-1:8

            """)
    }
}
