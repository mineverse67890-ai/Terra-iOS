//
//  TerraModsManagerViewController.h
//  ★ [TERRA-MODS] Redesigned "Manage Mods" screen with a left sidebar
//  (content type / filter / sort / actions) and a clean list of installed content.
//  Reuses ModService, ShaderService, ResourcePackService and DataPackService.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted (by anyone, e.g. TerraPotatoOptimizer) when installed content changed on disk;
/// the manager rescans when it receives it. Object: the profile name (NSString) or nil.
extern NSString * const TerraModsContentDidChangeNotification;

@interface TerraModsManagerViewController : UIViewController

/// Installation (profile) whose content is managed. nil = "default".
/// The launcher bridge sets this via KVC (setValue:forKey:@"profileName").
@property (nonatomic, copy, nullable) NSString *profileName;

/// Initial content section: @"mod" (default), @"shader", @"resourcepack" or @"datapack".
@property (nonatomic, copy, nullable) NSString *contentType;

@end

NS_ASSUME_NONNULL_END
