/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A processing instruction needs a closing `?>` (Raw HTML), so an unclosed `<?` in a block quote paragraph in a list
/// item is text. The paragraph's lazy continuation line holds a NUL, which is replaced by U+FFFD (Insecure
/// characters), and a `[x]` that does not begin the paragraph and so is text (Task list items (extension)).
@Suite("Unclosed processing instruction in a list item's block quote")
struct UnclosedProcessingInstructionInListItemTests {

    @Test("an unclosed `<?` after a tab is text")
    func afterTab() {
        #expect(TreeDump.dump("- >\ta<?\n  2\u{0} [x] \n", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "a<?"
                      softbreak
                      text "2\u{FFFD} [x]"

            """)
        #expect(TreeDump.dump("- >\ta<?\n  2\u{0} [x] \n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:10
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  block_quote @1:3-2:9
                    paragraph @1:5-2:9
                      text "a<?" @1:5-1:8
                      softbreak @-
                      text "2\u{FFFD} [x]" @2:3-2:9

            """)
    }

    @Test("an unclosed `<?` after a tab and a NUL is text")
    func afterTabAndNUL() {
        #expect(TreeDump.dump("- >\ta\u{0}<?\n  2\u{0} [x] \n", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "a\u{FFFD}<?"
                      softbreak
                      text "2\u{FFFD} [x]"

            """)
        #expect(TreeDump.dump("- >\ta\u{0}<?\n  2\u{0} [x] \n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:10
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  block_quote @1:3-2:9
                    paragraph @1:5-2:9
                      text "a\u{FFFD}<?" @1:5-1:9
                      softbreak @-
                      text "2\u{FFFD} [x]" @2:3-2:9

            """)
    }

    @Test("an unclosed `<?` after a NUL is text")
    func afterNUL() {
        #expect(TreeDump.dump("- >a\u{0}<?\n  2\u{0} [x] \n", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "a\u{FFFD}<?"
                      softbreak
                      text "2\u{FFFD} [x]"

            """)
        #expect(TreeDump.dump("- >a\u{0}<?\n  2\u{0} [x] \n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:10
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  block_quote @1:3-2:9
                    paragraph @1:4-2:9
                      text "a\u{FFFD}<?" @1:4-1:8
                      softbreak @-
                      text "2\u{FFFD} [x]" @2:3-2:9

            """)
    }

    @Test("an unclosed `<?` after a U+FFFD is text")
    func afterReplacementCharacter() {
        #expect(TreeDump.dump("- >\u{FFFD}<?\n  2\u{0} [x] ", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "\u{FFFD}<?"
                      softbreak
                      text "2\u{FFFD} [x]"

            """)
        #expect(TreeDump.dump("- >\u{FFFD}<?\n  2\u{0} [x] ", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:10
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  block_quote @1:3-2:9
                    paragraph @1:4-2:9
                      text "\u{FFFD}<?" @1:4-1:9
                      softbreak @-
                      text "2\u{FFFD} [x]" @2:3-2:9

            """)
    }
}
