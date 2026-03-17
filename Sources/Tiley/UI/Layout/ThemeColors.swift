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
        switch colorScheme {
        case .dark:
            return Color(red: 0.22, green: 0.24, blue: 0.28)
        default:
            return Color(red: 0.90, green: 0.92, blue: 0.96)
        }
    }

    static func gridCellSelectedFill(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.22, green: 0.55, blue: 1.0)
        default:
            return Color(red: 0.16, green: 0.49, blue: 0.93)
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
        gridCellSelectedFill(for: colorScheme).opacity(0.25)
    }

    static func gridCellHighlightBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.white.opacity(0.4)
        }
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
