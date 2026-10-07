/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import CommonMark

// Test-target `String` and `Segments` accessors for a node's content.
//
// The `String` accessors use `stringContent`, which is available on every deployment target. `literalSegments()` vends the borrowed `Segments` (`UTF8Span`) form, which requires OS 26.
extension MarkdownNode {

    borrowing func literal() -> String? {
        switch stringContent {
        case .text(let s): return s
        case .codeBlock(_, let body): return body
        case .htmlBlock(let body): return body
        default: return nil
        }
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    borrowing func literalSegments() -> Segments {
        // `content`'s payload is `~Copyable` and can only be borrowed in place, so the `Segments` are derived from the record data the same way `content` derives them.
        switch _view.record(at: _index).data {
        case .literal(let ref): return Segments(view: _view, ref: ref)
        case .codeBlock(_, let body): return Segments(view: _view, ref: body)
        case .htmlBlock(_, let body): return Segments(view: _view, ref: body)
        default: return Segments(view: _view, ref: .empty)
        }
    }

    borrowing func url() -> String? {
        if case .link(let url, _) = stringContent { return url }
        return nil
    }

    borrowing func title() -> String? {
        if case .link(_, let title) = stringContent { return title }
        return nil
    }

    borrowing func attributes() -> String? {
        if case .attribute(let a) = stringContent { return a }
        return nil
    }

    borrowing func codeBlockInfoString() -> String? {
        if case .codeBlock(let info, _) = stringContent { return info }
        return nil
    }

    borrowing func footnoteLabel() -> String? {
        if case .footnote(let label) = stringContent { return label }
        return nil
    }
}
