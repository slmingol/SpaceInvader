import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let jumpToSpace1  = Self("jumpToSpace1",  default: .init(.one,   modifiers: .control))
    static let jumpToSpace2  = Self("jumpToSpace2",  default: .init(.two,   modifiers: .control))
    static let jumpToSpace3  = Self("jumpToSpace3",  default: .init(.three, modifiers: .control))
    static let jumpToSpace4  = Self("jumpToSpace4",  default: .init(.four,  modifiers: .control))
    static let jumpToSpace5  = Self("jumpToSpace5",  default: .init(.five,  modifiers: .control))
    static let jumpToSpace6  = Self("jumpToSpace6",  default: .init(.six,   modifiers: .control))
    static let jumpToSpace7  = Self("jumpToSpace7",  default: .init(.seven, modifiers: .control))
    static let jumpToSpace8  = Self("jumpToSpace8",  default: .init(.eight, modifiers: .control))
    static let jumpToSpace9  = Self("jumpToSpace9",  default: .init(.nine,  modifiers: .control))
    static let jumpToSpace10 = Self("jumpToSpace10")

    static let quickSwitcher = Self("quickSwitcher")

    static func jumpToSpace(_ index: Int) -> Self? {
        switch index {
        case 1:  .jumpToSpace1
        case 2:  .jumpToSpace2
        case 3:  .jumpToSpace3
        case 4:  .jumpToSpace4
        case 5:  .jumpToSpace5
        case 6:  .jumpToSpace6
        case 7:  .jumpToSpace7
        case 8:  .jumpToSpace8
        case 9:  .jumpToSpace9
        case 10: .jumpToSpace10
        default: nil
        }
    }
}
