/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for many backtick runs of distinct lengths, none of which closes a code span.
///
/// Each run looks for a closing run of its own length to the end of the paragraph. Scanning the rest of the paragraph
/// afresh for every run makes `k` such runs cost `k` scans of the whole paragraph.
@Suite("Unmatched backtick runs parse in linear time")
struct UnmatchedBacktickRunParseTimeTests {

    static let options: [MarkdownDocument.ParseOptions] = [[], .inlineOnly]

    /// A paragraph of `count` backtick runs of lengths 1 through `count`, each after an `a`.
    static func ladder(count: Int) -> String {
        (1...count).map { "a" + String(repeating: "`", count: $0) }.joined()
    }

    @Test("a ladder of distinct backtick runs stays text", arguments: options)
    func ladderText(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(Self.ladder(count: 3), options: options) == """
            document
              paragraph
                text "a`a``a```"

            """)
    }

    /// The single backticks after the unmatched triple pair up into two code spans.
    @Test("code spans after an unmatched longer run still close", arguments: options)
    func spansAfterUnmatchedRun(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("```x `a` `b`", options: options) == """
            document
              paragraph
                text "```x "
                code "a"
                text " "
                code "b"

            """)
    }
}
