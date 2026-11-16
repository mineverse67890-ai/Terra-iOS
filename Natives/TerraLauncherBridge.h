// ===========================================================================
//  ★ [TERRA] TerraLauncherBridge.h —— Swift UI ↔ legacy ObjC launch pipeline
//  ---------------------------------------------------------------------------
//  TerraLauncherService is created by the SwiftUI root (TerraBridge in
//  TerraTheme.swift, via NSClassFromString) and provides:
//    · snapshot      — instance list (Documents/instances/<name>/minecraft/),
//                      selected profile, username, version, download source
//    · invoke:       — launch / selectInstance / deleteInstance / openMods /
//                      openSettings / openAccount / installVersion / stateRequest
//    · attachToRoot: — hosts the invisible LauncherRightPanelViewController
//                      (full original launch pipeline, NORIGHT mode) on the root
//                      VC, answers FindVersionInRemoteList (version manifest),
//                      and handles ShowAccountManager.
//  ===========================================================================
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerraLauncherService : NSObject

+ (instancetype)shared;

/// Attach to the window root VC: adds the invisible right-panel controller,
/// registers notification observers and starts fetching the version manifest.
- (void)attachToRoot:(UIViewController *)root;
/// Cheap JIT check for the Play screen: @{@"state": enabled|pending|disabled, @"text": localized label}.
/// Same rules as LauncherRightPanelViewController -updateJITStatus.
- (NSDictionary *)jitStatus;

/// One-shot snapshot for the SwiftUI layer.
- (NSDictionary *)snapshot;

/// Generic command channel (see header comment).
- (void)invoke:(NSString *)cmd payload:(nullable NSDictionary *)payload;

@end

NS_ASSUME_NONNULL_END
