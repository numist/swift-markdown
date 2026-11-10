/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Per-kind storage variant for a node.
internal enum NodeData {
    /// Inline literal content: text, code spans, raw HTML.
    case literal(ContentRef)

    /// Code block info string and body. Fence metadata lives on the node's `kind`.
    case codeBlock(info: ContentRef, literal: ContentRef)

    case link(url: ContentRef, title: ContentRef)

    /// The HTML block's start condition (HTML blocks), 1–7, and its body.
    case htmlBlock(type: UInt8, literal: ContentRef)

    /// `^[…]` inline attribute: its attribute string, as written for `^[text](…)`, or with backslash escapes and character references decoded when it comes from a definition.
    case attribute(ContentRef)

    /// Footnote reference label. The assigned index lives on the node's `kind`.
    case footnoteReference(label: ContentRef)

    case footnoteDefinition(label: ContentRef)

    /// Column alignments live on each cell's `kind`.
    case table(columnCount: Int)

    /// `padding` is the indent, in columns past the enclosing containers' prefixes, that a continuation line needs to belong to the item (List items).
    case item(padding: Int)
}

/// A link to a node, or to none, stored in one word. None is `-1`, which is no index in `DocumentStorage.nodes`.
@propertyWrapper
internal struct NodeLink {
    private var index = -1

    internal init(wrappedValue: DocumentStorage.Index?) {
        self.wrappedValue = wrappedValue
    }

    internal var wrappedValue: DocumentStorage.Index? {
        get { index < 0 ? nil : index }
        set {
            assert((newValue ?? 0) >= 0, "a node index is never negative")
            index = newValue ?? -1
        }
    }
}

/// One node, stored contiguously in `DocumentStorage.nodes`.
internal struct NodeRecord {
    internal var kind: MarkdownNode.Kind
    @NodeLink internal var firstChild: DocumentStorage.Index?
    @NodeLink internal var lastChild: DocumentStorage.Index?
    @NodeLink internal var next: DocumentStorage.Index?
    @NodeLink internal var previous: DocumentStorage.Index?
    @NodeLink internal var parent: DocumentStorage.Index?
    internal var data: NodeData?

    /// Whether the last line processed while this node was open was blank; drives tight/loose list detection.
    internal var lastLineBlank: Bool = false

    internal init(
        kind: MarkdownNode.Kind,
        parent: DocumentStorage.Index? = nil,
        data: NodeData? = nil
    ) {
        self.kind = kind
        self.firstChild = nil
        self.lastChild = nil
        self.next = nil
        self.previous = nil
        self.parent = parent
        self.data = data
    }
}
