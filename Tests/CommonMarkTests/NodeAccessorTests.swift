/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The node accessors a tree walk with `children` alone doesn't reach: `content` for HTML blocks, attributes and
/// footnotes, `Segments.byteCount`, `parent` at the root and `previous` past the first child.
@Suite("Node accessors")
struct NodeAccessorTests {

    @Test("an HTML block's content is its body segments")
    func htmlBlockContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let body = MarkdownDocument.withParsedDocument("<div>\nx\n</div>\n") { document -> String? in
            var body: String?
            document.root.children.forEach { block in
                switch block.content {
                case .htmlBlock(let segments): body = joined(segments)
                default: break
                }
            }
            return body
        }
        #expect(body == "<div>\nx\n</div>\n")
    }

    @Test("an attribute's content is its raw attribute string, nested parentheses included")
    func attributeContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let attributes = MarkdownDocument.withParsedDocument("^[x](k: (v))", options: [.attributes]) { document -> String? in
            var attributes: String?
            document.root.children.forEach { paragraph in
                paragraph.children.forEach { inline in
                    switch inline.content {
                    case .attribute(let raw): attributes = String(copying: raw)
                    default: break
                    }
                }
            }
            return attributes
        }
        #expect(attributes == "k: (v)")
    }

    @Test("a footnote reference's and definition's content is the label")
    func footnoteContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let labels = MarkdownDocument.withParsedDocument("[^a]\n\n[^a]: d\n", options: [.footnotes]) { document -> [String] in
            var labels: [String] = []
            document.root.children.forEach { block in
                switch block.content {
                case .footnote(let label): labels.append(String(copying: label))
                default: break
                }
                block.children.forEach { inline in
                    switch inline.content {
                    case .footnote(let label): labels.append(String(copying: label))
                    default: break
                    }
                }
            }
            return labels
        }
        #expect(labels == ["a", "a"])
    }

    @Test("a code block body's byte count spans all its segments")
    func segmentsByteCount() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let counts = MarkdownDocument.withParsedDocument("```\na\nbb\n```\n") { document -> (Int, Int)? in
            var counts: (Int, Int)?
            document.root.children.forEach { block in
                switch block.content {
                case .codeBlock(_, let body): counts = (body.byteCount, joined(body).utf8.count)
                default: break
                }
            }
            return counts
        }
        #expect(counts?.0 == 5)
        #expect(counts?.1 == 5)
    }

    @Test("the root has no parent, and a second child's previous sibling is the first")
    func parentAndPrevious() {
        let result = MarkdownDocument.withParsedDocument("a\n\n# b\n") { document -> (Bool, String) in
            let rootHasParent = document.root.parent != nil
            var previousKind = ""
            var index = 0
            document.root.children.forEach { block in
                if index == 1, let previous = block.previous { previousKind = "\(previous.kind)" }
                index += 1
            }
            return (rootHasParent, previousKind)
        }
        #expect(result.0 == false)
        #expect(result.1 == "paragraph")
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private func joined(_ segments: borrowing MarkdownNode.Segments) -> String {
        var text = ""
        segments.forEach { text += String(copying: $0) }
        return text
    }
}
