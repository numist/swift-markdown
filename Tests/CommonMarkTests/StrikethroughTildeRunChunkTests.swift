/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `strikethroughTildeRunChunk` splits a run of `~` from its start into chunks of that length and a shorter
/// remainder. Each chunk is classified on its own, from the characters before and after it: a flanking chunk of one or
/// two tildes is a strikethrough delimiter, and a longer chunk is literal text.
@Suite("Strikethrough tilde run chunk")
struct StrikethroughTildeRunChunkTests {

    private func limits(_ chunk: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.strikethroughTildeRunChunk = chunk
        return limits
    }

    @Test("a run one tilde longer than the chunk ends in a one-tilde closer")
    func boundary() {
        #expect(TreeDump.dump("~a~~~", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                text "~a~~~"

            """)
        #expect(TreeDump.dump("~a~~~~", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                strikethrough
                  text "a~~~"

            """)
    }

    @Test("a run two tildes longer than the chunk ends in a two-tilde closer")
    func twoTildeRemainder() {
        #expect(TreeDump.dump("~~a~~~~~", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                strikethrough
                  text "a~~~"

            """)
    }

    @Test("the default limits parse a run of three or more tildes as one literal run")
    func defaultLimits() {
        #expect(TreeDump.dump("~a~~~~", options: .strikethrough) == """
            document
              paragraph
                text "~a~~~~"

            """)
        #expect(TreeDump.dump("a ~~~~~b~~", options: .strikethrough) == """
            document
              paragraph
                text "a ~~~~~b~~"

            """)
    }

    @Test("a chunk after the first is flanking from the tilde before it and the character after it")
    func laterChunkOpens() {
        #expect(TreeDump.dump("a ~~~~~b~~", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                text "a ~~~"
                strikethrough
                  text "b"

            """)
    }

    @Test("a chunk before the last is flanking from the character before it and the tilde after it")
    func earlierChunkOpens() {
        #expect(TreeDump.dump("x ~~~a~", options: .strikethrough, limits: limits(2)) == """
            document
              paragraph
                text "x ~~"
                strikethrough
                  text "a"

            """)
        #expect(TreeDump.dump("~~a~~", options: .strikethrough, limits: limits(1)) == """
            document
              paragraph
                strikethrough
                  strikethrough
                    text "a"

            """)
    }

    @Test("a closing chunk is flanking from the character after the run, multibyte included")
    func multibyteNeighbour() {
        #expect(TreeDump.dump("~a~~~~。", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                strikethrough
                  text "a~~~"
                text "。"

            """)
        #expect(TreeDump.dump("~a~~~~é", options: .strikethrough, limits: limits(3)) == """
            document
              paragraph
                text "~a~~~~é"

            """)
    }

    @Test("a chunk pairs only with an opener of the same length")
    func equalLengthPairing() {
        #expect(TreeDump.dump("~~a~~~", options: .strikethrough, limits: limits(2)) == """
            document
              paragraph
                strikethrough
                  text "a"
                text "~"

            """)
        #expect(TreeDump.dump("~a~~~", options: .strikethrough, limits: limits(2)) == """
            document
              paragraph
                text "~a~~~"

            """)
    }

    @Test("with double-tilde strikethrough, one-tilde chunks stay literal")
    func doubleTilde() {
        #expect(TreeDump.dump("~~a~~", options: [.strikethrough, .strikethroughDoubleTilde], limits: limits(1)) == """
            document
              paragraph
                text "~~a~~"

            """)
    }

    @Test("a chunk of 0 or below splits a run into single tildes", arguments: [0, -1, Int.min])
    func nonPositiveChunk(_ chunk: Int) {
        #expect(TreeDump.dump("~~a~~", options: .strikethrough, limits: limits(chunk)) == """
            document
              paragraph
                strikethrough
                  strikethrough
                    text "a"

            """)
    }

    @Test("a strikethrough closed by a chunk covers that chunk and not the literal chunk before it")
    func sourceRanges() {
        let tree = TreeDump.dump(
            "a ~~~~~b~~ ~c~~~~", options: [.strikethrough, .sourcePosition], limits: limits(3), sourceRanges: true)
        #expect(tree == """
            document @1:1-1:18
              paragraph @1:1-1:18
                text "a ~~~" @1:1-1:6
                strikethrough @1:6-1:11
                  text "b" @1:8-1:9
                text " " @1:11-1:12
                strikethrough @1:12-1:18
                  text "c~~~" @1:13-1:17

            """)
    }

    @Test("emphasis delimiter runs are not chunked")
    func emphasisRunsUnchunked() {
        #expect(TreeDump.dump("***a***", options: .strikethrough, limits: limits(1)) == """
            document
              paragraph
                emph
                  strong
                    text "a"

            """)
    }
}
