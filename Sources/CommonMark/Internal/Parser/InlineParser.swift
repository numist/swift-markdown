/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// The emphasis `openersBottom` table: rows by whether the closer can open and its `length % 3`, columns by delimiter
/// character (`*_~'"`).
///
/// It wraps `SIMD32` because `InlineArray` requires the anyAppleOS 26 runtime.
internal struct OpenersBottom {
    private var storage: SIMD32<Int>

    internal init(fill: Int) {
        storage = SIMD32(repeating: fill)
    }

    internal subscript(_ row: Int, _ col: Int) -> Int {
        get { storage[row * 5 + col] }
        set { storage[row * 5 + col] = newValue }
    }
}

/// Per kind, the starts from which a raw-HTML closer scan fails in the current `parseInline` pass. A scan
/// that fails from `p` reached the content end, ruling out every start at or after `p`, so an unclosed opener
/// doesn't rescan to the end.
internal struct HTMLCloserMisses {
    var comment: Range<Int> = 0..<0
    var cdata: Range<Int> = 0..<0
    var declaration: Range<Int> = 0..<0
    var processingInstruction: Range<Int> = 0..<0
}

/// The backtick runs that a closer scan passed on its way to the content end in one `parseInline` pass.
///
/// A scan from a run's end splits the content into the same runs as any other, so once a scan has reached the end from
/// `scannedToEndFrom`, an opener ending at or past it has a closer exactly when a run of its length starts at or past its
/// end. At most one scan per pass reaches the end.
internal struct BacktickRunsSeen {
    /// The offset from which this pass's one scan to the content end began, or `nil` if no scan has reached the end.
    var scannedToEndFrom: Int?
    /// The latest start of a run of each length at or past `scannedToEndFrom`.
    var latestStart = [Int: Int]()

    /// Whether the scan to the content end shows that no run of `length` backticks starts at or past `openEnd`, the end of an opening run of that length.
    func rulesOutCloser(length: Int, after openEnd: Int) -> Bool {
        guard let scannedToEndFrom, scannedToEndFrom <= openEnd else {
            return false
        }
        return latestStart[length, default: -1] < openEnd
    }

    mutating func recordRun(length: Int, start: Int) {
        latestStart[length] = max(latestStart[length, default: -1], start)
    }
}

extension BlockParser {

