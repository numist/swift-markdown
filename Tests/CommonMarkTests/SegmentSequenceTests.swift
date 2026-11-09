/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Segment Sequence Tests")
struct SegmentsTests {

    @Test("the segments of inline text and code concatenate to the literal")
    func inlineTextMatches() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("hello *world* and `code`") == """
            document
              paragraph
                text "hello " ["hello "]
                emph
                  text "world" ["world"]
                text " and " [" and "]
                code "code" ["code"]

            """)
    }

    @Test("the segments of each line's text in a multi-line paragraph concatenate to its literal")
    func multiLineParagraph() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("first line\nsecond line\nthird line") == """
            document
              paragraph
                text "first line" ["first line"]
                softbreak
                text "second line" ["second line"]
                softbreak
                text "third line" ["third line"]

            """)
    }

    @Test("the segments of a fenced code block body concatenate to the body")
    func codeBlockBody() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\nline one\nline two\n```") == """
            document
              code_block "" "line one\\nline two\\n" ["line one", "\\n", "line two", "\\n"]

            """)
    }

    @Test("a document and a paragraph have no textual content")
    func emptyForNonLiteral() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("text") == """
            document
              paragraph
                text "text" ["text"]

            """)
    }
}
