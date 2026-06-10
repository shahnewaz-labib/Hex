#if os(macOS)
    import Sauce
    public typealias Key = Sauce.Key
#else
    import Foundation

    /// Cross-platform keyboard key enum replacing Sauce's macOS-only Key type.
    public enum Key: String, Codable, Equatable, Sendable {
        case a, s, d, f, h, g, z, x, c, v, b, q, w, e, r, y, t
        case one, two, three, four, six, five, equal, nine, seven, minus, eight, zero
        case rightBracket, o, u, leftBracket, i, p, l, j, quote, k, semicolon, backslash, comma, slash, n, m, period, grave
        case keypadDecimal, keypadMultiply, keypadPlus, keypadClear, keypadDivide, keypadEnter, keypadMinus, keypadEquals
        case keypadZero, keypadOne, keypadTwo, keypadThree, keypadFour, keypadFive, keypadSix, keypadSeven, keypadEight, keypadNine
        case `return`, tab, space, delete, escape
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
        case help, home, pageUp, forwardDelete, end, pageDown
        case leftArrow, rightArrow, downArrow, upArrow
        case yen, underscore, keypadComma, eisu, kana, atSign, caret, colon, section

        public var toString: String {
            switch self {
            case .escape: return "⎋"
            case .space: return "␣"
            case .zero: return "0"
            case .one: return "1"
            case .two: return "2"
            case .three: return "3"
            case .four: return "4"
            case .five: return "5"
            case .six: return "6"
            case .seven: return "7"
            case .eight: return "8"
            case .nine: return "9"
            case .period: return "."
            case .comma: return ","
            case .slash: return "/"
            case .quote: return "\""
            case .backslash: return "\\"
            case .leftArrow: return "←"
            case .rightArrow: return "→"
            case .upArrow: return "↑"
            case .downArrow: return "↓"
            default: return rawValue.uppercased()
            }
        }
    }
#endif
