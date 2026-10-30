/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension MarkdownNode {

    /// A node's content, exposed as borrowed spans you inspect with a single `switch`.
    ///
    /// The spans point into the document's storage, so a `Content` value can't outlive the node's borrow. For owned strings, or on any OS release, use `stringContent`.
    ///
    /// Textual content can span several segments, so iterate them rather than assuming one contiguous span.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public enum Content: ~Copyable, ~Escapable {
        /// No content (structural nodes: document, list, item, table, breaks, emphasis, …).
        case none
        /// Inline literal text - `.text`, `.codeInline`, `.htmlInline`.
        case text(Segments)
        /// A code block's info string and body.
        case codeBlock(info: UTF8Span, body: Segments)
        /// An HTML block's body.
        case htmlBlock(body: Segments)
        /// A link or image destination and title, either of which may be empty.
        case link(url: UTF8Span, title: UTF8Span)
        /// The raw attribute string of an `^[…]` inline attribute.
        case attribute(UTF8Span)
        /// A footnote reference or definition label.
        case footnote(label: UTF8Span)
    }

    /// The node's content as borrowed spans. For owned strings, or on an OS release without `UTF8Span`, use `stringContent`.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public var content: Content {
        @_lifetime(borrow self)
        get {
            switch _view.record(at: _index).data {
            case .literal(let ref):
                return .text(Segments(view: _view, ref: ref))
            case .codeBlock(let info, let body):
                return .codeBlock(info: _view.utf8Span(of: info), body: Segments(view: _view, ref: body))
            case .htmlBlock(_, let body):
                return .htmlBlock(body: Segments(view: _view, ref: body))
            case .link(let url, let title):
                return .link(url: _view.utf8Span(of: url), title: _view.utf8Span(of: title))
            case .attribute(let ref):
                return .attribute(_view.utf8Span(of: ref))
            case .footnoteReference(let label):
                return .footnote(label: _view.utf8Span(of: label))
            case .footnoteDefinition(let label):
                return .footnote(label: _view.utf8Span(of: label))
            default:
                return .none
            }
        }
    }
}

extension MarkdownNode {

    /// A node's content as owned strings, which can outlive the node.
    public enum StringContent: Sendable, Hashable {
        /// No content (structural nodes: document, list, item, table, breaks, emphasis, …).
        case none
        /// Inline literal text - `.text`, `.codeInline`, `.htmlInline`.
        case text(String)
        /// A code block's info string and body.
        case codeBlock(info: String, body: String)
        /// An HTML block's body.
        case htmlBlock(body: String)
        /// A link or image destination and title, either of which may be empty.
        case link(url: String, title: String)
        /// The raw attribute string of an `^[…]` inline attribute.
        case attribute(String)
        /// A footnote reference or definition label.
        case footnote(label: String)
    }

    /// The node's content as owned strings. Where `UTF8Span` is available, `content` reads it without copying.
    public var stringContent: StringContent {
        borrowing get {
            switch _view.record(at: _index).data {
            case .literal(let ref):
                return .text(_view.string(of: ref))
            case .codeBlock(let info, let body):
                return .codeBlock(info: _view.string(of: info), body: _view.string(of: body))
            case .htmlBlock(_, let body):
                return .htmlBlock(body: _view.string(of: body))
            case .link(let url, let title):
                return .link(url: _view.string(of: url), title: _view.string(of: title))
            case .attribute(let ref):
                return .attribute(_view.string(of: ref))
            case .footnoteReference(let label):
                return .footnote(label: _view.string(of: label))
            case .footnoteDefinition(let label):
                return .footnote(label: _view.string(of: label))
            default:
                return .none
            }
        }
    }
}
