/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Paragraphs of backtick strings of distinct lengths (Code spans).
///
/// A backtick string begins a code span only if a backtick string of equal length closes it, so none of these does and
/// the paragraph is text. A paragraph of 1,500 such strings, about 1.1 MB of source, parses well within the time
/// limit.
@Suite("Ladders of unmatched backtick strings")
struct UnmatchedBacktickStringLadderTests {
    private static let options: [MarkdownDocument.ParseOptions] = [[], .inlineOnly]

    /// `count` backtick strings of lengths 1 through `count`, each after an `a`.
    private static func ladder(count: Int) -> String {
        (1...count).map { "a" + String(repeating: "`", count: $0) }.joined()
    }

    @Test(arguments: options)
    func ladderIsText(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(Self.ladder(count: 3), options: options) == """
            document
              paragraph
                text "a`a``a```"

            """)
    }

    @Test(arguments: options)
    func codeSpansAfterUnmatchedLongerStringClose(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("```x `a` `b`", options: options) == """
            document
              paragraph
                text "```x "
                code "a"
                text " "
                code "b"

            """)
    }

    @Test(.timeLimit(.minutes(1)), arguments: options)
    func longLadderIsText(options: MarkdownDocument.ParseOptions) {
        let source = Self.ladder(count: 1500)
        #expect(TreeDump.dump(source, options: options) == """
            document
              paragraph
                text "\(source)"

            """)
    }
}
