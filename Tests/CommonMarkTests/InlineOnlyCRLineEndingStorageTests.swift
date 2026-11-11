/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Storage for inline-only content whose lines end in a CRLF or a lone CR.
///
/// Every line ending is `\n` in the content. The content is parsed in place, and only what differs from the source is
/// copied into the materialized string buffer: a text node, raw HTML or a link title that holds a CRLF or a lone CR,
/// with each line ending as `\n`, and a code span's line endings as spaces (Code spans). Content holding a NUL is copied
/// whole, with each NUL replaced by U+FFFD (Insecure characters). The buffer also holds the line ending that joins
/// lines.
@Suite("Inline-only content with CR line endings is copied only where a literal holds one")
struct InlineOnlyCRLineEndingStorageTests {

    static let modes: [MarkdownDocument.ParseOptions] = [
        .inlineOnly,
        [.inlineOnly, .sourcePosition],
        .preserveWhitespace,
        MarkdownDocument.ParseOptions.preserveWhitespace.union(.sourcePosition),
    ]

    private func materializedSize(_ source: String, _ options: MarkdownDocument.ParseOptions) -> Int {
        MarkdownDocument.withParsedDocument(source, options: options) { $0._materializedStringSize }
    }

    private func tree(_ source: String, _ options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    private func segments(_ source: String, _ options: MarkdownDocument.ParseOptions) -> String? {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return nil }
        return TreeDump.dumpSegments(source, options: options)
    }

