/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A link written with an empty destination and no title, `[a]()`, vends empty URL and title spans through the
/// borrowed `content` API, matching cmark-gfm's empty `cmark_node_get_url`/`cmark_node_get_title`.
@Suite("Empty link destination content")
struct EmptyLinkContentTests {

    private let source = "[a]()"

    @Test("the tree holds a link with an empty URL and title")
    func tree() {
        #expect(CmarkTreeDump.dump(source, options: []) == """
            document
              paragraph
                link "" ""
                  text "a"

            """)
    }

    @Test("content vends empty URL and title spans")
    func borrowedContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let (url, title) = MarkdownDocument.withParsedDocument(source) { doc -> (String?, String?) in
            var url: String?
            var title: String?
            func walk(_ node: borrowing MarkdownNode) {
                switch node.content {
                case .link(let u, let t):
                    url = String(copying: u)
                    title = String(copying: t)
                default:
                    break
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (url, title)
        }
        #expect(url == "")
        #expect(title == "")
    }
}
