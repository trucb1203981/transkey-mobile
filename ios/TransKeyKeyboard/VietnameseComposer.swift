import Foundation

/// The Vietnamese input engines the keyboard can run: Telex (letters as
/// modifiers) and VNI (digits as modifiers). They already share an identical
/// surface, so the keyboard holds one of these instead of branching on the
/// typing language at every call site.
protocol VietnameseComposer: AnyObject {
    var hasComposingText: Bool { get }
    var composingText: String { get }
    /// The user escaped the engine by repeating a modifier ("telexx", "covid19"):
    /// commit the word verbatim, never auto-correct it.
    var literalIntent: Bool { get }

    func reset()
    @discardableResult func input(_ ch: Character) -> Bool
    @discardableResult func backspace() -> Bool
    func commitWord() -> String
}

extension TelexProcessor: VietnameseComposer {}
extension VniProcessor: VietnameseComposer {}
