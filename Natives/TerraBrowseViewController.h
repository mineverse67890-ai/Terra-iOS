//
//  TerraBrowseViewController.h
//  ★ [TERRA-BROWSE] "Mods & More" browser, styled after the Modrinth website.
//
//  Content tabs (Mods · Modpacks · Shaders · Resource Packs · Data Packs), Modrinth /
//  CurseForge switch, filter sidebar (sort, loader, game version, categories — a sheet on
//  narrow widths), result cards with infinite scroll, project pages with per-version
//  Install buttons (dependencies resolved automatically), "Install to" target picker,
//  Potato Optimize and Competitive Download buttons.
//
//  Works embedded (SwiftUI UIViewControllerRepresentable), pushed on a navigation
//  controller, or presented. Configure with KVC before it appears:
//      setValue("MyInstall", forKey: "profileName"); setValue("shader", forKey: "contentType")
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted after content was installed from the browser. userInfo: @{@"profileName", @"contentType"}
extern NSString *const TerraBrowseDidInstallNotification;

@interface TerraBrowseViewController : UIViewController

/// Target installation (profile name). nil → the selected installation.
@property (nonatomic, copy, nullable) NSString *profileName;
/// Initial tab: @"mod" (default), @"modpack", @"shader", @"resourcepack", @"datapack".
@property (nonatomic, copy, nullable) NSString *contentType;
/// Show the Potato Optimize / Competitive Download buttons in the header (default YES).
@property (nonatomic, assign) BOOL showsOptimizeButtons;

@end

NS_ASSUME_NONNULL_END
