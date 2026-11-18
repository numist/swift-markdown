/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// While a link label is open, its line of only whitespace keeps an underline from forming a heading (Setext headings),
// so each `=` line continues the paragraph and the label until a `]` closes it (Link reference definitions).
@Suite("Setext underlines below an open link label")
struct SetextUnderlineOpenLabelTests {

    private static func unlimitedLabels() -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxLinkLabelCharacters = .max
        return limits
    }

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.sourcePosition], limits: Self.unlimitedLabels(), sourceRanges: true)
    }

    @Test("`=` lines continue a paragraph whose label never closes")
    func labelNeverCloses() {
        #expect(tree("[a\n\u{0B}\n=\n=\n") == """
            document @1:1-5:1
              paragraph @1:1-4:2
                text "[a" @1:1-1:3
                softbreak @-
                text "\\u{B}" @2:1-2:2
                softbreak @-
                text "=" @3:1-3:2
                softbreak @-
                text "=" @4:1-4:2

            """)
    }

    @Test("a `]:` on a later line completes the definition and a later underline forms a heading")
    func labelClosesAfterUnderlines() {
        #expect(tree("[a\n\u{0B}\n=\n=\nb]: /u\nc\n=\n\n[a \u{0B} = = b]\n") == """
            document @1:1-10:1
              heading 1 @6:1-7:2
                text "c" @6:1-6:2
              paragraph @9:1-9:12
                link "/u" "" @9:1-9:12
                  text "a \\u{B} = = b" @9:2-9:11

            """)
    }

    @Test("a `]:` on a later line in a block quote completes the definition")
    func labelClosesAfterUnderlinesInBlockQuote() {
        #expect(tree("> [a\n> \u{0B}\n> =\n> =\n> b]: /u\n> c\n> =\n\n[a \u{0B} = = b]\n") == """
            document @1:1-10:1
              block_quote @1:1-7:4
                heading 1 @6:3-7:4
                  text "c" @6:3-6:4
              paragraph @9:1-9:12
                link "/u" "" @9:1-9:12
                  text "a \\u{B} = = b" @9:2-9:11

            """)
    }

    @Test("a `]:` on a later line in a block quote after a paragraph beginning with `[` completes the definition")
    func labelClosesAfterUnderlinesInBlockQuoteAfterParagraph() {
        #expect(tree("[x]\n\n> [a\n> \u{0B}\n> =\n> b]: /u\n> c\n> =\n") == """
            document @1:1-9:1
              paragraph @1:1-1:4
                text "[x]" @1:1-1:4
              block_quote @3:1-8:4
                heading 1 @7:3-8:4
                  text "c" @7:3-7:4

            """)
    }

    @Test("an escaped backslash before `]` leaves the `]` to close the label")
    func escapedBackslashBeforeBracket() {
        #expect(tree("[a\n\u{0B}\n=\nb\\\\]: /u\nc\n=\n\n[a \u{0B} = b\\\\]\n") == """
            document @1:1-9:1
              heading 1 @5:1-6:2
                text "c" @5:1-5:2
              paragraph @8:1-8:12
                link "/u" "" @8:1-8:12
                  text "a \\u{B} = b\\\\" @8:2-8:11

            """)
    }

    @Test("an escaped `]` leaves the label open for a later `]`")
    func escapedBracket() {
        #expect(tree("[a\n\u{0B}\n=\nb\\]\n=\n]: /u\nc\n=\n\n[a \u{0B} = b\\] =]\n") == """
            document @1:1-11:1
              heading 1 @7:1-8:2
                text "c" @7:1-7:2
              paragraph @10:1-10:14
                link "/u" "" @10:1-10:14
                  text "a \\u{B} = b] =" @10:2-10:13

            """)
    }

    @Test("a `]` after a line ending in a backslash closes the label")
    func bracketAfterBackslashAtLineEnd() {
        #expect(tree("[a\n\u{0B}\n=\nb\\\n]: /u\nc\n=\n") == """
            document @1:1-8:1
              heading 1 @6:1-7:2
                text "c" @6:1-6:2

            """)
    }

    @Test("a `]` after a line ending in a backslash closes the label in a block quote")
    func bracketAfterBackslashAtLineEndInBlockQuote() {
        #expect(tree("> [a\n> \u{0B}\n> =\n> b\\\n> ]: /u\n> c\n> =\n") == """
            document @1:1-8:1
              block_quote @1:1-7:4
                heading 1 @6:3-7:4
                  text "c" @6:3-6:4

            """)
    }

    @Test("an unescaped `[` on a later line keeps the label from closing")
    func bracketOpenerAfterUnderline() {
        #expect(tree("[a\n\u{0B}\n=\nb[\n=\n]: /u\n=\n") == """
            document @1:1-8:1
              paragraph @1:1-7:2
                text "[a" @1:1-1:3
                softbreak @-
                text "\\u{B}" @2:1-2:2
                softbreak @-
                text "=" @3:1-3:2
                softbreak @-
                text "b[" @4:1-4:3
                softbreak @-
                text "=" @5:1-5:2
                softbreak @-
                text "]: /u" @6:1-6:6
                softbreak @-
                text "=" @7:1-7:2

            """)
    }

    @Test("an unescaped `[` on a later line in a block quote keeps the label from closing")
    func bracketOpenerAfterUnderlineInBlockQuote() {
        #expect(tree("> [a\n> \u{0B}\n> =\n> b[\n> =\n> ]: /u\n> =\n") == """
            document @1:1-8:1
              block_quote @1:1-7:4
                paragraph @1:3-7:4
                  text "[a" @1:3-1:5
                  softbreak @-
                  text "\\u{B}" @2:3-2:4
                  softbreak @-
                  text "=" @3:3-3:4
                  softbreak @-
                  text "b[" @4:3-4:5
                  softbreak @-
                  text "=" @5:3-5:4
                  softbreak @-
                  text "]: /u" @6:3-6:8
                  softbreak @-
                  text "=" @7:3-7:4

            """)
    }

    @Test("an escaped `[` leaves the label open for a later `]`")
    func escapedBracketOpener() {
        #expect(tree("[a\n\u{0B}\n=\nb\\[\n=\n]: /u\nc\n=\n\n[a \u{0B} = b\\[ =]\n") == """
            document @1:1-11:1
              heading 1 @7:1-8:2
                text "c" @7:1-7:2
              paragraph @10:1-10:14
                link "/u" "" @10:1-10:14
                  text "a \\u{B} = b[ =" @10:2-10:13

            """)
    }

    @Test("a `[` after the `]` that closes the label is part of the destination")
    func bracketOpenerAfterCloser() {
        #expect(tree("[a\n\u{0B}\n=\nb]: /u[\nc\n=\n\n[a \u{0B} = b]\n") == """
            document @1:1-9:1
              heading 1 @5:1-6:2
                text "c" @5:1-5:2
              paragraph @8:1-8:10
                link "/u[" "" @8:1-8:10
                  text "a \\u{B} = b" @8:2-8:9

            """)
    }
}
