/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

@Suite("Footnote Definition Tests")
struct FootnoteDefinitionTests {

    /// A footnote definition whose content is copied into the arena, rather than borrowed from the source, registers
    /// its label and resolves a reference.
    @Test("footnote definition with materialized (CRLF) content registers and resolves")
    func materializedFootnoteDefinitionResolves() {
        // Joining lines across a CRLF line ending copies the content into the arena.
        let source = "[^a]: first line\r\nsecond line\n\nsee [^a]\n"
        MarkdownDocument.withParsedDocument(source, options: [.footnotes]) { doc in

        var defLabel: String? = nil
        var refLabel: String? = nil
        var refIndex: Int? = nil

        let root = doc.root
        root.children.forEach { block in
            if block.kind == .footnoteDefinition {
                defLabel = block.footnoteLabel()
            }
            block.children.forEach { inline in
                if case .footnoteReference(let index) = inline.kind {
                    refLabel = inline.footnoteLabel()
                    refIndex = index
                }
            }
        }

        #expect(defLabel == "a")
        #expect(refLabel == "a")
        #expect(refIndex == 1)
        }
    }
}
