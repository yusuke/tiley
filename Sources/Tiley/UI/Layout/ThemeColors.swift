import SwiftUI

enum ThemeColors {
    // MARK: - Window Background

    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.14, green: 0.14, blue: 0.16)
        default:
            return Color(red: 0.95, green: 0.97, blue: 0.99)
        }
    }

    // MARK: - Grid Workspace

    static func gridCellFill(for colorScheme: ColorScheme) -> Color {
        return Color.clear
    }

    static func gridCellSelectedFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.22, green: 0.55, blue: 1.0).opacity(0.45)
        default:
            return Color(red: 0.16, green: 0.49, blue: 0.93).opacity(0.45)
        }
    }

    static func gridCellHoverFill(for colorScheme: ColorScheme) -> Color {
        gridCellSelectedFill(for: colorScheme).opacity(0.35)
    }

    static func gridCellBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        default:
            return Color.black.opacity(0.08)
        }
    }

    static func gridCellSelectedBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.60)
        default:
            return Color.white.opacity(0.82)
        }
    }

    static func gridCellHoverBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.35)
        default:
            return Color.white.opacity(0.5)
        }
    }

    static func gridCellHighlightFill(for colorScheme: ColorScheme) -> Color {
        gridCellSelectedFill(for: colorScheme)
    }

    static func gridCellHighlightBorder(for colorScheme: ColorScheme) -> Color {
        indexedSelectionBorder(index: 0, for: colorScheme)
    }

    // MARK: - Grid Preview (Settings)

    static func previewGradientStart(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.18, green: 0.18, blue: 0.20)
        default:
            return Color.white
        }
    }

    static func previewGradientEnd(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.14, green: 0.16, blue: 0.20)
        default:
            return Color(red: 0.90, green: 0.94, blue: 0.98)
        }
    }

    static func previewBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    static func previewCellFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.28, green: 0.30, blue: 0.35).opacity(0.75)
        default:
            return Color(red: 0.85, green: 0.90, blue: 0.95).opacity(0.75)
        }
    }

    static func previewCellBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.white.opacity(0.95)
        }
    }

    static func previewSelectionFill(for colorScheme: ColorScheme) -> Color {
        gridCellSelectedFill(for: colorScheme).opacity(0.22)
    }

    static func previewSelectionBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.30, green: 0.55, blue: 0.95)
        default:
            return Color(red: 0.11, green: 0.37, blue: 0.80)
        }
    }

    // MARK: - Overlay (Desktop)

    static func overlayBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.04)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func overlayCellFill(for colorScheme: ColorScheme) -> Color {
        gridCellSelectedFill(for: colorScheme).opacity(0.18)
    }

    static func overlayCellBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.40)
        default:
            return Color.white.opacity(0.55)
        }
    }

    static func overlaySelectionFill(for colorScheme: ColorScheme) -> Color {
        gridCellSelectedFill(for: colorScheme).opacity(0.24)
    }

    static func overlaySelectionBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.75)
        default:
            return Color.white.opacity(0.88)
        }
    }

    // MARK: - Preset List

    static func presetRowBackground(selected: Bool, for colorScheme: ColorScheme) -> Color {
        if selected {
            return Color.accentColor.opacity(0.12)
        }
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.04)
        }
    }

    static func presetRowBorder(selected: Bool, for colorScheme: ColorScheme) -> Color {
        if selected {
            return Color.accentColor.opacity(0.35)
        }
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func presetCellBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.07)
        default:
            return Color.black.opacity(0.06)
        }
    }

    static func presetCellBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.10)
        }
    }

    static func editButtonBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.22, green: 0.22, blue: 0.24)
        default:
            return Color(red: 0.91, green: 0.93, blue: 0.95)
        }
    }

    static func deleteButtonHoverBackground(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.35, green: 0.16, blue: 0.16)
        default:
            return Color(red: 0.98, green: 0.90, blue: 0.90)
        }
    }

    // MARK: - Multi-Selection Palette

    /// Colors for indexed selections: blue, green, orange, purple (cycling).
    private static let selectionPalette: [(light: (r: Double, g: Double, b: Double), dark: (r: Double, g: Double, b: Double))] = [
        (light: (0.16, 0.49, 0.93), dark: (0.22, 0.55, 1.0)),   // blue
        (light: (0.18, 0.70, 0.35), dark: (0.25, 0.75, 0.42)),  // green
        (light: (0.85, 0.52, 0.10), dark: (0.92, 0.60, 0.18)),  // orange
        (light: (0.58, 0.28, 0.78), dark: (0.65, 0.38, 0.85)),  // purple
    ]

    /// Fill for a selection at the given index (cycling through blue, green, orange, purple).
    static func indexedSelectionFill(index: Int, for colorScheme: ColorScheme) -> Color {
        let pal = selectionPalette[index % selectionPalette.count]
        let c = colorScheme == .dark ? pal.dark : pal.light
        return Color(red: c.r, green: c.g, blue: c.b).opacity(0.45)
    }

    /// Border for a selection at the given index.
    static func indexedSelectionBorder(index: Int, for colorScheme: ColorScheme) -> Color {
        let pal = selectionPalette[index % selectionPalette.count]
        let c = colorScheme == .dark ? pal.dark : pal.light
        return Color(red: c.r, green: c.g, blue: c.b).opacity(colorScheme == .dark ? 0.70 : 0.80)
    }

    /// Preset grid thumbnail fill for a selection at the given index.
    static func indexedPresetGridFill(index: Int, for colorScheme: ColorScheme) -> Color {
        let pal = selectionPalette[index % selectionPalette.count]
        let c = colorScheme == .dark ? pal.dark : pal.light
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Fill for an invalid (overlapping) drag selection.
    static func invalidSelectionFill(for colorScheme: ColorScheme) -> Color {
        Color.red.opacity(colorScheme == .dark ? 0.35 : 0.30)
    }

    /// Border for an invalid (overlapping) drag selection.
    static func invalidSelectionBorder(for colorScheme: ColorScheme) -> Color {
        Color.red.opacity(colorScheme == .dark ? 0.60 : 0.70)
    }

    static func presetGridUnselectedFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    static func screenshotBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.10)
        }
    }
}
