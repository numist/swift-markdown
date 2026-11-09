/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a delimiter run is longer than the run it pairs with, the unused delimiters remain text
/// (Emphasis and strong emphasis). The emphasis or strong emphasis source range covers only the
/// delimiters it uses and its content.
@Suite("Emphasis source ranges - partial pairing")
struct PartialPairingEmphasisRangeTests {

    @Test("partial pairing emphasis range excludes unused delimiters")
    func partialPairingExcludesUnusedDelimiters() {
        #expect(TreeDump.dump("**o*", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "*" @1:1-1:2
                emph @1:2-1:5
                  text "o" @1:3-1:4

            """)
        #expect(TreeDump.dump("*o**", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                emph @1:1-1:4
                  text "o" @1:2-1:3
                text "*" @1:4-1:5

            """)
        // The strong emphasis uses the inner two delimiters of each run, the emphasis the outer one.
        #expect(TreeDump.dump("***o***", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                emph @1:1-1:8
                  strong @1:2-1:7
                    text "o" @1:4-1:5

            """)
    }
}
