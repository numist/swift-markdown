/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The URL of an extended email autolink whose address skips a backslash escape is the whole address without the
/// backslash, and the borrowed `content` API vends it as one `UTF8Span` holding that whole URL.
@Suite("Escaped email autolink URL content")
struct EscapedEmailAutolinkURLContentTests {

    @Test("a scheme-prefixed address around an escaped period")
    func schemeAroundEscapedPeriodTree() {
        #expect(TreeDump.dump("xmpp:@\\.c", options: [.gfmAutolink]) == """
            document
              paragraph
                link "xmpp:@.c" ""
                  text "xmpp:@.c"

            """)
    }

    @Test("a scheme-prefixed address around an escaped period has one whole URL span")
    func schemeAroundEscapedPeriodContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(linkURLSpans("xmpp:@\\.c") == ["xmpp:@.c"])
    }

    @Test("a mailto address with an escaped local-part byte")
    func mailtoAroundEscapedUnderscoreTree() {
        #expect(TreeDump.dump("mailto:a\\_b@c.d", options: [.gfmAutolink]) == """
            document
              paragraph
                link "mailto:a_b@c.d" ""
                  text "mailto:a_b@c.d"

            """)
    }

    @Test("a mailto address with an escaped local-part byte has one whole URL span")
    func mailtoAroundEscapedUnderscoreContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(linkURLSpans("mailto:a\\_b@c.d") == ["mailto:a_b@c.d"])
    }

    @Test("a bare address with an escaped local-part byte")
    func bareAroundEscapedPeriodTree() {
        #expect(TreeDump.dump("a\\.b@c.d", options: [.gfmAutolink]) == """
            document
              paragraph
                link "mailto:a.b@c.d" ""
                  text "a.b@c.d"

            """)
    }

    @Test("a bare address with an escaped local-part byte has one whole mailto URL span")
    func bareAroundEscapedPeriodContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(linkURLSpans("a\\.b@c.d") == ["mailto:a.b@c.d"])
    }

    /// Each link's URL span from `content`, in document order.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private func linkURLSpans(_ markdown: String) -> [String] {
        MarkdownDocument.withParsedDocument(markdown, options: [.gfmAutolink]) { doc in
            var urls: [String] = []
            func walk(_ node: borrowing MarkdownNode) {
                switch node.content {
                case .link(let url, _):
                    urls.append(String(copying: url))
                default:
                    break
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return urls
        }
    }
}
