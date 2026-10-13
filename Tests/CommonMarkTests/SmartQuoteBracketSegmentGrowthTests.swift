/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Storage growth for smart quotes followed by a long run of unmatched bracket pairs.
///
/// With `.smart`, two quotes followed by `n` bracket pairs that resolve to no link must store content in proportion to
/// the input.
@Suite("Smart quotes before unmatched brackets store linear content")
struct SmartQuoteBracketSegmentGrowthTests {

    @Test("the text is one run")
    func text() {
        #expect(TreeDump.dump("''[a][a][a]", options: [.smart]) == """
            document
              paragraph
                text "\u{2018}\u{2019}[a][a][a]"

            """)
    }

    @Test("segment count grows linearly with the bracket pairs", arguments: [MarkdownDocument.ParseOptions.smart, [.smart, .inlineOnly]])
    func linearSegments(_ options: MarkdownDocument.ParseOptions) {
        let source = "''" + String(repeating: "[a]", count: 2000)
        let segments = MarkdownDocument.withParsedDocument(source, options: options) { $0._segmentCount }
        // Without `.smart` this input stores about one segment per byte.
        #expect(segments <= 4 * source.utf8.count, "\(segments) segments for \(source.utf8.count) bytes")
    }
}
