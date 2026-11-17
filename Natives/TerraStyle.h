//
//  TerraStyle.h
//  ★ [TERRA-STYLE] Shared Minecraft-launcher look for UIKit (Objective-C) screens.
//  Same palette as TerraTheme.swift (MCT): charcoal surfaces, official launcher green,
//  square-ish corners, bevelled "PLAY"-style buttons and the 4×4 grass-block icon.
//  Use this in every redesigned ObjC screen so they all match the SwiftUI launcher.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerraStyle : NSObject

#pragma mark Palette
+ (UIColor *)background;     ///< #1E1E1E  page background
+ (UIColor *)surface;        ///< #262626  sidebar / header / cards
+ (UIColor *)raised;         ///< #313131  raised controls, inputs
+ (UIColor *)border;         ///< white 8% hairline
+ (UIColor *)green;          ///< #3C8527  primary action
+ (UIColor *)greenBright;    ///< #52A535  highlight / selection accent
+ (UIColor *)greenDark;      ///< #2A641C  bevel shadow
+ (UIColor *)text;           ///< white
+ (UIColor *)dimText;        ///< 70% grey
+ (UIColor *)danger;         ///< #E55353
+ (UIColor *)warning;        ///< amber

#pragma mark Typography
+ (UIFont *)titleFont;       ///< 22 bold
+ (UIFont *)headlineFont;    ///< 16 semibold
+ (UIFont *)bodyFont;        ///< 14 regular
+ (UIFont *)captionFont;     ///< 12 regular
+ (UIFont *)sectionFont;     ///< 11 heavy (use with uppercase text) — "MINECRAFT: JAVA EDITION" style

#pragma mark Components
/// Card: surface color, 6pt corners, hairline border.
+ (UIView *)cardView;
/// Uppercase section header label ("FILTERS", "INSTALLED").
+ (UILabel *)sectionLabel:(NSString *)text;
/// Minecraft-style button: flat face, 3pt top highlight, 4pt bottom bevel, dark outline.
/// primary = green face (PLAY style); otherwise raised grey face.
+ (UIButton *)blockButtonWithTitle:(NSString *)title symbol:(nullable NSString *)symbol primary:(BOOL)primary;
/// Same as blockButtonWithTitle but red (destructive).
+ (UIButton *)dangerButtonWithTitle:(NSString *)title symbol:(nullable NSString *)symbol;
/// Small capsule chip/tag ("Fabric", "Release", category names).
+ (UILabel *)chipWithText:(NSString *)text color:(UIColor *)color;
/// 4×4 pixel grass block (same art as the SwiftUI TerraBlockIcon(.grass)).
+ (UIView *)grassBlockOfSize:(CGFloat)size;
/// Sidebar row button (icon + title); call setSidebarRow:selected: to toggle the selection style
/// (white bar at the left edge + lighter background, like the launcher sidebar).
+ (UIButton *)sidebarRowWithTitle:(NSString *)title symbol:(nullable NSString *)symbol;
+ (void)setSidebarRow:(UIButton *)row selected:(BOOL)selected;
/// Dark search field (UISearchTextField styled for the palette).
+ (UISearchTextField *)searchFieldWithPlaceholder:(NSString *)placeholder;

#pragma mark Screens
/// Dark background, dark nav bar (opaque #1E1E1E, white title, green tint), dark interface style.
+ (void)applyToViewController:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
