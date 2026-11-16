//
//  TerraVersionInstaller.h
//  ★ [TERRA-BROWSE] Installs a Minecraft version with an optional mod loader
//  (Vanilla / Fabric / Forge / NeoForge / Quilt) from anywhere in the app.
//
//  Flow: ModLoaderInstallViewController (choose loader + loader version) →
//        vanilla files are installed first when missing (MinecraftResourceDownloadTask) →
//        Fabric/Quilt: meta profile JSON, Forge/NeoForge: ForgeInstallViewController +
//        ForgeDirectInstaller / NeoForgeDirectInstaller (same path as the legacy
//        DownloadViewController). Progress is shown by the unified download-task page.
//
//  Swift: (NSClassFromString("TerraVersionInstaller") as AnyObject)
//           .perform(NSSelectorFromString("presentInstallForVersion:from:"), with: id, with: vc)
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread when an install finished successfully. userInfo: @{@"versionId": id}
extern NSString *const TerraVersionInstallerDidFinishNotification;

@interface TerraVersionInstaller : NSObject

/// Shows the loader picker for a Minecraft version and installs the choice.
/// presenter nil → the top-most presented view controller of the key window.
+ (void)presentInstallForVersion:(NSString *)versionId from:(nullable UIViewController *)presenter;

/// Top-most presented view controller of the key window.
+ (nullable UIViewController *)topPresenter;

/// YES when versions/<id>/<id>.json exists in the current game directory.
+ (BOOL)isVersionInstalled:(NSString *)versionId;

@end

NS_ASSUME_NONNULL_END
