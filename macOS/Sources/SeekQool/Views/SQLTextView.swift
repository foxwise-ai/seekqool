import SwiftUI
import AppKit

struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var errorRange: NSRange?
    @Binding var cursorPosition: Int
    @Binding var triggerCompletion: Bool
    var onInsertCompletion: ((String, Int) -> Void)?
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.backgroundColor = NSColor.textBackgroundColor

        // Set up text storage delegate for live highlighting
        textView.textStorage?.delegate = context.coordinator

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text actually changed from outside
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.applyHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
        }

        // Update error squiggle
        context.coordinator.updateErrorSquiggle(textView: textView, errorRange: errorRange)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: SQLTextView
        weak var textView: NSTextView?
        private var isHighlighting = false

        init(_ parent: SQLTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            // Update cursor position
            if let selection = textView.selectedRanges.first as? NSRange {
                parent.cursorPosition = selection.location
            }

            // Check if we should trigger completion (after typing . or starting a word)
            let cursorPos = textView.selectedRange().location
            if cursorPos > 0 {
                let text = textView.string
                let index = text.index(text.startIndex, offsetBy: cursorPos - 1, limitedBy: text.endIndex) ?? text.endIndex
                if index < text.endIndex {
                    let lastChar = text[index]
                    if lastChar == "." {
                        parent.triggerCompletion = true
                    }
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let selection = textView.selectedRanges.first as? NSRange {
                parent.cursorPosition = selection.location
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Escape to dismiss completion
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.triggerCompletion = false
                return false
            }
            return false
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !isHighlighting else { return }

            // Delay highlighting to avoid modifying text storage during editing
            DispatchQueue.main.async { [weak self] in
                guard let textView = self?.textView else { return }
                self?.applyHighlighting(to: textView)
            }
        }

        func applyHighlighting(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            isHighlighting = true
            defer { isHighlighting = false }

            let text = textStorage.string
            let fullRange = NSRange(location: 0, length: text.utf16.count)

            // Reset to default style
            textStorage.beginEditing()
            textStorage.removeAttribute(.foregroundColor, range: fullRange)
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textStorage.addAttribute(.font, value: parent.font, range: fullRange)

            // Apply SQL highlighting
            SQLHighlighter.highlight(textStorage: textStorage, text: text)

            textStorage.endEditing()
        }

        func updateErrorSquiggle(textView: NSTextView, errorRange: NSRange?) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)

            // Remove existing squiggles
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)

            // Add error squiggle if we have an error range
            if let range = errorRange, range.location != NSNotFound,
               range.location + range.length <= textStorage.length {
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue, range: range)
                textStorage.addAttribute(.underlineColor, value: NSColor.systemRed, range: range)
            }
        }

        func insertCompletion(_ completion: String, replacingFromPosition startPos: Int) {
            guard let textView = textView else { return }
            let currentPos = textView.selectedRange().location

            // Replace from startPos to currentPos with the completion
            let replaceRange = NSRange(location: startPos, length: currentPos - startPos)
            textView.insertText(completion, replacementRange: replaceRange)
        }
    }
}

// SQL Syntax Highlighter
enum SQLHighlighter {
    // SQL Keywords
    static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "IS", "NULL",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "TABLE", "INDEX", "VIEW", "DROP", "ALTER", "ADD", "COLUMN",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "ON",
        "GROUP", "BY", "ORDER", "ASC", "DESC", "HAVING", "LIMIT", "OFFSET",
        "DISTINCT", "AS", "CASE", "WHEN", "THEN", "ELSE", "END",
        "UNION", "ALL", "INTERSECT", "EXCEPT",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "CHECK", "DEFAULT",
        "CONSTRAINT", "CASCADE", "RESTRICT",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
        "TRUE", "FALSE", "LIKE", "ILIKE", "BETWEEN", "EXISTS",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF",
        "CAST", "EXTRACT", "DATE", "TIME", "TIMESTAMP", "INTERVAL",
        "WITH", "RECURSIVE", "RETURNING", "USING", "NATURAL"
    ]

    // Data types
    static let types: Set<String> = [
        "INT", "INTEGER", "BIGINT", "SMALLINT", "SERIAL", "BIGSERIAL",
        "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "REAL",
        "VARCHAR", "CHAR", "TEXT", "UUID", "BOOLEAN", "BOOL",
        "DATE", "TIME", "TIMESTAMP", "TIMESTAMPTZ", "INTERVAL",
        "JSON", "JSONB", "ARRAY", "BYTEA"
    ]

    // Colors
    static let keywordColor = NSColor.systemBlue
    static let typeColor = NSColor.systemTeal
    static let stringColor = NSColor.systemGreen
    static let numberColor = NSColor.systemOrange
    static let commentColor = NSColor.systemGray
    static let operatorColor = NSColor.systemPurple

    static func highlight(textStorage: NSTextStorage, text: String) {
        let nsText = text as NSString

        // Highlight strings (single quotes)
        highlightPattern(textStorage: textStorage, text: nsText, pattern: "'[^']*'", color: stringColor)

        // Highlight strings (double quotes for identifiers)
        highlightPattern(textStorage: textStorage, text: nsText, pattern: "\"[^\"]*\"", color: stringColor)

        // Highlight comments (-- style)
        highlightPattern(textStorage: textStorage, text: nsText, pattern: "--[^\n]*", color: commentColor)

        // Highlight comments (/* */ style)
        highlightPattern(textStorage: textStorage, text: nsText, pattern: "/\\*[\\s\\S]*?\\*/", color: commentColor)

        // Highlight numbers
        highlightPattern(textStorage: textStorage, text: nsText, pattern: "\\b\\d+\\.?\\d*\\b", color: numberColor)

        // Highlight keywords (case insensitive, word boundaries)
        for keyword in keywords {
            highlightWord(textStorage: textStorage, text: nsText, word: keyword, color: keywordColor)
        }

        // Highlight types
        for type in types {
            highlightWord(textStorage: textStorage, text: nsText, word: type, color: typeColor)
        }
    }

    private static func highlightPattern(textStorage: NSTextStorage, text: NSString, pattern: String, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let range = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                textStorage.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }

    private static func highlightWord(textStorage: NSTextStorage, text: NSString, word: String, color: NSColor) {
        let pattern = "\\b\(word)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let range = NSRange(location: 0, length: text.length)

        regex.enumerateMatches(in: text as String, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range {
                textStorage.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }
}
