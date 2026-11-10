/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A tab stop comes every four characters (Tabs), so a footnote definition's label counts one column per character,
/// however many bytes it takes, toward the tab stops of a tab later on its line.
@Suite("Tab stops after a non-ASCII footnote label")
struct TabStopAfterNonASCIIFootnoteLabelTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.footnotes, .sourcePosition], sourceRanges: true)
    }

    @Test("a tab after a list marker")
    func tabAfterListMarker() {
        #expect(tree("x[^é]\n\n[^é]: -\tfoo\n\n        bar\n") == """
            document @1:1-6:1
              paragraph @1:1-1:7
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:7
              footnote_definition "é" @3:1-5:12
                list bullet '-' loose @3:8-5:12
                  item @3:8-5:12
                    paragraph @3:10-3:13
                      text "foo" @3:10-3:13
                    paragraph @5:9-5:12
                      text "bar" @5:9-5:12

            """)
    }

    @Test("a tab after a block quote marker")
    func tabAfterBlockQuoteMarker() {
        #expect(tree("x[^é]\n\n[^é]: >\t\tfoo\n") == """
            document @1:1-4:1
              paragraph @1:1-1:7
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:7
              footnote_definition "é" @3:1-3:14
                block_quote @3:8-3:14
                  code_block "" "foo\\n" @3:11-3:14

            """)
    }
}
