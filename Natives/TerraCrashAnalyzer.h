//
//  TerraCrashAnalyzer.h
//  ★ [TERRA-DIAG] Reads the game log (+ newest Minecraft crash report / JVM hs_err file)
//  and explains in plain English why a launch failed or crashed, with concrete fixes.
//  Pure logic: no UI. Used by TerraTroubleshootViewController (loading screen + crash screen).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TerraDiagnosisSeverity) {
    TerraDiagnosisSeverityOK = 0,       ///< nothing wrong found (e.g. still loading)
    TerraDiagnosisSeverityWarning,      ///< likely problem, game may still start
    TerraDiagnosisSeverityProblem,      ///< definite cause of a failure / crash
};

@interface TerraDiagnosis : NSObject
@property(nonatomic, copy) NSString *identifier;        ///< stable id, e.g. "jit", "oom", "mixin"
@property(nonatomic, assign) TerraDiagnosisSeverity severity;
@property(nonatomic, copy) NSString *title;             ///< "Not enough memory"
@property(nonatomic, copy) NSString *summary;           ///< what happened, plain English
@property(nonatomic, copy, nullable) NSString *evidence; ///< the log line that gave it away
@property(nonatomic, copy) NSArray<NSString *> *fixes;  ///< ordered, actionable steps
/// Multi-line plain-text version (for Copy Report / sharing).
- (NSString *)reportText;
@end

@interface TerraCrashAnalyzer : NSObject

/// Analyze the current logs.
/// @param exitCode  game exit code, or NSNotFound while the game is still loading.
/// @param stageName current loading stage (only used while loading), may be nil.
+ (TerraDiagnosis *)diagnoseWithExitCode:(NSInteger)exitCode stageName:(nullable NSString *)stageName;

/// Same, on explicit log text (unit-testable; no file or device access except the JIT check).
+ (TerraDiagnosis *)diagnoseLog:(NSString *)log exitCode:(NSInteger)exitCode
                     jitEnabled:(BOOL)jitEnabled stageName:(nullable NSString *)stageName;

/// Files worth sharing for support: latestlog.txt plus any recent crash report / hs_err file.
+ (NSArray<NSURL *> *)logFileURLs;

/// Tail of latestlog.txt (at most maxBytes) for the in-app log viewer.
+ (NSString *)latestLogTail:(NSUInteger)maxBytes;

@end

NS_ASSUME_NONNULL_END
