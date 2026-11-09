/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// The `init(parsing:)` initializers and the `source` accessor, which exist only where `UTF8Span` does.
@Suite("anyAppleOS 26 initializers")
struct AppleOS26InitializerTests {

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test("returning String initializer parses the expected tree")
    func stringInitializer() {
        let source = "# Title\n\nA paragraph with *emphasis*."
        let doc = MarkdownDocument(parsing: source)
        #expect(dfs(doc).map { TreeDump.describe($0.kind) } == ["document", "heading 1", "text", "paragraph", "text", "emph", "text", "text"])
        #expect(dfs(doc).map(\.literal) == [nil, nil, "Title", nil, "A paragraph with ", nil, "emphasis", "."])
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test("UTF8Span initializer parses the same tree as the String initializer")
    func utf8SpanInitializer() {
        let source = "one `code` two"
        let viaString = MarkdownDocument(parsing: source)
        let stringKinds = dfs(viaString).map { TreeDump.describe($0.kind) }
        let viaSpan = MarkdownDocument(parsing: source.utf8Span)
        let spanKinds = dfs(viaSpan).map { TreeDump.describe($0.kind) }
        #expect(stringKinds == ["document", "paragraph", "text", "code backticks=1", "text"])
        #expect(spanKinds == stringKinds)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test("source accessor round-trips the original bytes (incl. multi-byte scalars)")
    func sourceAccessorRoundTrips() {
        let source = "l\u{ED}ne one\nline two"   // `í` is a 2-byte scalar
        let doc = MarkdownDocument(parsing: source)
        #expect(String(copying: doc.source) == source)
    }
}
