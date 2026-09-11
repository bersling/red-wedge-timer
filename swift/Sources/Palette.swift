import SwiftUI

/// The colours of the physical device: paper-white bezel, one loud red disk.
struct Palette {
    let paper: Color
    let face: Color
    let ink: Color
    let muted: Color
    let hairline: Color
    let wedge: Color
    let rim: Color
    let teal: Color
    let chip: Color

    static let light = Palette(
        paper:    Color(red: 0.984, green: 0.969, blue: 0.941),
        face:     .white,
        ink:      Color(red: 0.129, green: 0.141, blue: 0.169),
        muted:    Color(red: 0.549, green: 0.522, blue: 0.502),
        hairline: Color(red: 0.886, green: 0.863, blue: 0.820),
        wedge:    Color(red: 0.886, green: 0.227, blue: 0.149),
        rim:      Color(red: 0.925, green: 0.898, blue: 0.851),
        teal:     Color(red: 0.184, green: 0.561, blue: 0.478),
        chip:     .white
    )

    static let dark = Palette(
        paper:    Color(red: 0.098, green: 0.106, blue: 0.125),
        face:     Color(red: 0.149, green: 0.165, blue: 0.196),
        ink:      Color(red: 0.949, green: 0.937, blue: 0.914),
        muted:    Color(red: 0.592, green: 0.569, blue: 0.545),
        hairline: Color(red: 0.220, green: 0.239, blue: 0.278),
        wedge:    Color(red: 0.941, green: 0.314, blue: 0.227),
        rim:      Color(red: 0.204, green: 0.227, blue: 0.267),
        teal:     Color(red: 0.310, green: 0.733, blue: 0.627),
        chip:     Color(red: 0.180, green: 0.200, blue: 0.235)
    )

    static func of(_ scheme: ColorScheme) -> Palette { scheme == .dark ? .dark : .light }
}
