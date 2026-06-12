//
//  Theme.swift
//  ImHimKeyboard
//
//  Visual identity for the keyboard extension. Mirrors lib/theme/app_colors.dart
//  so the keyboard reads as part of the same product, not a stranger.
//
//  Why no custom fonts? iOS keyboard extensions have a hard memory ceiling
//  (~70 MB) and bundling Playfair / Inter eats into that budget. SF Pro
//  with weight + italic + tracking nails the same editorial mood and ships
//  for free with every iOS device.
//

import UIKit

enum Theme {
    // ── Colours ─────────────────────────────────────────────────────────
    static let base         = UIColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)
    static let surface1     = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.00)
    static let surface2     = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.00)
    static let surface3     = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.00)
    static let divider      = UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1.00)
    static let textPrimary  = UIColor.white
    static let textSecondary = UIColor(white: 1.00, alpha: 0.82)
    static let textTertiary = UIColor(white: 1.00, alpha: 0.58)
    static let textMuted    = UIColor(white: 1.00, alpha: 0.38)
    /// Brand red — same hex as AppColors.red in the Flutter app.
    static let red          = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 1.00)
    static let redDim       = UIColor(red: 0.90, green: 0.22, blue: 0.27, alpha: 0.18)
    static let accent       = UIColor(red: 0.55, green: 0.58, blue: 0.96, alpha: 1.00)

    // ── Type ────────────────────────────────────────────────────────────
    static func wordmark(size: CGFloat) -> UIFont {
        // Playfair-style italic editorial wordmark — system serif italic
        // with a heavy weight. Renders consistently with how the Flutter
        // app builds its ImHim header.
        let descriptor = UIFont.systemFont(ofSize: size, weight: .heavy)
            .fontDescriptor.withSymbolicTraits([.traitItalic])
        if let descriptor = descriptor {
            return UIFont(descriptor: descriptor, size: size)
        }
        return UIFont.systemFont(ofSize: size, weight: .heavy)
    }

    static func label(size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .black)
    }

    static func body(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
}
