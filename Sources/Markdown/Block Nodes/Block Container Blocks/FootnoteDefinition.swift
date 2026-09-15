/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A footnote definition, written as `[^label]: content`.
///
/// Footnote references and definitions are a GitHub Flavored Markdown extension enabled with
/// the ``ParseOptions/footnotes`` option. A definition is a block container holding the
/// footnote's content; it is matched to ``FootnoteReference`` elements by its ``footnoteLabel``.
public struct FootnoteDefinition: BlockContainer {
    public var _data: _MarkupData

    init(_ raw: RawMarkup) throws {
        guard case .footnoteDefinition = raw.data else {
            throw RawMarkup.Error.concreteConversionError(from: raw, to: FootnoteDefinition.self)
        }
        let absoluteRaw = AbsoluteRawMarkup(markup: raw, metadata: MarkupMetadata(id: .newRoot(), indexInParent: 0))
        self.init(_MarkupData(absoluteRaw))
    }

    init(_ data: _MarkupData) {
        self._data = data
    }
}

// MARK: - Public API

public extension FootnoteDefinition {
    /// Create a footnote definition with a label and child block elements.
    init(label: String, _ children: some Sequence<BlockMarkup>) {
        try! self.init(.footnoteDefinition(parsedRange: nil, label: label, children.map { $0.raw.markup }))
    }

    /// The definition's label, matching that of its ``FootnoteReference`` elements.
    var footnoteLabel: String {
        get {
            guard case let .footnoteDefinition(label) = _data.raw.markup.data else {
                fatalError("\(self) markup wrapped unexpected \(_data.raw)")
            }
            return label
        }
        set {
            _data = _data.replacingSelf(.footnoteDefinition(parsedRange: nil, label: newValue, _data.raw.markup.copyChildren()))
        }
    }

    // MARK: Visitation

    func accept<V: MarkupVisitor>(_ visitor: inout V) -> V.Result {
        return visitor.visitFootnoteDefinition(self)
    }
}
