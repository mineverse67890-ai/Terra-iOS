//
//  TerraTroubleshootViewController.h
//  ★ [TERRA-DIAG] "Why isn't it starting / why did it crash?" screen.
//  Shows TerraCrashAnalyzer's diagnosis (cause, evidence line, numbered fixes) with
//  View Full Log / Share Log / Copy Report. Opened from the loading screen and the crash screen.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TerraTroubleshootViewController : UIViewController

/// Present over `presenter` (full screen, never resizes the game surface underneath).
/// @param exitCode  game exit code, or NSNotFound while the game is still loading.
/// @param stageProvider returns the current loading-stage text (used by Re-check while loading); may be nil.
+ (void)presentFrom:(UIViewController *)presenter
           exitCode:(NSInteger)exitCode
      stageProvider:(NSString *_Nullable (^_Nullable)(void))stageProvider;

@end

NS_ASSUME_NONNULL_END
