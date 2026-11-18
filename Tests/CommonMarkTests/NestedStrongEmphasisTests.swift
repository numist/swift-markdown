/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// The spec's HTML for these examples renders strong emphasis nested in strong emphasis as one `<strong>`, so the
// trees pin the nesting.
@Suite("Strong emphasis within strong emphasis")
struct NestedStrongEmphasisTests {

    @Test("spec example 398")
    func example398() {
        #expect(TreeDump.dump("__foo, __bar__, baz__\n", options: []) == """
            document
              paragraph
                strong
                  text "foo, "
                  strong
                    text "bar"
                  text ", baz"

            """)
    }

    @Test("spec example 426")
    func example426() {
        #expect(TreeDump.dump("foo******bar*********baz\n", options: []) == """
            document
              paragraph
                text "foo"
                strong
                  strong
                    strong
                      text "bar"
                text "***baz"

            """)
    }

    @Test("spec example 434")
    func example434() {
        #expect(TreeDump.dump("__foo __bar__ baz__\n", options: []) == """
            document
              paragraph
                strong
                  text "foo "
                  strong
                    text "bar"
                  text " baz"

            """)
    }

    @Test("spec example 435")
    func example435() {
        #expect(TreeDump.dump("____foo__ bar__\n", options: []) == """
            document
              paragraph
                strong
                  strong
                    text "foo"
                  text " bar"

            """)
    }

    @Test("spec example 436")
    func example436() {
        #expect(TreeDump.dump("**foo **bar****\n", options: []) == """
            document
              paragraph
                strong
                  text "foo "
                  strong
                    text "bar"

            """)
    }

    @Test("spec example 473")
    func example473() {
        #expect(TreeDump.dump("****foo****\n", options: []) == """
            document
              paragraph
                strong
                  strong
                    text "foo"

            """)
    }

    @Test("spec example 474")
    func example474() {
        #expect(TreeDump.dump("____foo____\n", options: []) == """
            document
              paragraph
                strong
                  strong
                    text "foo"

            """)
    }

    @Test("spec example 475")
    func example475() {
        #expect(TreeDump.dump("******foo******\n", options: []) == """
            document
              paragraph
                strong
                  strong
                    strong
                      text "foo"

            """)
    }

    @Test("spec example 477")
    func example477() {
        #expect(TreeDump.dump("_____foo_____\n", options: []) == """
            document
              paragraph
                emph
                  strong
                    strong
                      text "foo"

            """)
    }
}
