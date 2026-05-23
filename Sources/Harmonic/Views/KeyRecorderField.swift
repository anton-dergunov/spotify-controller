import AppKit
import SwiftUI
import HotKey

// SwiftUI wrapper for a click-to-record keyboard shortcut field.
struct KeyRecorderField: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    func makeCoordinator() -> Coordinator { Coordinator(binding: $shortcut) }

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onChange = { context.coordinator.commit($0) }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        context.coordinator.binding = $shortcut
        if !nsView.isRecording {
            nsView.currentShortcut = shortcut
            nsView.needsDisplay = true
        }
    }

    final class Coordinator {
        var binding: Binding<Shortcut?>
        init(binding: Binding<Shortcut?>) { self.binding = binding }
        func commit(_ s: Shortcut?) { binding.wrappedValue = s }
    }
}

// MARK: - NSView

final class KeyRecorderNSView: NSView {
    var currentShortcut: Shortcut?
    var isRecording = false
    var onChange: ((Shortcut?) -> Void)?
    private var recordingMods: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 22) }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if clearRect.contains(pt), currentShortcut != nil {
            currentShortcut = nil
            onChange?(nil)
            isRecording = false
            needsDisplay = true
            return
        }
        guard !isRecording else { return }
        window?.makeFirstResponder(self)
        isRecording = true
        recordingMods = []
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 {  // Escape — cancel without changing
            isRecording = false
            needsDisplay = true
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty,
              let key = Key(carbonKeyCode: UInt32(event.keyCode)) else { return }
        let char = (event.charactersIgnoringModifiers ?? "?").prefix(1).uppercased()
        let s = Shortcut(key: key, modifiers: mods, displayChar: String(char))
        currentShortcut = s
        isRecording = false
        onChange?(s)
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        recordingMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false; needsDisplay = true }
        return super.resignFirstResponder()
    }

    // MARK: - Drawing

    private var clearRect: CGRect {
        CGRect(x: bounds.maxX - 22, y: 0, width: 22, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        let focused = window?.firstResponder == self
        if focused {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        if isRecording {
            let preview = recordingMods.isEmpty ? "Press shortcut…" : recordingMods.glyphs + "…"
            drawLabel(preview, color: .placeholderTextColor, in: bounds)
        } else if let s = currentShortcut {
            drawLabel(s.displayString, color: .labelColor,
                      in: CGRect(x: 0, y: 0, width: bounds.width - 22, height: bounds.height))
            drawLabel("✕", color: .secondaryLabelColor, in: clearRect)
        } else {
            drawLabel("Not set", color: .placeholderTextColor, in: bounds)
        }
    }

    private func drawLabel(_ text: String, color: NSColor, in rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        let y = rect.minY + (rect.height - sz.height) / 2
        str.draw(in: CGRect(x: rect.minX, y: y, width: rect.width, height: sz.height + 2))
    }
}
