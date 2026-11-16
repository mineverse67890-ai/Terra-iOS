//
//  TerraInstanceSettingsViewController.h
//  ★ [TERRA-INSTANCE] Per-installation ("Minecraft version") settings, Terra launcher style.
//  Header card + left section sidebar (pull-down section menu on narrow widths) + detail pane.
//  Reads and writes the same launcher_profiles.json keys as the legacy
//  ProfileSettingsViewController (which stays reachable via "Advanced folder options…").
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerraInstanceSettingsViewController : UIViewController

/// Key of the profile in PLProfiles.current.profiles. Set via KVC by the launcher bridge.
/// nil ⇒ the currently selected profile. Updated in place when the installation is renamed.
@property (nonatomic, copy, nullable) NSString *profileName;

@end

NS_ASSUME_NONNULL_END
