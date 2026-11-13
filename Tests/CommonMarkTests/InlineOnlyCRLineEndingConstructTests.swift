/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only constructs across a CRLF or a lone CR, each of which is one line ending (Characters and lines).
@Suite("Inline-only constructs across CR line endings")
struct InlineOnlyCRLineEndingConstructTests {

    static let modes: [MarkdownDocument.ParseOptions] = [.inlineOnly, .preserveWhitespace]

    private func tree(_ source: String, _ options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    /// A link label has at most 999 characters (Links), and a CRLF in it is one.
    @Test("a 999-character link label holding a CRLF", arguments: modes)
    func linkLabelLengthCap(_ options: MarkdownDocument.ParseOptions) {
        let a = String(repeating: "a", count: 997)
        #expect(tree("[\(a)\r\nb]: /u\r\n[\(a) b]", options) == """
            document @1:1-3:1002
              paragraph @3:1-3:1002
                link "/u" "" @3:1-3:1002
                  text "\(a) b" @3:2-3:1001

            """)
        #expect(tree("[\(a)\r\nbc]: /u\r\n[\(a) bc]", options) == """
            document @1:1-3:1003
              paragraph @1:1-3:1003
                text "[\(a)\\nbc]: /u\\n[\(a) bc]" @1:1-3:1003

            """)
    }

    /// A link destination in `<` `>` holds no line ending (Links).
    @Test("a pointy link destination across a lone CR and a CRLF", arguments: modes)
    func pointyDestination(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("[d]: <e\r\nf>\r\n[d] [a](<b\rc>)", options) == """
            document @1:1-4:4
              paragraph @1:1-4:4
                text "[d]: " @1:1-1:6
                html_inline "<e\\nf>" @1:6-2:3
                text "\\n[d] [a](" @2:3-3:9
                html_inline "<b\\nc>" @3:9-4:3
                text ")" @4:3-4:4

            """)
    }

    /// A code span's line endings become spaces before one space is stripped from each end (Code spans).
    @Test("code spans across a CRLF and lone CRs", arguments: modes)
    func codeSpans(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("` \r\na ` `\ra\r`", options) == """
            document @1:1-4:2
              paragraph @1:1-4:2
                code " a" @1:1-2:4
                text " " @2:4-2:5
                code "a" @2:5-4:2

            """)
    }

    /// A definition's destination and title may each follow a line ending (Link reference definitions).
    @Test("a definition with CRLFs before its destination and title", arguments: modes)
    func definitionAcrossLines(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("[a]:\r\n/u\r\n\"t\"\r\n[a]", options) == """
            document @1:1-4:4
              paragraph @4:1-4:4
                link "/u" "t" @4:1-4:4
                  text "a" @4:2-4:3

            """)
    }

    /// A character reference to U+000D is a CR in the text, not a line ending.
    @Test("a character reference to a CR before a CRLF", arguments: modes)
    func carriageReturnReference(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("&#13;\r\n[a](/u \"&#13;\r\nb\")", options) == """
            document @1:1-3:4
              paragraph @1:1-3:4
                text "\\u{D}\\n" @1:1-2:1
                link "/u" "\\u{D}\\nb" @2:1-3:4
                  text "a" @2:2-2:3

            """)
    }

    /// An escaped backslash before a line ending forms no hard line break (Backslash escapes, Hard line breaks).
    @Test("an escaped backslash before a CRLF", arguments: modes)
    func escapedBackslash(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("\\\\\r\nb", options) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "\\\\\\nb" @1:1-2:2

            """)
    }

    /// An attribute definition's attributes end at its line ending.
    @Test("an attribute definition before a lone CR, and attributes across a CRLF", arguments: modes)
    func attributes(_ options: MarkdownDocument.ParseOptions) {
        #expect(tree("^[a]: class=x\r^[t][a] ^[u](y\r\nz)", options.union(.attributes)) == """
            document @1:1-3:3
              paragraph @2:1-3:3
                attribute "class=x" @2:1-2:8
                  text "t" @2:3-2:4
                text " " @2:8-2:9
                attribute "y\\nz" @2:9-3:3
                  text "u" @2:11-2:12

            """)
    }
}
