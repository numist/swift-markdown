/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// With `.strikethrough`, a run of one or two tildes delimits strikethrough and closes only an opener of the same
/// length. A run of three or more tildes is literal text, whatever its length.
@Suite("Strikethrough delimiter run length")
struct StrikethroughDelimiterRunLengthTests {

    private static let longRun = String(repeating: "~", count: 10_000)

    // The opener is followed by the punctuation `)`, so the `**` before it, also punctuation, makes it left-flanking.

    @Test("one- and two-tilde runs pair with a run of the same length; three-tilde runs stay literal", arguments: [
        ("~x~", """
            document
              paragraph
                strikethrough
                  text "x"

            """),
        ("~~x~~", """
            document
              paragraph
                strikethrough
                  text "x"

            """),
        ("a ~~~x~~~", """
            document
              paragraph
                text "a ~~~x~~~"

            """),
        ("**~)~", """
            document
              paragraph
                text "**"
                strikethrough
                  text ")"

            """),
        ("**~~)~~", """
            document
              paragraph
                text "**"
                strikethrough
                  text ")"

            """),
    ])
    func shortRuns(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: .strikethrough) == tree)
    }

    @Test("a run of three or more tildes inside one- or two-tilde strikethrough stays literal", arguments: [
        ("**~)~~~)~", """
            document
              paragraph
                text "**"
                strikethrough
                  text ")~~~)"

            """),
        ("**~~)~~~)~~", """
            document
              paragraph
                text "**"
                strikethrough
                  text ")~~~)"

            """),
    ])
    func shortOpenerBeforeLongRun(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: .strikethrough) == tree)
    }

    @Test("a run of ten thousand tildes inside one-tilde strikethrough stays literal")
    func shortOpenerBeforeVeryLongRun() {
        #expect(TreeDump.dump("**~)" + Self.longRun + ")~", options: .strikethrough) == """
            document
              paragraph
                text "**"
                strikethrough
                  text ")\(Self.longRun))"

            """)
    }

    @Test("an opener of three or more tildes stays literal")
    func longOpenerStaysLiteral() {
        #expect(TreeDump.dump("**~~~)~~~", options: .strikethrough) == """
            document
              paragraph
                text "**~~~)~~~"

            """)
        #expect(TreeDump.dump("**" + Self.longRun + ")" + Self.longRun, options: .strikethrough) == """
            document
              paragraph
                text "**\(Self.longRun))\(Self.longRun)"

            """)
    }

    /// With `.strikethroughDoubleTilde`, only a two-tilde run delimits strikethrough.
    @Test("with double-tilde strikethrough, only a two-tilde run closes a two-tilde opener", arguments: [
        ("**~~)~~", """
            document
              paragraph
                text "**"
                strikethrough
                  text ")"

            """),
        ("**~)~", """
            document
              paragraph
                text "**~)~"

            """),
        ("**~~)~~~", """
            document
              paragraph
                text "**~~)~~~"

            """),
    ])
    func doubleTildeRuns(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: [.strikethrough, .strikethroughDoubleTilde]) == tree)
    }
}