    @Test("CRLF line endings", arguments: modes)
    func crlf(_ options: MarkdownDocument.ParseOptions) {
        let source = "Some *text,\r\nmore* text\r\n"
        // "text,\nmore" and " text\n"
        #expect(materializedSize(source, options) == 1 + 10 + 6)
        #expect(tree(source, options) == """
            document @1:1-3:1
              paragraph @1:1-2:11
                text "Some " @1:1-1:6
                emph @1:6-2:6
                  text "text,\\nmore" @1:7-2:5
                text " text\\n" @2:6-2:11

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "Some " ["Some "]
                    emph
                      text "text,\\nmore" ["text,\\nmore"]
                    text " text\\n" [" text\\n"]

                """)
        }
    }

    @Test("lone CR line endings", arguments: modes)
    func loneCR(_ options: MarkdownDocument.ParseOptions) {
        let source = "a\r\r*b*\rc\r"
        // "a\n\n" and "\nc\n"
        #expect(materializedSize(source, options) == 1 + 3 + 3)
        #expect(tree(source, options) == """
            document @1:1-5:1
              paragraph @1:1-4:2
                text "a\\n\\n" @1:1-3:1
                emph @3:1-3:4
                  text "b" @3:2-3:3
                text "\\nc\\n" @3:4-4:2

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "a\\n\\n" ["a\\n\\n"]
                    emph
                      text "b" ["b"]
                    text "\\nc\\n" ["\\nc\\n"]

                """)
        }
    }

    @Test("mixed line endings", arguments: modes)
    func mixed(_ options: MarkdownDocument.ParseOptions) {
        let source = "a\r\nb\rc\nd\r\n\re"
        // "a\nb\nc\nd\n\ne"
        #expect(materializedSize(source, options) == 1 + 10)
        #expect(tree(source, options) == """
            document @1:1-6:2
              paragraph @1:1-6:2
                text "a\\nb\\nc\\nd\\n\\ne" @1:1-6:2

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "a\\nb\\nc\\nd\\n\\ne" ["a\\nb\\nc\\nd\\n\\ne"]

                """)
        }
    }

    @Test("hard line breaks before a CRLF and a lone CR", arguments: modes)
    func hardLineBreaks(_ options: MarkdownDocument.ParseOptions) {
        let source = "a\\\r\nb\\\rc"
        #expect(materializedSize(source, options) == 1)
        #expect(tree(source, options) == """
            document @1:1-3:2
              paragraph @1:1-3:2
                text "a" @1:1-1:2
                linebreak @-
                text "b" @2:1-2:2
                linebreak @-
                text "c" @3:1-3:2

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "a" ["a"]
                    linebreak
                    text "b" ["b"]
                    linebreak
                    text "c" ["c"]

                """)
        }
    }

    @Test("a definition whose title spans a CRLF", arguments: modes)
    func definitionTitleAcrossCRLF(_ options: MarkdownDocument.ParseOptions) {
        let source = "[a]: /u \"t\r\nu\"\r\n[a]\r\n"
        // "t\nu" and "\n"
        #expect(materializedSize(source, options) == 1 + 3 + 1)
        #expect(tree(source, options) == """
            document @1:1-4:1
              paragraph @3:1-3:4
                link "/u" "t\\nu" @3:1-3:4
                  text "a" @3:2-3:3
                text "\\n" @3:4-3:4

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    link "/u" "t\\nu"
                      text "a" ["a"]
                    text "\\n" ["\\n"]

                """)
        }
    }

    @Test("content after a definition starting at a lone CR", arguments: modes)
    func contentStartingAtLoneCR(_ options: MarkdownDocument.ParseOptions) {
        let source = "[a]: /u\r\r[a]"
        // "\n"
        #expect(materializedSize(source, options) == 1 + 1)
        #expect(tree(source, options) == """
            document @1:1-3:4
              paragraph @2:1-3:4
                text "\\n" @2:1-3:1
                link "/u" "" @3:1-3:4
                  text "a" @3:2-3:3

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "\\n" ["\\n"]
                    link "/u" ""
                      text "a" ["a"]

                """)
        }
    }

    @Test("a code span and raw HTML across line endings", arguments: modes)
    func codeSpanAndRawHTML(_ options: MarkdownDocument.ParseOptions) {
        let source = "`c\r\nd` <b\rc>"
        // "c d" and "<b\nc>"
        #expect(materializedSize(source, options) == 1 + 3 + 5)
        #expect(tree(source, options) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                code "c d" @1:1-2:3
                text " " @2:3-2:4
                html_inline "<b\\nc>" @2:4-3:3

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    code "c d" ["c d"]
                    text " " [" "]
                    html_inline "<b\\nc>" ["<b\\nc>"]

                """)
        }
    }

    @Test("email autolinks in text across line endings", arguments: modes)
    func emailAutolinks(_ options: MarkdownDocument.ParseOptions) {
        let options = options.union(.gfmAutolink)
        let source = "x a@b.c\r\nd\re@f.g"
        // "mailto:a@b.c", "mailto:e@f.g" and "\nd\n"
        #expect(materializedSize(source, options) == 1 + 12 + 12 + 3)
        #expect(tree(source, options) == """
            document @1:1-3:6
              paragraph @1:1-3:6
                text "x " @1:1-1:3
                link "mailto:a@b.c" "" @1:3-1:8
                  text "a@b.c" @1:3-1:8
                text "\\nd\\n" @1:8-3:1
                link "mailto:e@f.g" "" @3:1-3:6
                  text "e@f.g" @3:1-3:6

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "x " ["x "]
                    link "mailto:a@b.c" ""
                      text "a@b.c" ["a@b.c"]
                    text "\\nd\\n" ["\\nd\\n"]
                    link "mailto:e@f.g" ""
                      text "e@f.g" ["e@f.g"]

                """)
        }
    }

    @Test("content holding a NUL", arguments: modes)
    func nul(_ options: MarkdownDocument.ParseOptions) {
        let source = "a\u{0}\r\nb\rc"
        // "a\u{FFFD}\nb\nc"
        #expect(materializedSize(source, options) == 1 + 8)
        #expect(tree(source, options) == """
            document @1:1-3:2
              paragraph @1:1-3:2
                text "a\u{FFFD}\\nb\\nc" @1:1-3:2

            """)
        if let segments = segments(source, options) {
            #expect(segments == """
                document
                  paragraph
                    text "a\u{FFFD}\\nb\\nc" ["a\u{FFFD}\\nb\\nc"]

                """)
        }
    }

    @Test("long CRLF lines in one text node", arguments: modes)
    func longLines(_ options: MarkdownDocument.ParseOptions) {
        let source = String(repeating: "word ", count: 2000) + "\r\n" + String(repeating: "more ", count: 2000)
        #expect(materializedSize(source, options) == 1 + 10_000 + 1 + 10_000)
    }
}
