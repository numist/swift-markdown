/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Line endings and tabs")
struct LineReaderTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.sourcePosition], sourceRanges: true)
    }

    @Test(arguments: ["aa\nbb\ncc", "aa\r\nbb\rcc"])
    func lineEndings(_ source: String) {
        #expect(tree(source) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                text "aa" @1:1-1:3
                softbreak @-
                text "bb" @2:1-2:3
                softbreak @-
                text "cc" @3:1-3:3

            """)
    }

    @Test
    func tabsInsideALineAreKept() {
        #expect(tree("\tfoo\tbaz\t\tbim\n") == """
            document @1:1-2:1
              code_block "" "foo\\tbaz\\t\\tbim\\n" @1:2-1:14

            """)
    }
}