    /// Parses `content` into inline children of `parent`.
    mutating func parseInline(
        content: borrowing ContentSpan,
        into parent: DocumentStorage.Index,
        preserveWhitespace: Bool = false
    ) {
        if content.isEmpty {
            return
        }
        // The delimiter and bracket stacks are reused across blocks rather than allocated per call.
        delimiters.removeSubrange(0..<delimiters.count)
        brackets.removeSubrange(0..<brackets.count)
        
        var cursor = content.startOffset
        let endOffset = content.endOffset
        var pendingTextStart = cursor
        lastDelim = nil
        lastBracket = nil
        linksFormed = 0

        let strikethroughEnabled = storage.options.contains(.strikethrough)
        let gfmAutolinkEnabled = storage.options.contains(.gfmAutolink)
        let smartEnabled = storage.options.contains(.smart)

        htmlCloserMisses = HTMLCloserMisses()
        destinationParentheses.reset()
        attributeParentheses.reset()
        // Runs are recorded only once a scan has reached the content end.
        if backtickRunsSeen.scannedToEndFrom != nil {
            backtickRunsSeen = BacktickRunsSeen()
        }
        characterReferenceSources.removeAll(keepingCapacity: true)

        while cursor < endOffset {
            let byte = content[cursor]
            switch byte {
            case UInt8(ascii: "`"):
                cursor = handleBackticks(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "\n"):
                cursor = handleLineEnding(at: cursor, preserveWhitespace: preserveWhitespace, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "&"):
                cursor = handleCharacterReference(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "<"):
                cursor = handleAngleBracket(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "*"), UInt8(ascii: "_"):
                cursor = handleDelimRun(
                    char: byte,
                    start: cursor,
                    content: content,
                    parent: parent,
                    pendingTextStart: &pendingTextStart
                )

            case UInt8(ascii: "~"):
                if strikethroughEnabled {
                    cursor = handleDelimRun(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "["):
                cursor = openBracket(
                    .link,
                    length: 1,
                    at: cursor,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )

            case UInt8(ascii: "!"):
                cursor = handleExclamationMark(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "^"):
                cursor = handleCaret(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "]"):
                flushPendingText(
                    start: pendingTextStart,
                    end: cursor,
                    content: content,
                    into: parent
                )
                cursor = handleCloseBracket(
                    cursor: cursor,
                    content: content,
                    parent: parent
                )
                pendingTextStart = cursor

            case UInt8(ascii: "\\"):
                cursor = handleBackslash(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: ":"), UInt8(ascii: "w"):
                cursor = handleGFMAutolinkTrigger(byte, at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)

            case UInt8(ascii: "'"), UInt8(ascii: "\""):
                if smartEnabled {
                    cursor = handleQuoteDelim(
                        char: byte,
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "-"):
                if smartEnabled {
                    cursor = handleSmartHyphen(
                        start: cursor,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "."):
                if smartEnabled {
                    cursor = handleEllipsis(at: cursor, content: content, parent: parent, pendingTextStart: &pendingTextStart)
                } else {
                    cursor += 1
                }

            default:
                cursor = content.nextSignificant(
                    from: cursor,
                    strikethrough: strikethroughEnabled,
                    gfmAutolink: gfmAutolinkEnabled,
                    smart: smartEnabled
                )
            }
        }
        flushPendingText(
            start: pendingTextStart,
            end: endOffset,
            content: content,
            into: parent
        )
        processEmphasis(
            stackBottom: -1,
            content: content
        )
    }

    // Each `handle` step consumes the construct starting at `cursor` and returns where scanning resumes: past the construct, or past the bytes it leaves as pending text.

    /// A code span (Code spans). An unmatched backtick run stays pending text whole.
    private mutating func handleBackticks(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let span = matchCodeSpan(
            start: cursor,
            content: content
        ) {
            emitLiteral(
                .codeInline(backtickCount: span.backtickCount),
                span.content,
                start: cursor,
                end: span.afterClose,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return span.afterClose
        }
        return scanBacktickRun(
            start: cursor,
            content: content
        )
    }

    /// A soft or hard line break (Soft line breaks, Hard line breaks).
    private mutating func handleLineEnding(at cursor: Int, preserveWhitespace: Bool, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let info: LineBreakInfo
        if preserveWhitespace {
            // Preserving whitespace, a line ending is literal text unless a backslash before it forms a hard line break (Hard line breaks).
            guard cursor > pendingTextStart, content[cursor - 1] == UInt8(ascii: "\\") else {
                return cursor + 1
            }
            info = LineBreakInfo(isHard: true, textEnd: cursor - 1)
        } else {
            info = classifyLineBreak(
                at: cursor,
                pendingTextStart: pendingTextStart,
                content: content
            )
        }
        return appendLineBreak(isHard: info.isHard, textEnd: info.textEnd, resumingAt: cursor + 1, content: content, parent: parent, pendingTextStart: &pendingTextStart)
    }

    /// Flushes the pending text before `textEnd` and appends a soft or hard line break, after which scanning and pending
    /// text resume at `resume`.
    private mutating func appendLineBreak(isHard: Bool, textEnd: Int, resumingAt resume: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        flushPendingText(
            start: pendingTextStart,
            end: textEnd,
            content: content,
            into: parent
        )
        let kind: MarkdownNode.Kind = isHard ? .lineBreak : .softBreak
        let breakIdx = storage.appendNode(NodeRecord(kind: kind, parent: parent))
        storage.appendChild(breakIdx, to: parent)
        pendingTextStart = resume
        return resume
    }

    /// An entity or numeric character reference (Entity and numeric character references).
    private mutating func handleCharacterReference(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Entity matching reads one buffer, so it scans `&`'s segment; a line join ends any reference anyway.
        guard let window = content.contiguousChunk(fromVirtual: cursor, limit: content.endOffset) else {
            preconditionFailure("an `&` is never a line join, the only byte without a contiguous chunk")
        }
        guard let entity = characterReference(at: window.offset, in: window) else {
            return cursor + 1
        }
        let decoded = Self.appendUTF8Bytes(
            bytes: entity.bytes,
            count: entity.count,
            into: &storage.strings
        )
        let afterSemi = cursor + (entity.afterSemi - window.offset)
        let textIdx = emitLiteral(
            .text,
            decoded,
            start: cursor,
            end: afterSemi,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        if positionsEnabled {
            let source = storage.sourceRanges[textIdx]
            characterReferenceSources.append((decoded.range, source.start..<source.end))
        }
        return afterSemi
    }

    /// An autolink (Autolinks) or raw inline HTML (Raw HTML).
    private mutating func handleAngleBracket(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if let auto = matchAutolink(
            start: cursor,
            content: content
        ) {
            flushPendingText(
                start: pendingTextStart,
                end: cursor,
                content: content,
                into: parent
            )
            emitAutolink(
                auto: auto,
                into: parent,
                content: content
            )
            linksFormed += 1
            pendingTextStart = auto.afterClose
            return auto.afterClose
        }
        if let htmlEnd = matchInlineHTML(
            start: cursor,
            content: content
        ) {
            emitLiteral(
                .htmlInline,
                materializedChunk(start: cursor, end: htmlEnd, content: content),
                start: cursor,
                end: htmlEnd,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
            return htmlEnd
        }
        return cursor + 1
    }

    /// An image opener `![`.
    private mutating func handleExclamationMark(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if cursor + 1 < content.endOffset,
           content[cursor + 1] == UInt8(ascii: "[") {
            return openBracket(
                .image,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    /// An inline attribute opener `^[`.
    private mutating func handleCaret(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // Without `.attributes`, `^` is ordinary text and a following `[` opens a link bracket.
        if storage.options.contains(.attributes),
           cursor + 1 < content.endOffset,
           content[cursor + 1] == UInt8(ascii: "[") {
            return openBracket(
                .attribute,
                length: 2,
                at: cursor,
                to: parent,
                pendingTextStart: &pendingTextStart,
                content: content
            )
        }
        return cursor + 1
    }

    /// A backslash escape (Backslash escapes). A backslash before a line ending is handled with the line ending; one before anything but ASCII punctuation is literal.
    private mutating func handleBackslash(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        if cursor + 1 < content.endOffset {
            let next = content[cursor + 1]
            if next.isASCIIPunct {
                emitLiteral(
                    .text,
                    content.chunk(offset: cursor + 1, length: 1),
                    start: cursor,
                    end: cursor + 2,
                    to: parent,
                    pendingTextStart: &pendingTextStart,
                    content: content
                )
                return cursor + 2
            }
            // A line ending after a backslash is a hard line break (Hard line breaks). An LF forms it when scanned; a
            // CR, which only inline-only content parsed in place holds, forms it here, with a CRLF's LF.
            if next == UInt8(ascii: "\r"), let afterLineEnding = lineEndingEnd(at: cursor + 1, in: content) {
                return appendLineBreak(isHard: true, textEnd: cursor, resumingAt: afterLineEnding, content: content, parent: parent, pendingTextStart: &pendingTextStart)
            }
        }
        return cursor + 1
    }

    /// An extended url or www autolink, triggered by `byte` (`:` or `w`).
    private mutating func handleGFMAutolinkTrigger(_ byte: UInt8, at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // An open `[` or `![` suppresses the autolink even if it never closes, so `[a http://t.t` is text.
        let insideLinkOrImageBracket = lastBracket.map { brackets[$0].insideLinkOrImage } ?? false
        if storage.options.contains(.gfmAutolink),
           !insideLinkOrImageBracket,
           let auto = matchGFMAutolink(
            trigger: byte,
            cursor: cursor,
            content: content
           ) {
            flushPendingText(
                start: pendingTextStart,
                end: auto.urlStart,
                content: content,
                into: parent
            )
            emitGFMAutolink(
                auto: auto,
                into: parent,
                content: content
            )
            pendingTextStart = auto.urlEnd
            return auto.urlEnd
        }
        return cursor + 1
    }

    /// A smart ellipsis, `...`.
    private mutating func handleEllipsis(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        guard cursor + 2 < content.endOffset,
              content[cursor + 1] == UInt8(ascii: "."),
              content[cursor + 2] == UInt8(ascii: ".") else {
            return cursor + 1
        }
        emitLiteral(
            .text,
            smartConstantChunk(Self.ellipsis),
            start: cursor,
            end: cursor + 3,
            to: parent,
            pendingTextStart: &pendingTextStart,
            content: content
        )
        return cursor + 3
    }

    // MARK: - Links / images (bracket stack)

    internal enum BracketKind {
        case link
        case image
        case attribute

        var nodeKind: MarkdownNode.Kind {
            switch self {
            case .link: .link
            case .image: .image
            case .attribute: .attribute
            }
        }
    }

    /// An open `[`, `![` or `^[` on the bracket stack, a linked list through `previous` in `brackets`.
    internal struct BracketRecord {
        var kind: BracketKind
        var inlText: DocumentStorage.Index
        /// The opener's virtual offset, from which the wrapper's start is stamped. The opener text node's range is in source offsets, so stamping from it would map twice.
        var virtualStart: Int
        /// The delimiter stack top at push: the `stackBottom` for resolving emphasis inside the link text.
        var delimPosition: Int
        /// Whether a bracket was pushed after this one. Its text then holds an unescaped bracket, which no link label does, so it can't be the label of a collapsed or shortcut reference.
        var bracketAfter: Bool = false
        /// Whether this bracket or one enclosing it is a link or image opener, which suppresses extended url and www autolinks.
        var insideLinkOrImage: Bool
        /// `linksFormed` at push. A link opener can't form a link once a link or autolink formed after it, because links
        /// may not contain other links (Links).
        var linksFormedBefore: Int
        var previous: Int?
    }

    /// Pushes a `kind` opener, the `length` bytes at `cursor`, and returns the offset past it. An unresolved opener stays literal text with its own source range.
    private mutating func openBracket(_ kind: BracketKind, length: Int, at cursor: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> Int {
        let textIdx = emitLiteral(.text, content.chunk(offset: cursor, length: length), start: cursor, end: cursor + length, to: parent, pendingTextStart: &pendingTextStart, content: content)
        pushBracket(kind: kind, inlText: textIdx, virtualStart: cursor, delimPosition: lastDelim ?? -1)
        return cursor + length
    }

    private mutating func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int) {
        if let lastBracket {
            brackets[lastBracket].bracketAfter = true
        }
        let prev = lastBracket
        let newIdx = brackets.count
        let insideLinkOrImage = (prev.map { brackets[$0].insideLinkOrImage } ?? false)
            || kind == .link || kind == .image
        brackets.append(BracketRecord(
            kind: kind,
            inlText: inlText,
            virtualStart: virtualStart,
            delimPosition: delimPosition,
            insideLinkOrImage: insideLinkOrImage,
            linksFormedBefore: linksFormed,
            previous: prev
        ))
        lastBracket = newIdx
    }

    private mutating func popBracket() {
        if let last = lastBracket {
            lastBracket = brackets[last].previous
        }
    }
    
    /// Handles a `]`: the innermost opener becomes a link, image or attribute when that form follows, or a footnote reference when `[^label]` names a definition. Otherwise the `]` is literal text; after an `^[` opener, a label that follows is consumed into the `]`'s source range but not its text.
    private mutating func handleCloseBracket(cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) -> Int {
        let afterBracket = cursor + 1
        guard let openerIdx = lastBracket else {
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let openerKind = brackets[openerIdx].kind
        let openerInl = brackets[openerIdx].inlText
        let openerDelimPos = brackets[openerIdx].delimPosition
        let openerStart = brackets[openerIdx].virtualStart
        if openerKind == .link, brackets[openerIdx].linksFormedBefore < linksFormed {
            popBracket()
            emitBracketLiteral(at: cursor, end: afterBracket, content: content, parent: parent)
            return afterBracket
        }
        let formed: (data: NodeData, end: Int)?
        let literalEnd: Int
        if openerKind == .attribute {
            let attribute = matchAttributeForm(cursor: cursor, content: content)
            formed = attribute.data.map { ($0, attribute.end) }
            literalEnd = attribute.end
        } else if let inline = matchInlineLinkForm(cursor: cursor, content: content) {
            formed = inline
            literalEnd = afterBracket
        } else {
            formed = matchReferenceLinkForm(bracketTextStart: brackets[openerIdx].bracketAfter ? nil : openerStart + (openerKind == .image ? 2 : 1), cursor: cursor, content: content)
            literalEnd = afterBracket
        }
        if let formed {
            wrapBracketContent(openerKind.nodeKind, formed.data, openerInl: openerInl, delimPosition: openerDelimPos, start: openerStart, end: formed.end, content: content)
            popBracket()
            if openerKind == .link {
                linksFormed += 1
            }
            return formed.end
        }
        if openerKind != .attribute, emitFootnoteReferenceIfDefined(openerIdx: openerIdx, bracketStart: openerKind == .image ? openerStart + 1 : openerStart, closeBracket: cursor, content: content) {
            return afterBracket
        }
        popBracket()
        emitBracketLiteral(at: cursor, end: literalEnd, content: content, parent: parent)
        return literalEnd
    }

    /// The link or image data for an inline link after the `]` at `cursor`, and the offset past it.
    @inline(__always)
    private mutating func matchInlineLinkForm(cursor: Int, content: borrowing ContentSpan) -> (data: NodeData, end: Int)? {
        let pos = cursor + 1
        guard pos < content.endOffset, content[pos] == UInt8(ascii: "("),
              let inline = matchInlineLinkTail(afterParen: pos + 1, content: content) else {
            return nil
        }
        return (.link(url: storage.intern(inline.url), title: storage.intern(inline.title)), inline.end)
    }

    /// The link or image data for a full, collapsed or shortcut reference after the `]` at `cursor`, and the offset past it.
    ///
    /// `bracketTextStart` is where the bracket text begins, which collapsed and shortcut references take as their label, or `nil` when a bracket nested under the opener rules that out.
    @inline(__always)
    private mutating func matchReferenceLinkForm(bracketTextStart: Int?, cursor: Int, content: borrowing ContentSpan) -> (data: NodeData, end: Int)? {
        let pos = cursor + 1
        // A reference matches only a link reference definition, so without one no label is normalized.
        if storage.referenceMap.isEmpty {
            return nil
        }
        var key = ""
        var afterReference = pos
        if let label = matchLabelKey(from: pos, content: content) {
            key = label.key
            // A whitespace-only `[ ]` is neither a link label nor `[]` (Links), so after a shortcut
            // reference it stays text.
            if !key.isEmpty || label.afterEnd == pos + 2 {
                afterReference = label.afterEnd
            }
        }
        if key.isEmpty, let textStart = bracketTextStart {
            // A link label has at most 999 characters inside its brackets (Links).
            if cursor > textStart, linkLabelFitsLengthCap(virtualRange: textStart..<cursor, in: content) {
                key = normalizeLabel(virtualRange: textStart..<cursor, in: content)
            }
        }
        guard !key.isEmpty, let definition = storage.referenceMap[key] else {
            return nil
        }
        return (.link(url: storage.intern(definition.destination), title: storage.intern(definition.title)), afterReference)
    }

    /// Matches an inline link's `destination "title")` after its `(`, returning the destination and title with backslash escapes and character references resolved, and the offset past the `)`.
    ///
    /// A title may span a line ending, and a destination never does. Each is zero-copy when it lies within one segment and holds no escape, reference or CR.
    @inline(__always)
    private mutating func matchInlineLinkTail(afterParen: Int, content: borrowing ContentSpan) -> (url: Chunk, title: Chunk, end: Int)? {
        let end = content.endOffset
        let destStart = skipWhitespace(from: afterParen, in: content)
        guard let dest = matchLinkDestination(from: destStart, end: end, in: content) else {
            return nil
        }
        let titleStart = skipWhitespace(from: dest.afterEnd, in: content)
        var titleEnd = dest.afterEnd
        var titleInterior = dest.afterEnd..<dest.afterEnd
        if titleStart > dest.afterEnd,
           let title = matchLinkTitle(from: titleStart, end: end, in: content) {
            titleInterior = title.interior
            titleEnd = title.afterEnd
        }
        let close = skipWhitespace(from: titleEnd, in: content)
        guard close < end, content[close] == UInt8(ascii: ")") else {
            return nil
        }
        return (
            unescapedChunk(dest.destination, in: content),
            unescapedTitle(titleInterior, in: content),
            close + 1
        )
    }

    /// The normalized key of the label at `pos`, empty for a blank one, and the offset past its `]`.
    private mutating func matchLabelKey(from pos: Int, content: borrowing ContentSpan) -> (key: String, afterEnd: Int)? {
        let end = content.endOffset
        guard let label = matchLinkLabel(from: pos, end: end, in: content) else {
            return nil
        }
        return (label.interior.isEmpty ? "" : normalizeLabel(virtualRange: label.interior, in: content), label.afterEnd)
    }

    /// Appends a text node holding the `]` at `cursor`, spanning `cursor..<end`.
    private mutating func emitBracketLiteral(at cursor: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) {
        appendInline(.text, .literal(storage.intern(content.chunk(offset: cursor, length: 1))), to: parent, start: cursor, end: end, content: content)
    }

    /// Wraps the nodes after the opener's text in a new `kind` node spanning the virtual range `start..<end`, removes the opener's text, and resolves emphasis inside the new node with the opener's delimiter position as the floor.
    @inline(__always)
    private mutating func wrapBracketContent(_ kind: MarkdownNode.Kind, _ data: NodeData, openerInl: DocumentStorage.Index, delimPosition: Int, start: Int, end: Int, content: borrowing ContentSpan) {
        let wrapper = storage.appendNode(NodeRecord(kind: kind, parent: storage[openerInl].parent, data: data))
        stampInline(wrapper, start, end, content: content)
        storage.insertChildBefore(wrapper, before: openerInl)
        var sibling = storage[openerInl].next
        while let current = sibling {
            sibling = storage[current].next
            storage.unlinkChild(current)
            storage.appendChild(current, to: wrapper)
        }
        storage.unlinkChild(openerInl)
        processEmphasis(stackBottom: delimPosition, content: content)
    }

    // MARK: - Footnote references

    /// The definition the footnote-shaped bracket from `open` to `closeBracket` references, or `nil`. Its label,
    /// everything after the `^`, is normalized as a link label (Links), so it may span a line ending.
    private mutating func footnoteDefinition(referencedFrom open: Int, closeBracket: Int, in content: borrowing ContentSpan) -> DocumentStorage.Index? {
        let labelStart = open + 2
        guard !storage.footnoteMap.isEmpty, labelStart < closeBracket, content[open + 1] == UInt8(ascii: "^"),
              linkLabelFitsLengthCap(virtualRange: labelStart..<closeBracket, in: content) else {
            return nil
        }
        return storage.footnoteMap[normalizeLabel(virtualRange: labelStart..<closeBracket, in: content)]
    }

    /// When the footnote-shaped bracket from `bracketStart` to the `]` at `closeBracket` names a footnote definition,
    /// replaces it with a footnote reference, pops its opener, and returns `true`. An image opener's `!` stays text.
    private mutating func emitFootnoteReferenceIfDefined(openerIdx: Int, bracketStart: Int, closeBracket: Int, content: borrowing ContentSpan) -> Bool {
        guard storage.options.contains(.footnotes),
              let defIdx = footnoteDefinition(referencedFrom: bracketStart, closeBracket: closeBracket, in: content) else {
            return false
        }
        let openerInl = brackets[openerIdx].inlText
        let openerStart = brackets[openerIdx].virtualStart
        // Resolve emphasis inside the bracket first, so removing its nodes leaves no stale delimiters.
        processEmphasis(stackBottom: brackets[openerIdx].delimPosition, content: content)
        emitFootnoteReference(after: openerInl, definition: defIdx, span: bracketStart..<closeBracket + 1, content: content)
        if bracketStart > openerStart {
            storage.trimLiteral(of: openerInl, trimStart: 0, newLength: bracketStart - openerStart)
            stampInline(openerInl, openerStart, bracketStart, content: content)
        } else {
            storage.unlinkChild(openerInl)
        }
        popBracket()
        return true
    }

    /// Replaces the bracket's inner nodes, the siblings after the opener's text, with a `.footnoteReference` to
    /// `definition` over `span`.
    ///
    /// The reference carries the definition's label, so `[^Foo]` resolving to `[^foo]` displays `foo`. Its index is 0
    /// until the footnote pass numbers the finalized tree.
    private mutating func emitFootnoteReference(after openerInl: DocumentStorage.Index, definition defIdx: DocumentStorage.Index, span: Range<Int>, content: borrowing ContentSpan) {
        guard case .footnoteDefinition(let defLabel) = storage[defIdx].data else {
            preconditionFailure("footnoteMap holds only footnote definitions")
        }
        var sib = storage[openerInl].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
        }
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: 0),
            parent: storage[openerInl].parent,
            data: .footnoteReference(label: defLabel)
        ))
        storage.insertChildAfter(fnRefIdx, after: openerInl)
        stampInline(fnRefIdx, span.lowerBound, span.upperBound, content: content)
    }

    // MARK: - Inline attributes (`^[…]`)

    /// The attribute data for the form after the `]` closing an `^[` opener, and the offset past it: an inline `(attrs)`, or a `[label]`.
    ///
    /// A link label, or a collapsed or blank one, belongs to the form whether or not it names an attribute definition; the data is `nil` when it names none, or when no form follows.
    private mutating func matchAttributeForm(cursor: Int, content: borrowing ContentSpan) -> (data: NodeData?, end: Int) {
        let end = content.endOffset
        let pos = cursor + 1
        if pos < end, content[pos] == UInt8(ascii: "("),
           let scanned = matchAttributeAttributes(start: pos + 1, content: content) {
            return (.attribute(storage.intern(scanned.chunk)), scanned.afterEnd)
        }
        if storage.attributeReferenceMap.isEmpty {
            return (nil, matchLinkLabel(from: pos, end: end, in: content)?.afterEnd ?? pos)
        }
        guard let label = matchLabelKey(from: pos, content: content) else {
            return (nil, pos)
        }
        guard !label.key.isEmpty, let attributes = storage.attributeReferenceMap[label.key] else {
            return (nil, label.afterEnd)
        }
        return (.attribute(storage.intern(attributes)), label.afterEnd)
    }

    private struct AttributeAttributesMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Scans an attribute form's `(…)` interior, which may hold whitespace, balanced parentheses, and backslash escapes,
    /// returning it and the offset past the closing `)`.
    private mutating func matchAttributeAttributes(start: Int, content: borrowing ContentSpan) -> AttributeAttributesMatch? {
        let end = content.endOffset
        // No byte ends the run, so a scan that stops before the end stops at the `)` closing the form.
        guard let close = attributeParentheses.balancedEnd(from: start, end: end, byte: { content[$0] }, terminates: { _ in false }),
              close < end else {
            return nil
        }
        return AttributeAttributesMatch(chunk: materializedChunk(start: start, end: close, content: content), afterEnd: close + 1)
    }

    // MARK: - Emphasis / strong (delimiter stack)

    /// A delimiter run on the delimiter stack (Appendix: A parsing strategy), pointing at the `.text` node holding it.
    ///
    /// The stack is a doubly-linked list through `delimiters`; unlinking a record leaves the array, and so other indices, intact.
    /// `processEmphasis` also links the records of each character into a list of their own, so an opener search passes
    /// only delimiters of its closer's character, not those that a quote pair or a `~` pair of unequal lengths leaves on
    /// the stack.
    internal struct DelimiterRecord {
        var character: UInt8
        var length: Int
        var canOpen: Bool
        var canClose: Bool
        var inlText: DocumentStorage.Index
        /// The virtual range of the run's unused delimiters, from which `insertEmph` stamps the emphasis node. The run's text node is in source offsets, so stamping from it would map twice.
        ///
        /// A closer uses delimiters from its start and an opener from its end, so the unused ones stay contiguous.
        var virtualStart: Int
        var virtualEnd: Int
        var previous: Int?
        var next: Int?
        var previousOfCharacter: Int? = nil
        var nextOfCharacter: Int? = nil
    }

    /// The flanking classification of a delimiter run.
    private struct Flanking {
        var leftFlanking: Bool
        var rightFlanking: Bool
        /// The byte before the run, for the quote `]`/`)` rule.
        var beforeChar: UInt8
        /// Whether the bordering characters are punctuation, for the `_` intraword rule.
        var beforeIsPunct: Bool
        var afterIsPunct: Bool
    }

    /// Classifies a delimiter run as left- or right-flanking (Emphasis and strong emphasis).
    private func classifyFlanking(start: Int, runEnd: Int, content: borrowing ContentSpan) -> Flanking {
        let end = content.endOffset
        let contentStart = content.startOffset
        // The content's start and end count as Unicode whitespace (Emphasis and strong emphasis).
        let beforeIdx = start - 1
        let beforeChar: UInt8 = beforeIdx >= contentStart ? content[beforeIdx] : UInt8(ascii: "\n")
        // Flanking is defined over characters, so a multi-byte whitespace or punctuation neighbour counts.
        let beforeScalar: Int32 = beforeIdx >= contentStart
            ? Self.flankingScalarBefore(endingAt: beforeIdx, lowerBound: contentStart, content: content)
            : 0x0A
        let afterScalar: Int32 = runEnd < end
            ? Self.flankingScalarAfter(startingAt: runEnd, content: content)
            : 0x0A
        let beforeClass = Self.characterClass(beforeScalar)
        let afterClass = Self.characterClass(afterScalar)
        let beforeIsSpace = beforeClass == .whitespace
        let beforeIsPunct = beforeClass == .punctuation
        let afterIsSpace = afterClass == .whitespace
        let afterIsPunct = afterClass == .punctuation
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        return Flanking(
            leftFlanking: leftFlanking,
            rightFlanking: rightFlanking,
            beforeChar: beforeChar,
            beforeIsPunct: beforeIsPunct,
            afterIsPunct: afterIsPunct
        )
    }

    /// The scalar whose last byte is at `endIdx`, decoded from its lead byte at or after `lowerBound`.
    @inline(__always)
    private static func flankingScalarBefore(endingAt endIdx: Int, lowerBound: Int, content: borrowing ContentSpan) -> Int32 {
        let last = content[endIdx]
        if last < 0x80 { return Int32(last) }
        var lead = endIdx
        while lead > lowerBound, content[lead] & 0xC0 == 0x80 { lead -= 1 }
        return decodeUTF8Scalar(at: lead, content: content)
    }

    @inline(__always)
    private static func flankingScalarAfter(startingAt idx: Int, content: borrowing ContentSpan) -> Int32 {
        let first = content[idx]
        if first < 0x80 { return Int32(first) }
        return decodeUTF8Scalar(at: idx, content: content)
    }

    /// Decodes the multi-byte scalar whose lead byte is at `idx`. Inline content is valid UTF-8 cut only at
    /// ASCII bytes, so the whole sequence lies inside the content.
    private static func decodeUTF8Scalar(at idx: Int, content: borrowing ContentSpan) -> Int32 {
        let b0 = content[idx]
        precondition(b0 >= 0xC2 && b0 <= 0xF4, "inline content is valid UTF-8, so a decoded scalar starts at a multi-byte lead byte")
        if b0 < 0xE0 {
            return (Int32(b0 & 0x1F) << 6) | Int32(content[idx + 1] & 0x3F)
        }
        if b0 < 0xF0 {
            return (Int32(b0 & 0x0F) << 12) | (Int32(content[idx + 1] & 0x3F) << 6) | Int32(content[idx + 2] & 0x3F)
        }
        return (Int32(b0 & 0x07) << 18) | (Int32(content[idx + 1] & 0x3F) << 12) | (Int32(content[idx + 2] & 0x3F) << 6) | Int32(content[idx + 3] & 0x3F)
    }

    /// The class of a character in the spec's definitions: a Unicode whitespace character, a punctuation character,
    /// or neither (Characters and lines).
    private enum CharacterClass {
        case whitespace
        case punctuation
        case other
    }

    /// The class of `uc`.
    @inline(__always)
    private static func characterClass(_ uc: Int32) -> CharacterClass {
        if uc < 0x80 {
            let b = UInt8(uc)
            return b.isFlankingSpace ? .whitespace : b.isASCIIPunct ? .punctuation : .other
        }
        return nonASCIICharacterClass(uc)
    }

    /// The class of non-ASCII `uc`, from its general category: `Zs` is whitespace and the `P` categories are
    /// punctuation. Out of line, so that the general-category lookup's setup runs only for non-ASCII scalars.
    @inline(never)
    private static func nonASCIICharacterClass(_ uc: Int32) -> CharacterClass {
        switch Unicode.Scalar(UInt32(uc))?.properties.generalCategory {
        case .spaceSeparator:
            return .whitespace
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return .punctuation
        default:
            return .other
        }
    }

    /// Scans the delimiter run at `start`, emits its text unless it can neither open nor close, and pushes a delimiter if it can open or close (Emphasis and strong emphasis) and, for `~`, has a strikethrough length. Returns the offset past the run.
    private mutating func handleDelimRun(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let end = content.endOffset
        var runEnd = start
        while runEnd < end, content[runEnd] == char {
            runEnd += 1
        }

        let count = runEnd - start
        let flanking = classifyFlanking(start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeIsPunct = flanking.beforeIsPunct
        let afterIsPunct = flanking.afterIsPunct
        
        let canOpen: Bool
        let canClose: Bool
        if char == UInt8(ascii: "_") {
            // Rules 2, 4, 6 and 8 (Emphasis and strong emphasis).
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunct)
            canClose = rightFlanking && (!leftFlanking || afterIsPunct)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        if !canOpen && !canClose {
            return runEnd
        }
        // An unpaired delimiter stays literal text with its own source range.
        let textIdx = emitLiteral(.text, content.chunk(offset: start, length: count), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        // Strikethrough (extension) uses two tildes, or one unless `.strikethroughDoubleTilde` is set.
        // Other `~` runs stay literal.
        let pushDelim: Bool
        if char == UInt8(ascii: "~") {
            let doubleTilde = storage.options.contains(.strikethroughDoubleTilde)
            pushDelim = count == 2 || (!doubleTilde && count == 1)
        } else {
            pushDelim = true
        }
        if pushDelim {
            pushDelimiter(char, length: count, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
        }
        return runEnd
    }

    /// Resolves emphasis among the delimiters above `stackBottom` (`-1` for the whole stack), pairing each closer with the nearest compatible opener.
    ///
    /// `openersBottom` records, per closer character, length mod 3 and whether the closer can open, the last closer
    /// whose opener search failed; a later closer of the same kind searches no lower, since the same openers would fail
    /// it (rules 9 and 10).
    private mutating func processEmphasis(stackBottom: Int, content: borrowing ContentSpan) {
        var openersBottom = OpenersBottom(fill: stackBottom)
        // The earliest delimiter above `stackBottom`.
        var closer: Int? = nil
        // The walk runs from the top down, so per character this holds the nearest delimiter above the walker, or -1.
        var laterOfCharacter = SIMD8<Int>(repeating: -1)
        var walker = lastDelim
        while let w = walker, w > stackBottom {
            let wCharIdx = charIndex(for: delimiters[w].character)
            let later = laterOfCharacter[wCharIdx]
            if later >= 0 {
                delimiters[later].previousOfCharacter = w
                delimiters[w].nextOfCharacter = later
            }
            laterOfCharacter[wCharIdx] = w
            closer = w
            walker = delimiters[w].previous
        }
        while let c = closer {
            if !delimiters[c].canClose {
                closer = delimiters[c].next
                continue
            }
            let closerChar = delimiters[c].character
            let charIdx = charIndex(for: closerChar)
            let bottomRow = (delimiters[c].canOpen ? 3 : 0) + delimiters[c].length % 3
            var opener = delimiters[c].previousOfCharacter
            var openerFound = false
            while let o = opener, o > stackBottom,
                  o >= openersBottom[bottomRow, charIdx] {
                if delimiters[o].canOpen {
                    let cl = delimiters[c]
                    let op = delimiters[o]
                    // The multiple-of-3 test of rules 9 and 10 (Emphasis and strong emphasis) applies to `~`
                    // too. A `~` opener need not match the closer's length here: `insertEmph` discards a
                    // mismatched pair, so a closer never reaches past the nearest `~` opener that passes that test.
                    if !(cl.canOpen || op.canClose)
                        || cl.length % 3 == 0
                        || (op.length + cl.length) % 3 != 0 {
                        openerFound = true
                        break
                    }
                }
                opener = delimiters[o].previousOfCharacter
            }
            let oldCloser = c
            if closerChar == UInt8(ascii: "'") || closerChar == UInt8(ascii: "\"") {
                // A quote closer already has its closing glyph from `handleQuoteDelim`. Re-interning it would move its segment to the pool's end, so `consolidateTextNodes` would merge it with its neighbours (the apostrophe in `it's`) by copying their segments instead of widening in place.
                let single = closerChar == UInt8(ascii: "'")
                let next = delimiters[c].next
                if openerFound, let opener {
                    setSmartLiteral(
                        of: delimiters[opener].inlText,
                        single ? Self.leftSingleQuote : Self.leftDoubleQuote
                    )
                    removeDelim(opener)
                    removeDelim(oldCloser)
                }
                closer = next
            } else if openerFound, let opener {
                closer = insertEmph(
                    opener: opener,
                    closer: c,
                    content: content
                )
            } else {
                closer = delimiters[c].next
            }
            if !openerFound {
                openersBottom[bottomRow, charIdx] = oldCloser
                if !delimiters[oldCloser].canOpen {
                    removeDelim(oldCloser)
                }
            }
        }
        while let last = lastDelim, last > stackBottom {
            removeDelim(last)
        }
    }

    private func charIndex(for c: UInt8) -> Int {
        switch c {
        case UInt8(ascii: "_"): return 1
        case UInt8(ascii: "~"): return 2
        case UInt8(ascii: "'"): return 3
        case UInt8(ascii: "\""): return 4
        default: return 0
        }
    }

    /// Wraps the nodes between `opener` and `closer` in an `.emphasis`, `.strong` or `.strikethrough` node, trims the used delimiters, and returns the next closer to process: `closer` again if part of its run remains. A `~` pair of unequal lengths forms no node.
    private mutating func insertEmph(opener: Int, closer: Int, content: borrowing ContentSpan) -> Int? {
        let openerInl = delimiters[opener].inlText
        let closerInl = delimiters[closer].inlText
        let openerChar = delimiters[opener].character
        var openerNumChars = literalLength(of: openerInl)
        var closerNumChars = literalLength(of: closerInl)
        let useDelims: Int
        let kind: MarkdownNode.Kind
        if openerChar == UInt8(ascii: "~") {
            // Strikethrough forms only between runs of equal length. On a mismatch both stay literal and leave
            // the stack, so no farther opener pairs with the closer.
            if openerNumChars != closerNumChars {
                let next = delimiters[closer].next
                removeDelim(closer)
                removeDelim(opener)
                return next
            }
            useDelims = openerNumChars
            kind = .strikethrough
        } else {
            useDelims = (closerNumChars >= 2 && openerNumChars >= 2) ? 2 : 1
            kind = useDelims == 1 ? .emphasis : .strong
        }
        openerNumChars -= useDelims
        closerNumChars -= useDelims
        // A record's `length` stays the original run length, which rules 9 and 10 sum and `openersBottom`
        // is indexed by: `***a****a` nests as Emphasis>Strong because its second pairing sums the runs' lengths
        // 3 and 4, not the 1 and 2 delimiters left. The count still available is the text literal's length.
        storage.trimLiteral(of: openerInl, trimStart: 0, newLength: openerNumChars)
        storage.trimLiteral(of: closerInl, trimStart: useDelims, newLength: closerNumChars)
        // Intervening delimiters go; their text nodes become children of the new node.
        if let previous = delimiters[closer].previous, previous != opener {
            removeDelims(after: opener, through: previous)
        }
        let parentIdx = storage[openerInl].parent
        let emphIdx = storage.appendNode(NodeRecord(kind: kind, parent: parentIdx))
        // The node covers the used delimiters and the content, not the leftover delimiters (`**o*` → `Emphasis @1:2-1:5`).
        let start = delimiters[opener].virtualEnd - useDelims
        let end = delimiters[closer].virtualStart + useDelims
        stampInline(emphIdx, start, end, content: content)
        // The unused delimiters stay text covering only themselves.
        stampInline(openerInl, delimiters[opener].virtualStart, start, content: content)
        stampInline(closerInl, end, delimiters[closer].virtualEnd, content: content)
        delimiters[opener].virtualEnd = start
        delimiters[closer].virtualStart = end
        var sibling = storage[openerInl].next
        while let sibling_ = sibling, sibling_ != closerInl {
            let nextSibling = storage[sibling_].next
            storage.unlinkChild(sibling_)
            storage.appendChild(sibling_, to: emphIdx)
            sibling = nextSibling
        }
        storage.insertChildAfter(emphIdx, after: openerInl)
        var resultCloser: Int? = closer
        if openerNumChars == 0 {
            storage.unlinkChild(openerInl)
            removeDelim(opener)
        }
        if closerNumChars == 0 {
            storage.unlinkChild(closerInl)
            let next = delimiters[closer].next
            removeDelim(closer)
            resultCloser = next
        }
        return resultCloser
    }

    /// Removes the delimiters from `last` back to, but not including, `first`.
    private mutating func removeDelims(after first: Int, through last: Int) {
        var d: Int? = last
        while let dd = d, dd != first {
            let prev = delimiters[dd].previous
            removeDelim(dd)
            d = prev
        }
    }

    private mutating func removeDelim(_ idx: Int) {
        let prev = delimiters[idx].previous
        let next = delimiters[idx].next
        if let prev {
            delimiters[prev].next = next
        }
        if let next {
            delimiters[next].previous = prev
        }
        if idx == lastDelim {
            lastDelim = prev
        }
        let previousOfCharacter = delimiters[idx].previousOfCharacter
        let nextOfCharacter = delimiters[idx].nextOfCharacter
        if let previousOfCharacter {
            delimiters[previousOfCharacter].nextOfCharacter = nextOfCharacter
        }
        if let nextOfCharacter {
            delimiters[nextOfCharacter].previousOfCharacter = previousOfCharacter
        }
    }

    private func literalLength(of nodeIdx: DocumentStorage.Index) -> Int {
        guard case .literal(let ref) = storage[nodeIdx].data else {
            preconditionFailure("a delimiter run's text node holds a literal")
        }
        return ref.totalLength
    }

    // MARK: - Smart punctuation

    /// Smart-punctuation replacement characters.
    static let leftSingleQuote: Unicode.Scalar = "\u{2018}"
    static let rightSingleQuote: Unicode.Scalar = "\u{2019}"
    static let leftDoubleQuote: Unicode.Scalar = "\u{201C}"
    static let rightDoubleQuote: Unicode.Scalar = "\u{201D}"
    static let enDash: Unicode.Scalar = "\u{2013}"
    static let emDash: Unicode.Scalar = "\u{2014}"
    static let ellipsis: Unicode.Scalar = "\u{2026}"

    private mutating func appendToArena(_ s: String) {
        for b in s.utf8 {
            storage.strings.append(b)
        }
    }

    private mutating func appendSmartConstant(_ glyph: Unicode.Scalar) {
        UTF8.encode(glyph) { storage.strings.append($0) }
    }

    /// Appends `glyph` to the arena, returning its chunk.
    private mutating func smartConstantChunk(_ glyph: Unicode.Scalar) -> Chunk {
        let offset = storage.strings.count
        appendSmartConstant(glyph)
        return arenaChunk(from: offset)
    }

    /// Replaces a text node's literal with a constant smart-punctuation glyph.
    private mutating func setSmartLiteral(of nodeIdx: DocumentStorage.Index, _ glyph: Unicode.Scalar) {
        let ref = storage.intern(smartConstantChunk(glyph))
        storage[nodeIdx].data = .literal(ref)
    }

    /// A run of two or more hyphens becomes en and em dashes; a lone hyphen stays pending text.
    private mutating func handleSmartHyphen(start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        let end = content.endOffset
        var runEnd = start
        while runEnd < end,
              content[runEnd] == UInt8(ascii: "-") {
            runEnd += 1
        }
        let numHyphens = runEnd - start
        if numHyphens < 2 {
            // Lone hyphen: leave it in pending text (identical output, no extra node).
            return runEnd
        }
        var enCount = 0
        var emCount = 0
        if numHyphens % 3 == 0 {
            emCount = numHyphens / 3
        } else if numHyphens % 2 == 0 {
            enCount = numHyphens / 2
        } else if numHyphens % 3 == 2 {
            enCount = 1
            emCount = (numHyphens - 2) / 3
        } else {
            enCount = 2
            emCount = (numHyphens - 4) / 3
        }
        let offset = storage.strings.count
        for _ in 0..<emCount {
            appendSmartConstant(Self.emDash)
        }
        for _ in 0..<enCount {
            appendSmartConstant(Self.enDash)
        }
        let chunk = arenaChunk(from: offset)
        emitLiteral(.text, chunk, start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        return runEnd
    }

    /// Emits a `'` or `"` as its initial curly quote and, if it can open or close, pushes a delimiter for `processEmphasis` to pair.
    private mutating func handleQuoteDelim(char: UInt8, start: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        // A quote delimiter is one character.
        let runEnd = start + 1
        let flanking = classifyFlanking(start: start, runEnd: runEnd, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeChar = flanking.beforeChar
        let canOpen = leftFlanking && !rightFlanking && beforeChar != UInt8(ascii: "]") && beforeChar != UInt8(ascii: ")")
        let canClose = rightFlanking
        // `'` starts as an apostrophe; `"` as a closing quote when it can close, otherwise an opening one.
        let literal: Unicode.Scalar
        if char == UInt8(ascii: "'") {
            literal = Self.rightSingleQuote
        } else {
            literal = canClose ? Self.rightDoubleQuote : Self.leftDoubleQuote
        }
        let textIdx = emitLiteral(.text, smartConstantChunk(literal), start: start, end: runEnd, to: parent, pendingTextStart: &pendingTextStart, content: content)
        if canOpen || canClose {
            // A length of 3 makes the multiple-of-3 test always admit a quote pairing.
            pushDelimiter(char, length: 3, canOpen: canOpen, canClose: canClose, inlText: textIdx, range: start..<runEnd)
        }
        return runEnd
    }

    /// Pushes a delimiter run spanning virtual `range` onto the delimiter stack.
    private mutating func pushDelimiter(_ char: UInt8, length: Int, canOpen: Bool, canClose: Bool, inlText: DocumentStorage.Index, range: Range<Int>) {
        let prev = lastDelim
        let newIdx = delimiters.count
        delimiters.append(DelimiterRecord(
            character: char,
            length: length,
            canOpen: canOpen,
            canClose: canClose,
            inlText: inlText,
            virtualStart: range.lowerBound,
            virtualEnd: range.upperBound,
            previous: prev,
            next: nil
        ))
        if let prev {
            delimiters[prev].next = newIdx
        }
        lastDelim = newIdx
    }

    // MARK: - Code spans

    private struct CodeSpanMatch {
        var content: Chunk
        /// The offset just past the closing backtick run.
        var afterClose: Int
        var backtickCount: Int
    }

    /// Matches a code span at the backtick run at `start`, or `nil` if no closing run of equal length follows.
    private mutating func matchCodeSpan(start: Int, content: borrowing ContentSpan) -> CodeSpanMatch? {
        let end = content.endOffset
        let openEnd = scanBacktickRun(start: start, content: content)
        let runLength = openEnd - start
        // Rescanning for every unmatched opener would make a paragraph of distinct-length runs quadratic.
        if backtickRunsSeen.rulesOutCloser(length: runLength, after: openEnd) {
            return nil
        }

        var i = openEnd
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "`") {
                let closeEnd = scanBacktickRun(start: i, content: content)
                let closeLength = closeEnd - i
                if closeLength == runLength {
                    return CodeSpanMatch(content: codeSpanContent(start: openEnd, end: i, content: content), afterClose: closeEnd, backtickCount: runLength)
                }
                i = closeEnd
                continue
            }
            i += 1
        }
        // Runs are recorded in a second walk, taken at most once per pass, so scans that find a closer skip the
        // bookkeeping.
        backtickRunsSeen.scannedToEndFrom = openEnd
        var k = openEnd
        while k < end {
            guard content[k] == UInt8(ascii: "`") else {
                k += 1
                continue
            }
            let runEnd = scanBacktickRun(start: k, content: content)
            backtickRunsSeen.recordRun(length: runEnd - k, start: k)
            k = runEnd
        }
        return nil
    }

    /// The offset past the backtick run at `start`.
    private func scanBacktickRun(start: Int, content: borrowing ContentSpan) -> Int {
        let end = content.endOffset
        var i = start
        while i < end, content[i] == UInt8(ascii: "`") {
            i += 1
        }
        return i
    }

    /// The content of a code span over `start..<end` (Code spans), with line endings converted to spaces and the
    /// one-space strip applied, copied into the arena only if it holds a line ending.
    private mutating func codeSpanContent(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end), contiguous.length == end - start {
            // Content holding a CR is the source itself, whose line endings are written as `\n` first, so that a CRLF
            // becomes one space.
            if contentHoldsCR, let copy = lineFeedCopy(of: contiguous) {
                return trimSingleSpaces(spacingLineEndings(copy))
            }
            var holdsLineEnding = false
            for i in contiguous.range where readByte(at: i, in: contiguous) == UInt8(ascii: "\n") {
                holdsLineEnding = true
                break
            }
            if !holdsLineEnding {
                return trimSingleSpaces(contiguous)
            }
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            let b = content[k]
            storage.strings.append(b == UInt8(ascii: "\n") ? UInt8(ascii: " ") : b)
        }
        return trimSingleSpaces(arenaChunk(from: outOffset))
    }

    /// `chunk`, a copy just made in the arena, with each `\n` replaced by a space.
    private mutating func spacingLineEndings(_ chunk: Chunk) -> Chunk {
        for k in chunk.range where storage.strings[k] == UInt8(ascii: "\n") {
            storage.strings[k] = UInt8(ascii: " ")
        }
        return chunk
    }

    /// The code span one-space strip (Code spans).
    private func trimSingleSpaces(_ chunk: Chunk) -> Chunk {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start < end,
           readByte(at: start, in: chunk) == UInt8(ascii: " "),
           readByte(at: end - 1, in: chunk) == UInt8(ascii: " ") {
            // Verify there's at least one non-space byte strictly between the two enclosing spaces. For 1- and 2-byte runs there are no inner bytes, so the strip rule doesn't apply.
            let innerStart = start + 1
            let innerEnd = end - 1
            var hasNonSpace = false
            if innerStart < innerEnd {
                for j in innerStart..<innerEnd {
                    let b = readByte(at: j, in: chunk)
                    if b != UInt8(ascii: " ") {
                        hasNonSpace = true
                        break
                    }
                }
            }
            if hasNonSpace {
                return chunk.extracting(1..<(chunk.length - 1))
            }
        }
        return chunk
    }

    // MARK: - Line breaks

    private struct LineBreakInfo {
        var isHard: Bool
        var textEnd: Int
    }

    /// Classifies the line ending at `newlineOffset` as a soft or hard line break (Hard line breaks), with where the
    /// pending text ends, before any backslash or trailing spaces and tabs.
    private func classifyLineBreak(at newlineOffset: Int, pendingTextStart: Int, content: borrowing ContentSpan) -> LineBreakInfo {
        if newlineOffset > pendingTextStart {
            let prev = content[newlineOffset - 1]
            if prev == UInt8(ascii: "\\") {
                return LineBreakInfo(isHard: true, textEnd: newlineOffset - 1)
            }
        }
        // Spaces and tabs before a line ending are not text, whatever the break; a line tabulation or form
        // feed is (`a\f\t  \n` keeps `a\f`). The break is hard when the two characters before the line ending
        // are spaces, so `a  \t\n` is soft.
        var textEnd = newlineOffset
        var spacesBeforeLineEnding = 0
        var inSpaceRun = true
        while textEnd > pendingTextStart {
            let prev = content[textEnd - 1]
            if prev == UInt8(ascii: " ") {
                if inSpaceRun { spacesBeforeLineEnding += 1 }
            } else if prev == UInt8(ascii: "\t") {
                inSpaceRun = false
            } else {
                break
            }
            textEnd -= 1
        }
        return LineBreakInfo(isHard: spacesBeforeLineEnding >= 2, textEnd: textEnd)
    }

    // MARK: - Autolinks

    private struct AutolinkMatch {
        /// The bytes between `<` and `>` (the visible text).
        var interior: Range<Int>
        /// The offset just past the closing `>`.
        var afterClose: Int
        var isEmail: Bool
    }

    /// Matches an autolink (Autolinks) at the `<` at `start`.
    private func matchAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        if let uri = matchURIAutolink(start: start, content: content) {
            return uri
        }
        return matchEmailAutolink(start: start, content: content)
    }

    /// A URI autolink (Autolinks).
    private func matchURIAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        if i >= end {
            return nil
        }
        let first = content[i]
        if !first.isASCIILetter {
            return nil
        }
        i += 1
        var schemeChars = 1
        while i < end, schemeChars < 32 {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "+")
                || b == UInt8(ascii: ".")
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
            schemeChars += 1
        }
        // A scheme is 2 to 32 characters (Autolinks).
        if schemeChars < 2 || i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        // An absolute URI excludes ASCII control characters, DEL (0x7F) included.
        let bodyStart = start + 1
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                return AutolinkMatch(
                    interior: bodyStart..<i,
                    afterClose: i + 1,
                    isEmail: false
                )
            }
            if b == UInt8(ascii: "<") || b == UInt8(ascii: " ") || b < 0x20 || b == 0x7F {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// An email autolink (Autolinks).
    private func matchEmailAutolink(start: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        let end = content.endOffset
        var i = start + 1
        let bodyStart = i
        var localChars = 0
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "@") {
                break
            }
            if !isEmailLocalChar(b) {
                return nil
            }
            i += 1
            localChars += 1
        }
        if localChars == 0 || i >= end {
            return nil
        }
        i += 1
        var labelStart = i
        while true {
            if i >= end {
                return nil
            }
            let b = content[i]
            if b == UInt8(ascii: ">") || b == UInt8(ascii: ".") {
                let labelLength = i - labelStart
                if labelLength == 0 || labelLength > 63
                    || content[labelStart] == UInt8(ascii: "-") || content[i - 1] == UInt8(ascii: "-") {
                    return nil
                }
                if b == UInt8(ascii: ">") {
                    break
                }
                labelStart = i + 1
            } else if !(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-")) {
                // Stopping at the first byte no domain holds keeps an unclosed `<local@` from scanning the block.
                return nil
            }
            i += 1
        }
        return AutolinkMatch(
            interior: bodyStart..<i,
            afterClose: i + 1,
            isEmail: true
        )
    }

    private func isEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"),
             UInt8(ascii: "%"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="), UInt8(ascii: "?"),
             UInt8(ascii: "^"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "{"),
             UInt8(ascii: "|"), UInt8(ascii: "}"), UInt8(ascii: "~"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    /// Whether `b` may appear in an extended email autolink's local part (Autolinks (extension)).
    private func isGFMEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    /// Emits a `.link` with one `.text` child for an autolink.
    ///
    /// The text has character references decoded, but not backslash escapes (Backslash escapes). An email's URL gets a `mailto:` prefix; an email admits no `;`, so it holds no reference.
    private mutating func emitAutolink(auto: AutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = unescapedChunk(
            content.chunk(offset: auto.interior.lowerBound, length: auto.interior.count),
            backslashEscapes: false
        )
        let urlChunk = auto.isEmail
            ? materializeAutolinkURL(prefix: "mailto:", start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
            : textChunk
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.interior.lowerBound - 1, end: auto.afterClose, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.interior.lowerBound, end: auto.interior.upperBound, content: content)
    }

    // MARK: - Raw inline HTML

    /// Matches raw HTML (Raw HTML) at the `<` at `start`, returning the offset past its end.
    private mutating func matchInlineHTML(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        let after = start + 1
        if after >= end {
            return nil
        }
        let c = content[after]
        switch c {
        case UInt8(ascii: "!"):
            return matchHTMLBangForm(start: start, content: content)
        case UInt8(ascii: "?"):
            return Self.matchHTMLOpenerToCloser("<?", "?>", start: start, content: content, misses: &htmlCloserMisses.processingInstruction)
        case UInt8(ascii: "/"):
            return matchHTMLTag(nameStart: start + 2, isClosing: true, content: content)
        default:
            return matchHTMLTag(nameStart: after, isClosing: false, content: content)
        }
    }

    /// Matches an open or closing tag (Raw HTML) whose name starts at `nameStart`.
    private func matchHTMLTag(nameStart: Int, isClosing: Bool, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        guard let nameEnd = htmlTagNameEnd(from: nameStart, end: end, byte: { content[$0] }) else {
            return nil
        }
        return htmlTagEnd(afterName: nameEnd, isClosing: isClosing, end: end) { content[$0] }
    }

    /// Matches a `<!`-prefixed form (Raw HTML): a comment, CDATA section or declaration.
    private mutating func matchHTMLBangForm(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        let i = start + 2
        if i >= end {
            return nil
        }
        let next = content[i]
        if next == UInt8(ascii: "-") {
            return matchHTMLComment(start: start, content: content)
        }
        if next == UInt8(ascii: "[") {
            return Self.matchHTMLOpenerToCloser("<![CDATA[", "]]>", start: start, content: content, misses: &htmlCloserMisses.cdata)
        }
        return matchHTMLDeclaration(start: start, content: content)
    }

    /// Matches an HTML comment (Raw HTML).
    private mutating func matchHTMLComment(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        if start + 4 > end {
            return nil
        }
        if content[start + 2] != UInt8(ascii: "-") || content[start + 3] != UInt8(ascii: "-") {
            return nil
        }
        let bodyStart = start + 4
        // <!-->
        if bodyStart < end, content[bodyStart] == UInt8(ascii: ">") {
            return bodyStart + 1
        }
        // <!--->
        if bodyStart + 1 < end, content[bodyStart] == UInt8(ascii: "-"), content[bodyStart + 1] == UInt8(ascii: ">") {
            return bodyStart + 2
        }
        return Self.scanRawHTMLCloser("-->", from: bodyStart, content: content, misses: &htmlCloserMisses.comment)
    }

    /// Matches a declaration (Raw HTML).
    private mutating func matchHTMLDeclaration(start: Int, content: borrowing ContentSpan) -> Int? {
        let end = content.endOffset
        var i = start + 2
        var nameLen = 0
        while i < end {
            let b = content[i]
            if b.isUppercaseASCIILetter {
                nameLen += 1
                i += 1
            } else {
                break
            }
        }
        if nameLen == 0 {
            return nil
        }
        let afterSpaces = skipWhitespace(from: i, in: content)
        if afterSpaces == i {
            return nil
        }
        return Self.scanRawHTMLCloser(">", from: afterSpaces, content: content, misses: &htmlCloserMisses.declaration)
    }

    /// Matches a CDATA section or processing instruction (Raw HTML): the case-sensitive `opener`, then the first `closer`.
    private static func matchHTMLOpenerToCloser(_ opener: String, _ closer: String, start: Int, content: borrowing ContentSpan, misses: inout Range<Int>) -> Int? {
        let end = content.endOffset
        let openerLength = opener.utf8.count
        if start + openerLength > end {
            return nil
        }
        if !bytesEqual(at: start, target: opener.utf8, content: content) {
            return nil
        }
        return scanRawHTMLCloser(closer, from: start + openerLength, content: content, misses: &misses)
    }

    /// The offset past the first `closer` at or after `start`, or `nil`.
    ///
    /// A failing scan records in `misses` that every start from `start` fails, since a later start sees a subset of the same bytes and the same content end.
    private static func scanRawHTMLCloser(
        _ closer: String, from start: Int, content: borrowing ContentSpan, misses: inout Range<Int>
    ) -> Int? {
        let end = content.endOffset
        if misses.contains(start) {
            return nil
        }
        let width = closer.utf8.count
        var i = start
        while i + width <= end {
            if bytesEqual(at: i, target: closer.utf8, content: content) {
                return i + width
            }
            i += 1
        }
        misses = start..<Int.max
        return nil
    }

    // MARK: - Extended autolinks

    /// An extended autolink's visible text range, and the scheme its destination adds before that text: `http://`
    /// for an extended www autolink, `mailto:` for an email unless a `mailto:` or `xmpp:` scheme was folded into it or into the
    /// address a second `@` restarted it from, and nothing otherwise.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var destinationPrefix: String
    }

    /// Matches an extended url or www autolink at `cursor`. Emails are matched by `gfmEmailAutolinkPass`.
    private mutating func matchGFMAutolink(trigger: UInt8, cursor: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        if trigger == UInt8(ascii: ":") {
            return matchGFMSchemeAutolink(
                colon: cursor, content: content
            )
        }
        precondition(trigger == UInt8(ascii: "w"), "a GFM autolink trial is dispatched only on `:` or `w`")
        return matchGFMWWWAutolink(
            start: cursor, content: content
        )
    }

    /// Matches an `http://`, `https://` or `ftp://` extended autolink whose `:` is at `colon`.
    private mutating func matchGFMSchemeAutolink(colon: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let contentStart = content.startOffset
        if colon + 3 >= end {
            return nil
        }
        if content[colon + 1] != UInt8(ascii: "/") || content[colon + 2] != UInt8(ascii: "/") {
            return nil
        }
        guard let schemeStart = matchSchemeBackward(colon: colon, content: content) else {
            return nil
        }
        // The scheme is the whole run of ASCII letters before `://`, so a letter before `http` makes the scheme
        // something else (`xhttp://a.b` is text). Any other character may precede it.
        if schemeStart > contentStart, content[schemeStart - 1].isASCIILetter {
            return nil
        }
        guard schemeURLDomainAccepted(afterSlashes: colon + 3, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: colon + 3, content: content)
        let trimmedEnd = trimTrailingPunctuation(urlStart: schemeStart, urlEnd: urlEnd, content: content)
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            destinationPrefix: ""
        )
    }

    /// The start of a case-insensitive `http`, `https` or `ftp` ending just before `colon`.
    private mutating func matchSchemeBackward(colon: Int, content: borrowing ContentSpan) -> Int? {
        let contentStart = content.startOffset
        if colon - 5 >= contentStart,
           Self.bytesEqual(at: colon - 5, target: Self.httpsScheme, content: content, ignoringASCIICase: true) {
            return colon - 5
        }
        if colon - 4 >= contentStart,
           Self.bytesEqual(at: colon - 4, target: Self.httpScheme, content: content, ignoringASCIICase: true) {
            return colon - 4
        }
        if colon - 3 >= contentStart,
           Self.bytesEqual(at: colon - 3, target: Self.ftpScheme, content: content, ignoringASCIICase: true) {
            return colon - 3
        }
        return nil
    }

    /// `w`-triggered: matches `www.` followed by a URL body.
    private mutating func matchGFMWWWAutolink(start: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let end = content.endOffset
        let contentStart = content.startOffset
        if start > contentStart {
            let pre = content[start - 1]
            if !isValidWWWPreceding(pre) {
                return nil
            }
        }
        if start + 4 > end {
            return nil
        }
        if !Self.bytesEqual(at: start, target: Self.wwwPrefix, content: content) {
            return nil
        }
        guard domainAccepted(base: start, requirePeriod: true, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: start + 4, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, destinationPrefix: "http://")
    }

    /// The length of lowercase `scheme` (`mailto:` or `xmpp:`) ending at `colon`, when it lies within
    /// `localBound...colon` and starts at `localBound` or after a non-alphanumeric byte, so it folds into an
    /// extended email autolink.
    private func matchEmailScheme(_ scheme: String, colon: Int, localBound: Int, content: borrowing ContentSpan) -> Int? {
        let len = scheme.utf8.count
        let schemeStart = colon + 1 - len
        if schemeStart < localBound {
            return nil
        }
        if !Self.bytesEqual(at: schemeStart, target: scheme.utf8, content: content) {
            return nil
        }
        if schemeStart == localBound {
            return len
        }
        let prev = content[schemeStart - 1]
        if prev.isASCIILetter || prev.isASCIIDigit {
            return nil
        }
        return len
    }

    /// Matches an extended email autolink around the `@` at `at`, scanning back no further than `localBound`:
    /// the content start, or the end of the previous candidate.
    ///
    /// On failure `resumeAt` is past everything scanned, and every `@` before it is settled, so the pass stays
    /// linear on `@`-dense input.
    private mutating func matchGFMEmailAutolink(at: Int, localBound: Int, content: borrowing ContentSpan, resumeAt: inout Int) -> GFMAutolinkMatch? {
        let end = content.endOffset
        // A second `@` in the domain restarts the trial there, the run between becoming the local part. The
        // scheme state and the period flag carry across the restart.
        var atSign = at
        var schemeFolded = false
        var isXmpp = false
        var hasPeriodBeforeAlphanumeric = false
        while true {
            // A `:` completing a lowercase `mailto:` or `xmpp:` at a boundary folds the scheme into the link.
            var localStart = atSign
            while localStart > localBound {
                let b = content[localStart - 1]
                if isGFMEmailLocalChar(b) {
                    localStart -= 1
                    continue
                }
                if b == UInt8(ascii: ":") {
                    if let len = matchEmailScheme("mailto:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        localStart -= len
                        continue
                    }
                    if let len = matchEmailScheme("xmpp:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        isXmpp = true
                        localStart -= len
                        continue
                    }
                }
                break
            }
            // Without a local part or a folded scheme this `@` is no email. A folded scheme alone suffices, so
            // `mailto:@a.b` is accepted.
            if localStart == atSign {
                resumeAt = atSign + 1
                return nil
            }
            // The domain is ASCII alphanumerics, `-`, `_`, and periods followed by an alphanumeric, with `/`
            // too after `xmpp:`.
            var i = atSign + 1
            var sawSecondAt = false
            while i < end {
                let b = content[i]
                if b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") {
                    i += 1
                } else if b == UInt8(ascii: "."), i + 1 < end, content[i + 1].isASCIILetter || content[i + 1].isASCIIDigit {
                    hasPeriodBeforeAlphanumeric = true
                    i += 1
                } else if b == UInt8(ascii: "/"), isXmpp {
                    i += 1
                } else {
                    sawSecondAt = b == UInt8(ascii: "@")
                    break
                }
            }
            if sawSecondAt {
                atSign = i
                continue
            }
            resumeAt = i
            // The domain ends in a letter, and it or a domain before a restart holds a period.
            guard i > atSign + 1, hasPeriodBeforeAlphanumeric, content[i - 1].isASCIILetter else {
                return nil
            }
            return GFMAutolinkMatch(urlStart: localStart, urlEnd: i, destinationPrefix: schemeFolded ? "" : "mailto:")
        }
    }

    /// Emits a `.link` with one `.text` child for an extended url or www autolink.
    private mutating func emitGFMAutolink(auto: GFMAutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = content.chunk(
            offset: auto.urlStart,
            length: auto.urlEnd - auto.urlStart
        )
        let urlChunk = auto.destinationPrefix.isEmpty
            ? textChunk
            : materializeAutolinkURL(prefix: auto.destinationPrefix, start: auto.urlStart, end: auto.urlEnd, content: content)
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = appendInline(.link, .link(url: urlRef, title: .empty), to: parent, start: auto.urlStart, end: auto.urlEnd, content: content)
        appendInline(.text, .literal(textRef), to: linkIdx, start: auto.urlStart, end: auto.urlEnd, content: content)
    }

    /// Appends `prefix` and the content bytes `start..<end` to the arena, returning their chunk.
    private mutating func materializeAutolinkURL(prefix: String, start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        let offset = storage.strings.count
        appendToArena(prefix)
        for j in start..<end {
            storage.strings.append(content[j])
        }
        return arenaChunk(from: offset)
    }

    /// Scans to a URL boundary: a space, tab, line ending or `<`. `>`, line tabulation and form feed are URL bytes.
    private func scanGFMURLBody(
        start: Int,
        content: borrowing ContentSpan
    ) -> Int {
        let end = content.endOffset
        var i = start
        while i < end {
            let b = content[i]
            if b.isSpaceTabOrLineEnding || b == UInt8(ascii: "<") {
                break
            }
            i += 1
        }
        return i
    }

    /// Trims an extended autolink's trailing punctuation (Autolinks (extension)), right to left: `? ! . , : * _ ~ ' "`
    /// one at a time, a `)` only while the URL holds more `)` than `(`, and at a `;` a whole `&letters;` entity
    /// tail, or else just the `;`.
    private func trimTrailingPunctuation(urlStart: Int, urlEnd: Int, content: borrowing ContentSpan) -> Int {
        var opening = 0
        var closing = 0
        for j in urlStart..<urlEnd {
            switch content[j] {
            case UInt8(ascii: "("): opening += 1
            case UInt8(ascii: ")"): closing += 1
            default: break
            }
        }

        var i = urlEnd
        trim: while i > urlStart {
            switch content[i - 1] {
            case UInt8(ascii: ")"):
                if closing <= opening {
                    break trim
                }
                closing -= 1
                i -= 1
            case UInt8(ascii: "?"), UInt8(ascii: "!"), UInt8(ascii: "."), UInt8(ascii: ","),
                 UInt8(ascii: ":"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"),
                 UInt8(ascii: "'"), UInt8(ascii: "\""):
                i -= 1
            case UInt8(ascii: ";"):
                // An entity tail needs at least one letter, so `&;` peels only the `;`.
                var entityStart = i - 2
                while entityStart > urlStart, content[entityStart].isASCIILetter {
                    entityStart -= 1
                }
                if entityStart < i - 2, content[entityStart] == UInt8(ascii: "&") {
                    i = entityStart
                } else {
                    i -= 1
                }
            default:
                break trim
            }
        }
        return i
    }

    /// Whether the domain of an extended www or url autolink at `base` is accepted.
    ///
    /// The scan runs from the domain's second character, the first being checked by the caller, over host
    /// characters, `-`, `_` and `.`, up to the first other character or the content's last character, which it
    /// never examines. A backslash makes it examine the next character instead. An underscore in either of the
    /// last two period-separated segments rejects the domain unless the scan passed more than ten periods.
    /// `requirePeriod` also demands a period.
    private mutating func domainAccepted(base: Int, requirePeriod: Bool, content: borrowing ContentSpan) -> Bool {
        let end = content.endOffset
        let size = end - base
        var periods = 0
        var underscoresInPreviousSegment = 0
        var underscoresInLastSegment = 0
        var i = 1
        while i < size - 1 {
            if content[base + i] == UInt8(ascii: "\\"), i < size - 2 {
                i += 1
            }
            let b = content[base + i]
            if b == UInt8(ascii: "_") {
                underscoresInLastSegment += 1
            } else if b == UInt8(ascii: ".") {
                underscoresInPreviousSegment = underscoresInLastSegment
                underscoresInLastSegment = 0
                periods += 1
            } else if !isHostByte(b) && b != UInt8(ascii: "-") {
                break
            }
            i += 1
        }
        if (underscoresInPreviousSegment > 0 || underscoresInLastSegment > 0) && periods <= 10 {
            return false
        }
        return !requirePeriod || periods > 0
    }

    /// Whether an extended url autolink's domain at `afterSlashes` is accepted: its first character is a host
    /// character or a non-ASCII character that is neither whitespace nor punctuation, and `domainAccepted`
    /// accepts the rest.
    private mutating func schemeURLDomainAccepted(afterSlashes: Int, content: borrowing ContentSpan) -> Bool {
        let first = content[afterSlashes]
        if first < 0x80 {
            if !isHostByte(first) {
                return false
            }
        } else {
            let scalar = Self.decodeUTF8Scalar(at: afterSlashes, content: content)
            if Self.characterClass(scalar) != .other {
                return false
            }
        }
        return domainAccepted(base: afterSlashes, requirePeriod: false, content: content)
    }

    /// Whether `b` is a host character: ASCII other than punctuation, space, tab, line ending or form feed.
    private func isHostByte(_ b: UInt8) -> Bool {
        b < 0x80 && !b.isASCIIPunct && (b == 0x0B || !b.isWhitespaceCharacter)
    }

    /// Characters that may directly precede an extended www autolink: space, tab, line feed, carriage return, `*`,
    /// `_`, `~` and `(`.
    private func isValidWWWPreceding(_ b: UInt8) -> Bool {
        if b.isSpaceTabOrLineEnding {
            return true
        }
        switch b {
        case UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "("):
            return true
        default:
            return false
        }
    }

    /// The autolink prefixes, as UTF-8 bytes.
    private static let httpsScheme = Array("https".utf8)
    private static let httpScheme = Array("http".utf8)
    private static let ftpScheme = Array("ftp".utf8)
    private static let wwwPrefix = Array("www.".utf8)

    /// Whether `target` is at `start`, ignoring ASCII case if `ignoringASCIICase`.
    private static func bytesEqual(at start: Int, target: some Collection<UInt8>, content: borrowing ContentSpan, ignoringASCIICase: Bool = false) -> Bool {
        let mask: UInt8 = ignoringASCIICase ? 0x20 : 0
        for (k, targetByte) in target.enumerated() {
            if (content[start + k] | mask) != (targetByte | mask) {
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    /// Appends `count` bytes to `out`, returning their chunk.
    private static func appendUTF8Bytes(bytes: Bytes8, count: Int, into out: inout UniqueArray<UInt8>) -> Chunk {
        let offset = out.count
        for i in 0..<count {
            out.append(bytes[i])
        }
        return Chunk(offset: offset, length: count, inSource: false)
    }

    /// Emits a `.text` node over `start..<end` if non-empty. Every line join is a line break, which flushes the run, so it lies within one segment.
    private mutating func flushPendingText(start: Int, end: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        if end <= start {
            return
        }
        guard let chunk = content.contiguousChunk(fromVirtual: start, limit: end), chunk.length == end - start else {
            preconditionFailure("a text run lies within one segment")
        }
        appendInline(.text, .literal(storage.intern(chunk)), to: parent, start: start, end: end, content: content)
    }

    /// Appends an inline node to `parent`, stamped with the source range of the virtual range `start..<end`.
    @discardableResult
    private mutating func appendInline(_ kind: MarkdownNode.Kind, _ data: NodeData?, to parent: DocumentStorage.Index, start: Int, end: Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        let idx = storage.appendNode(NodeRecord(kind: kind, parent: parent, data: data))
        storage.appendChild(idx, to: parent)
        stampInline(idx, start, end, content: content)
        return idx
    }

    /// Flushes the pending text before `start`, then appends a `kind` node with literal `chunk` over `start..<end`. Pending text resumes at `end`.
    @discardableResult
    private mutating func emitLiteral(_ kind: MarkdownNode.Kind, _ chunk: Chunk, start: Int, end: Int, to parent: DocumentStorage.Index, pendingTextStart: inout Int, content: borrowing ContentSpan) -> DocumentStorage.Index {
        flushPendingText(start: pendingTextStart, end: start, content: content, into: parent)
        pendingTextStart = end
        return appendInline(kind, .literal(storage.intern(chunk)), to: parent, start: start, end: end, content: content)
    }

    /// A chunk for `start..<end`, copied into the arena only when the range spans segments, as raw HTML or attributes
    /// can, or holds a CR, so that each line ending is `\n`.
    mutating func materializedChunk(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end),
           contiguous.length == end - start {
            if contentHoldsCR, let copy = lineFeedCopy(of: contiguous) {
                return copy
            }
            return contiguous
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            storage.strings.append(content[k])
        }
        return arenaChunk(from: outOffset)
    }

    /// Stamps `node`'s source range from virtual offsets `start..<end`.
    ///
    /// The last byte, `end - 1`, is resolved, so an `end` at a line join maps to just past the preceding source byte.
    @inline(__always)
    mutating func stampInline(_ node: DocumentStorage.Index, _ start: Int, _ end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, end > start else {
            return
        }
        storage.setSourceStart(node, lineEndingStart(content.sourceOffset(ofVirtual: start)))
        storage.setSourceEnd(node, content.sourceOffset(ofVirtual: end - 1) + 1)
    }

    /// Merges adjacent `.text` children throughout `root`'s inline subtree, such as the separate nodes that smart punctuation and character references emit.
    mutating func consolidateTextNodes(_ root: DocumentStorage.Index) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            if storage[current].kind.isText {
                while let next = storage[current].next, storage[next].kind.isText {
                    mergeTextNode(next, into: current)
                }
            } else {
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = storage[current].next
        }
    }

    /// Writes each line ending in the text of `root`'s inline subtree as `\n`, copying each text node that holds a CR into
    /// the arena once the text is final, after the email autolink pass has split it.
    mutating func writeLineEndingsAsLineFeeds(inTextOf root: DocumentStorage.Index) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            guard storage[current].kind.isText else {
                parent = current
                child = storage[current].firstChild
                continue
            }
            guard case .literal(let ref) = storage[current].data else {
                preconditionFailure("a text node holds a literal")
            }
            if sourceSegmentsHoldCR(ref) {
                let offset = storage.strings.count
                for i in 0..<ref.count {
                    let chunk = storage.segments[ref.first + i].chunk
                    if chunk.inSource {
                        appendWritingLineEndingsAsLineFeeds(chunk.range)
                    } else {
                        // A CR decoded from a character reference is text, not a line ending. The arena can't be read
                        // through a span while it grows, so its bytes are copied one at a time.
                        for k in chunk.range {
                            storage.strings.append(storage.strings[k])
                        }
                    }
                }
                storage[current].data = .literal(storage.intern(arenaChunk(from: offset)))
            }
            child = storage[current].next
        }
    }

    /// Whether any of `ref`'s source segments holds a CR.
    private func sourceSegmentsHoldCR(_ ref: ContentRef) -> Bool {
        for i in 0..<ref.count {
            let chunk = storage.segments[ref.first + i].chunk
            if chunk.inSource, firstCR(in: chunk.range) < chunk.range.upperBound {
                return true
            }
        }
        return false
    }

    /// Appends copies of `ref`'s segments to the pool.
    private mutating func appendSegments(of ref: ContentRef) {
        for i in 0..<ref.count {
            let seg = storage.segments[ref.first + i]
            storage.segments.append(seg)
        }
    }

    /// Merges `source` into the preceding text node `dest` and unlinks it.
    private mutating func mergeTextNode(_ source: DocumentStorage.Index, into dest: DocumentStorage.Index) {
        guard case .literal(let destRef) = storage[dest].data,
              case .literal(let srcRef) = storage[source].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Pool-contiguous runs widen in place. A destination ending the pool grows by copies of the source's segments
        // alone, since re-copying it per sibling would make a long run quadratic. Otherwise both are copied to the pool end.
        let isContiguous = destRef.first + destRef.count == srcRef.first
        let endsPool = destRef.first + destRef.count == storage.segments.count
        let first = isContiguous || endsPool ? destRef.first : storage.segments.count
        if !isContiguous {
            if !endsPool {
                appendSegments(of: destRef)
            }
            appendSegments(of: srcRef)
        }
        storage[dest].data = .literal(ContentRef(
            first: first,
            count: destRef.count + srcRef.count,
            totalLength: destRef.totalLength + srcRef.totalLength
        ))
        if positionsEnabled {
            let a = storage.sourceRanges[dest]
            let b = storage.sourceRanges[source]
            precondition(a.start >= 0 && b.start >= 0, "with `.sourcePosition`, every text node is stamped before it consolidates")
            // From the first node's start to the last node's end, which differs from the union only when an earlier node ends past the last.
            storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                start: a.start,
                end: b.end
            )
        }
        storage.unlinkChild(source)
    }

    // MARK: - Extended email autolink pass

    /// Finds extended email autolinks after emphasis resolution and `consolidateTextNodes`, splitting each text node
    /// outside a link at each address. A `_` or `*` beside an email is therefore resolved before the email's boundaries are.
    ///
    /// `image` maps the leaf's content to the source when it is a single arena chunk.
    mutating func gfmEmailAutolinkPass(_ root: DocumentStorage.Index, image: ContentImage?) {
        var parent = root
        var child = storage[root].firstChild
        while true {
            guard let current = child else {
                guard storage.ascend(from: &parent, resumingAt: &child, within: root) else {
                    return
                }
                continue
            }
            // Taken before the split, so resuming here skips the nodes the split inserts.
            let next = storage[current].next
            switch storage[current].kind {
            case .text:
                splitEmailsInTextNode(current, parent: parent, image: image)
            case .link:
                // Links may not contain other links (Links).
                break
            default:
                parent = current
                child = storage[current].firstChild
                continue
            }
            child = next
        }
    }

    /// Splits a text node into `[before, link, after]` at each extended email autolink.
    ///
    /// The content is scanned left to right, in place when it is one source segment and otherwise from a copy made
    /// once; the text runs are carved from the node's segments. The link spans the address's source bytes, and each
    /// text run keeps the part of the node's range on its side, so a run that isn't all source bytes, such as a smart
    /// quote, still has a range.
    private mutating func splitEmailsInTextNode(_ node: DocumentStorage.Index, parent: DocumentStorage.Index, image: ContentImage?) {
        guard case .literal(let ref) = storage[node].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Most text nodes have no `@`.
        if !contentRefContains(ref, byte: UInt8(ascii: "@")) {
            return
        }
        // `content` borrows the source or `scratch`, never the arena, which the storage mutations below grow.
        // Content of several segments is joined in `scratch` too, so it is read as one span.
        let firstChunk = storage.segments[ref.first].chunk
        let inPlace = ref.count == 1 && firstChunk.inSource
        var copy = UniqueArray<UInt8>()
        if !inPlace {
            materialize(ref, into: &copy)
        }
        let scratch = copy
        let content = inPlace
            ? ContentSpan(span: sourceBytes.extracting(firstChunk.range), base: firstChunk.offset, inSource: true)
            : ContentSpan(span: scratch.span, base: 0, inSource: false)
        // A content offset less `origin` is the offset into `ref`'s content.
        let origin = content.startOffset
        let total = content.endOffset

        // `current` is the running text node, starting at `segStart`. `localBound` keeps a later `@`'s local part
        // out of a prior email.
        var current = node
        var segStart = origin
        var localBound = origin
        var carve = ContentRefCarvePosition()
        var didSplit = false
        var i = origin
        var resumeAt = origin
        // The split node's end, which the last text run keeps.
        let nodeEnd = positionsEnabled ? storage.sourceRanges[node].end : -1
        while i < total {
            guard content[i] == UInt8(ascii: "@") else {
                i += 1
                continue
            }
            guard let auto = matchGFMEmailAutolink(
                at: i, localBound: localBound, content: content, resumeAt: &resumeAt
            ) else {
                // `resumeAt > i`, skipping every `@` the trial settled. `localBound` moves too, or a `+` or `.`
                // that ended the domain would pull the abandoned candidate into the next local part.
                localBound = resumeAt
                i = resumeAt
                continue
            }
            // `current` becomes the text run before this email.
            let beforeRef = subContentRef(of: ref, from: segStart - origin, to: auto.urlStart - origin, resumingAt: &carve)
            storage[current].data = .literal(beforeRef)
            let emailRef = subContentRef(of: ref, from: auto.urlStart - origin, to: auto.urlEnd - origin, resumingAt: &carve)
            let email = positionsEnabled ? sourceSpan(of: emailRef, image: image) : nil
            if let email {
                let currentStart = storage.sourceRanges[current].start
                precondition(currentStart >= 0, "a text run is placed before an address splits it")
                storage.setSourceStart(current, min(currentStart, email.start))
                storage.setSourceEnd(current, email.start)
            }

            // With a folded scheme the visible run is the destination, joined in the arena if it is several
            // segments, since a URL is read as one span. A plain email gets `mailto:`.
            let urlRef = auto.destinationPrefix.isEmpty && emailRef.count == 1
                ? emailRef
                : materializeURL(prefix: auto.destinationPrefix, for: emailRef)
            let linkIdx = storage.appendNode(NodeRecord(
                kind: .link, parent: parent, data: .link(url: urlRef, title: .empty)))
            let childIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: linkIdx, data: .literal(emailRef)))
            storage.appendChild(childIdx, to: linkIdx)
            storage.insertChildAfter(linkIdx, after: current)
            if let email {
                for idx in [linkIdx, childIdx] {
                    storage.setSourceStart(idx, email.start)
                    storage.setSourceEnd(idx, email.end)
                }
            }

            // A fresh tail node becomes the running text node. Its content is carved once its end is known, since
            // carving the whole tail per address would re-copy a long run's segments each time.
            let tailIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: parent, data: .literal(.empty)))
            storage.insertChildAfter(tailIdx, after: linkIdx)
            if let email {
                storage.setSourceStart(tailIdx, email.end)
                storage.setSourceEnd(tailIdx, max(nodeEnd, email.end))
            }

            if beforeRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
            current = tailIdx
            segStart = auto.urlEnd
            localBound = auto.urlEnd
            i = auto.urlEnd
            didSplit = true
        }
        if didSplit {
            let afterRef = subContentRef(of: ref, from: segStart - origin, to: total - origin, resumingAt: &carve)
            storage[current].data = .literal(afterRef)
            if afterRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
        }
    }

    /// Whether any content byte of `ref` is `target`.
    private func contentRefContains(_ ref: ContentRef, byte target: UInt8) -> Bool {
        for s in 0..<ref.count {
            let chunk = storage.segments[ref.first + s].chunk
            // Every text node is scanned, so the bytes are chosen once per segment rather than per byte, and indexed from
            // zero, which keeps the per-byte loop free of overflow checks.
            let bytes = (chunk.inSource ? sourceBytes : storage.strings.span).extracting(chunk.range)
            for k in 0..<bytes.count where bytes[k] == target { return true }
        }
        return false
    }

    /// Copies `ref`'s content bytes into `out`.
    private func materialize(_ ref: ContentRef, into out: inout UniqueArray<UInt8>) {
        for s in 0..<ref.count {
            let chunk = storage.segments[ref.first + s].chunk
            for k in chunk.range { out.append(readByte(at: k, in: chunk)) }
        }
    }

    /// Where the next of a left-to-right series of `subContentRef` carves resumes: the index within the ref of a
    /// segment beginning at or before the carve, and that segment's content offset.
    private struct ContentRefCarvePosition {
        var segment = 0
        var start = 0
    }

    /// Carves `lo..<hi` of `ref`'s content into new segments over the same bytes.
    ///
    /// Resuming from `position`, carves that never start before an earlier carve's end visit each segment of `ref` a
    /// bounded number of times in total.
    private mutating func subContentRef(of ref: ContentRef, from lo: Int, to hi: Int, resumingAt position: inout ContentRefCarvePosition) -> ContentRef {
        if hi <= lo {
            return .empty
        }
        precondition(position.start <= lo, "a carve starts at or after the segment it resumes from")
        let refFirst = ref.first
        let refCount = ref.count
        let newFirst = storage.segments.count
        var count = 0
        var total = 0
        var v = position.start
        for s in position.segment..<refCount {
            let seg = storage.segments[refFirst + s]
            let segLen = seg.length
            let segStart = v
            if segStart >= hi {
                break
            }
            position = ContentRefCarvePosition(segment: s, start: segStart)
            v += segLen
            let pieceLo = max(lo, segStart)
            let pieceHi = min(hi, v)
            if pieceHi <= pieceLo {
                continue
            }
            let localOffset = pieceLo - segStart
            let pieceLen = pieceHi - pieceLo
            storage.segments.append(Segment(
                offset: seg.offset + localOffset,
                length: pieceLen,
                inSource: seg.inSource
            ))
            count += 1
            total += pieceLen
        }
        precondition(count > 0, "a non-empty sub-range of a text node overlaps at least one of its segments")
        return ContentRef(first: newFirst, count: count, totalLength: total)
    }

    /// Copies `prefix` and `emailRef`'s bytes into the arena as one chunk, through a local buffer because they may be
    /// in the arena.
    private mutating func materializeURL(prefix: String, for emailRef: ContentRef) -> ContentRef {
        var buf = UniqueArray<UInt8>()
        for b in prefix.utf8 {
            buf.append(b)
        }
        materialize(emailRef, into: &buf)
        let offset = storage.strings.count
        for k in 0..<buf.count {
            storage.strings.append(buf[k])
        }
        return storage.intern(Chunk(offset: offset, length: buf.count, inSource: false))
    }

    /// The source extent of non-empty `ref`, from what its first byte stands for to what its last does.
    private mutating func sourceSpan(of ref: ContentRef, image: ContentImage?) -> (start: Int, end: Int) {
        precondition(ref.count > 0 && ref.totalLength > 0, "an email address holds at least one byte")
        let firstSeg = storage.segments[ref.first]
        let lastSeg = storage.segments[ref.first + ref.count - 1]
        let first = sourceRange(of: firstSeg, local: 0, image: image)
        let last = sourceRange(of: lastSeg, local: lastSeg.length - 1, image: image)
        return (first.lowerBound, last.upperBound)
    }

    /// The source bytes that byte `local` of an address's segment `seg` stands for: a source byte, an arena byte
    /// imaged by `image`, or the character reference it was decoded from. Other arena text is smart punctuation, which
    /// no address holds.
    private func sourceRange(of seg: Segment, local: Int, image: ContentImage?) -> Range<Int> {
        if seg.inSource {
            let offset = seg.offset + local
            return offset..<(offset + 1)
        }
        let arena = seg.offset + local
        if let offset = image?.sourceOffset(ofArenaByte: arena) {
            return offset..<(offset + 1)
        }
        return characterReferenceSource(ofArenaByte: arena)
    }

    /// The source range of the character reference decoded into arena byte `offset` in this pass.
    private func characterReferenceSource(ofArenaByte offset: Int) -> Range<Int> {
        var lo = 0
        var hi = characterReferenceSources.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if characterReferenceSources[mid].arena.upperBound > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        precondition(lo < characterReferenceSources.count && characterReferenceSources[lo].arena.contains(offset), "an address's arena byte outside the leaf's content comes from a character reference")
        return characterReferenceSources[lo].source
    }
}
