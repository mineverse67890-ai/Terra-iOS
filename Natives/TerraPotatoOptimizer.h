//
//  TerraPotatoOptimizer.h
//  ★ [TERRA-BROWSE] One-tap mod sets from Modrinth for an installation.
//
//  · Potato Optimize      — the best client performance mods for the installation's loader.
//  · Competitive Download — PvP mods (zoom, freelook, armor/totem HUDs, hitboxes + a performance
//                           base) and PvP resource packs (Spunky + overlays). Vanilla installs
//                           get the resource packs only.
//
//  Both show a confirm sheet listing what will be installed, then live progress and a summary.
//  Projects without a version for the loader + Minecraft version are skipped, already-installed
//  ones are left alone, and required dependencies are resolved with ModDependencyResolver.
//  Posts TerraPotatoOptimizerDidFinishNotification (userInfo @{@"profileName"}) when done.
//
//  Swift: (NSClassFromString("TerraPotatoOptimizer") as AnyObject)
//           .perform(NSSelectorFromString("optimizeProfile:presenter:"), with: name, with: vc)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TerraPotatoOptimizerDidFinishNotification;

@interface TerraPotatoOptimizer : NSObject

/// Potato Optimize. profileName nil/empty → the selected installation.
+ (void)optimizeProfile:(nullable NSString *)profileName presenter:(nullable UIViewController *)presenter;

/// Competitive Download. profileName nil/empty → the selected installation.
+ (void)competitiveProfile:(nullable NSString *)profileName presenter:(nullable UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
