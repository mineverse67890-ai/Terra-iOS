//
//  TerraVersionInstaller.m
//  ★ [TERRA-BROWSE] see TerraVersionInstaller.h
//  The install steps mirror DownloadViewController (proceedWithVersion:/installFabricLikeLoader:/
//  installForge:/installNeoForge:) so profiles, version JSONs and progress tasks are identical.
//

#import "TerraVersionInstaller.h"
#import "TerraBrowseAPI.h"
#import "TerraStyle.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "PLCrashView.h"
#import "PLTaskStages.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "MinecraftResourceDownloadTask.h"
#import "LauncherNavigationController.h"
// Legacy installer headers are not nullability-annotated.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "installer/ModLoaderInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ForgeDirectInstaller.h"
#import "installer/NeoForgeDirectInstaller.h"
#import "installer/ForgeProcessorExecutor.h"
#pragma clang diagnostic pop

NSString *const TerraVersionInstallerDidFinishNotification = @"TerraVersionInstallerDidFinishNotification";

static NSString *const kOfficialManifest = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
static NSString *const kBMCLManifest = @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json";

static NSString *TVIGameDir(void) {
    const char *env = getenv("POJAV_GAME_DIR");
    if (env) return @(env);
    const char *home = getenv("POJAV_HOME");
    return home ? @(home) : NSHomeDirectory();
}

@implementation TerraVersionInstaller

#pragma mark - Presentation helpers

+ (UIViewController *)topPresenter {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (!window && scene.activationState == UISceneActivationStateForegroundActive) {
            window = ((UIWindowScene *)scene).windows.firstObject;
        }
        if (window) break;
    }
    UIViewController *vc = window.rootViewController;
    for (int guard = 0; vc.presentedViewController && !vc.presentedViewController.isBeingDismissed && guard < 16; guard++) {
        vc = vc.presentedViewController;
    }
    return vc;
}

+ (void)alertTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = [self topPresenter];
        if (!presenter) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

+ (BOOL)isVersionInstalled:(NSString *)versionId {
    if (versionId.length == 0) return NO;
    NSString *json = [TVIGameDir() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
    return [NSFileManager.defaultManager fileExistsAtPath:json];
}

+ (BOOL)isVanillaComplete:(NSString *)versionId {
    NSString *dir = [TVIGameDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"versions/%@", versionId]];
    NSFileManager *fm = NSFileManager.defaultManager;
    return [fm fileExistsAtPath:[dir stringByAppendingPathComponent:[versionId stringByAppendingString:@".json"]]] &&
           [fm fileExistsAtPath:[dir stringByAppendingPathComponent:[versionId stringByAppendingString:@".jar"]]];
}

+ (void)postInstalled:(NSString *)versionId {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc postNotificationName:@"ReloadProfileList" object:nil];
        [nc postNotificationName:@"TerraInstancesChanged" object:nil];
        [nc postNotificationName:TerraVersionInstallerDidFinishNotification object:nil
                        userInfo:versionId ? @{@"versionId": versionId} : nil];
    });
}

+ (void)finishWithSuccess:(NSString *)message versionId:(NSString *)versionId {
    [self postInstalled:versionId];
    dispatch_async(dispatch_get_main_queue(), ^{
        // Forge/NeoForge processors run in a headless in-process JVM, which can only be created
        // once per process: the game needs a fresh launcher process afterwards.
        if ([ForgeProcessorExecutor jvmUsedThisProcess]) {
            UIViewController *presenter = [self topPresenter];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart required"
                message:[message stringByAppendingString:@"\n\nRestart the launcher before playing this version."]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [PLCrashView restartLauncher];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
            [presenter presentViewController:alert animated:YES completion:nil];
        } else {
            [self alertTitle:@"Installed" message:message];
        }
    });
}

#pragma mark - Entry point

+ (void)presentInstallForVersion:(NSString *)versionId from:(UIViewController *)presenter {
    if (versionId.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = presenter ?: [self topPresenter];
        while (host.presentedViewController && !host.presentedViewController.isBeingDismissed) host = host.presentedViewController;
        if (!host) return;

        ModLoaderInstallViewController *picker = [ModLoaderInstallViewController new];
        picker.gameVersion = versionId;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        nav.navigationBar.tintColor = TerraStyle.greenBright;
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            nav.preferredContentSize = CGSizeMake(620, 760);
        }

        __weak UINavigationController *weakNav = nav;
        picker.cancelled = ^{};
        picker.completion = ^(NSString *loaderId, BOOL installFabricAPI, BOOL installOptiFine, NSString *loaderVersion) {
            UINavigationController *strongNav = weakNav;
            if ([loaderId isEqualToString:@"forge"] || [loaderId isEqualToString:@"neoforge"]) {
                [self pushForgeFlowOn:strongNav gameVersion:versionId neo:[loaderId isEqualToString:@"neoforge"]
                        loaderVersion:loaderVersion installOptiFine:installOptiFine];
                return;
            }
            [strongNav dismissViewControllerAnimated:YES completion:^{
                [self proceedWithVersion:versionId loader:loaderId installFabricAPI:installFabricAPI loaderVersion:loaderVersion];
            }];
        };
        [host presentViewController:nav animated:YES completion:nil];
    });
}

+ (void)proceedWithVersion:(NSString *)versionId loader:(NSString *)loader
          installFabricAPI:(BOOL)installFabricAPI loaderVersion:(NSString *)loaderVersion {
    if ([loader isEqualToString:@"vanilla"]) {
        [self installVanilla:versionId];
    } else if ([loader isEqualToString:@"fabric"] || [loader isEqualToString:@"quilt"]) {
        [self ensureVanilla:versionId completion:^(BOOL ok) {
            if (!ok) {
                [self alertTitle:@"Couldn't install Minecraft" message:[NSString stringWithFormat:
                    @"Minecraft %@ has to be installed before %@, but the download failed. Check your connection and try again.",
                    versionId, [TerraBrowseAPI displayNameForLoader:loader]]];
                return;
            }
            [self installFabricLike:versionId loaderVersion:loaderVersion
                         installAPI:installFabricAPI quilt:[loader isEqualToString:@"quilt"]];
        }];
    } else if ([loader isEqualToString:@"optifine"]) {
        [self alertTitle:@"OptiFine" message:@"Installing OptiFine on its own isn't supported from the Download Center. Install Fabric with Sodium (or use Potato Optimize) for the best performance."];
    } else {
        [self alertTitle:@"Unsupported loader" message:loader ?: @""];
    }
}

#pragma mark - Manifest / vanilla

+ (void)fetchManifestEntry:(NSString *)versionId completion:(void (^)(NSDictionary *entry))completion {
    NSString *source = getPrefObject(@"general.download_source");
    NSArray *urls = [source isEqual:@"bmclapi"] ? @[kBMCLManifest, kOfficialManifest] : @[kOfficialManifest, kBMCLManifest];
    [self fetchManifestEntry:versionId urls:urls index:0 completion:completion];
}

+ (void)fetchManifestEntry:(NSString *)versionId urls:(NSArray<NSString *> *)urls index:(NSUInteger)index
                completion:(void (^)(NSDictionary *))completion {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urls[index]]];
    req.timeoutInterval = 20;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *versions = [json isKindOfClass:NSDictionary.class] ? json[@"versions"] : nil;
        if (![versions isKindOfClass:NSArray.class]) {
            [self fetchManifestEntry:versionId urls:urls index:index + 1 completion:completion];
            return;
        }
        NSDictionary *found = nil;
        for (NSDictionary *v in versions) {
            if ([v isKindOfClass:NSDictionary.class] && [v[@"id"] isEqual:versionId]) { found = v; break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(found); });
    }] resume];
}

/// Full vanilla install (JSON + client + libraries + assets) with the unified progress page;
/// completion(YES) right away when already complete.
+ (void)ensureVanilla:(NSString *)versionId completion:(void (^)(BOOL ok))completion {
    if ([self isVanillaComplete:versionId]) {
        completion(YES);
        return;
    }
    [self fetchManifestEntry:versionId completion:^(NSDictionary *entry) {
        if (!entry) {
            // Unknown to the manifest but already present locally (custom version) → fine.
            completion([self isVersionInstalled:versionId]);
            return;
        }
        MinecraftResourceDownloadTask *task = [MinecraftResourceDownloadTask new];
        task.maxRetryCount = 3;
        __block BOOL failed = NO;
        task.handleError = ^{ failed = YES; };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [task downloadVersion:entry];
            // downloadVersion: rebuilds task.progress, so poll the latest object (same as the
            // legacy pre-install) instead of KVO on a stale one.
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30 * 60];
            BOOL ok = NO;
            while (deadline.timeIntervalSinceNow > 0 && !failed) {
                NSProgress *p = task.progress;
                if (p && p.finished) { ok = !p.cancelled; break; }
                [NSThread sleepForTimeInterval:0.5];
            }
            BOOL result = ok && !failed;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        });
    }];
}

+ (void)saveProfileForVersion:(NSString *)versionId {
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"name"] = versionId;
    profile[@"lastVersionId"] = versionId;
    profile[@"gameDir"] = @".";
    profile[@"type"] = @"custom";
    profile[@"created"] = [NSDate date].description;
    [PLProfiles.current saveProfile:profile withName:versionId];
    PLProfiles.current.selectedProfileName = versionId;
}

+ (void)installVanilla:(NSString *)versionId {
    [self saveProfileForVersion:versionId];
    [self postInstalled:nil];
    [self ensureVanilla:versionId completion:^(BOOL ok) {
        if (ok) {
            [self finishWithSuccess:[NSString stringWithFormat:@"Minecraft %@ is ready to play.", versionId] versionId:versionId];
        } else {
            [self alertTitle:@"Download failed" message:[NSString stringWithFormat:
                @"Minecraft %@ couldn't be downloaded completely. The installation was created; missing files will be downloaded when you press Play.", versionId]];
        }
    }];
}

#pragma mark - Fabric / Quilt

+ (NSString *)registerTaskNamed:(NSString *)name display:(NSString *)display stages:(NSArray *)stages {
    NSString *source = getPrefObject(@"general.download_source") ?: @"official";
    DownloadTaskItem *item = [[DownloadTaskManager sharedManager] registerTaskWithResourceType:DownloadTaskResourceTypeModloader
                                                                                  resourceName:name
                                                                                   displayName:display
                                                                                downloadSource:source
                                                                                       rawTask:nil
                                                                                supportsResume:NO
                                                                                       iconURL:nil];
    if (!item) return nil;
    [[DownloadTaskManager sharedManager] setTaskWithId:item.taskId stages:stages];
    item.autoPresentDetail = YES;
    return item.taskId;
}

+ (void)installFabricLike:(NSString *)gameVersion loaderVersion:(NSString *)loaderVersion
               installAPI:(BOOL)installAPI quilt:(BOOL)isQuilt {
    NSString *display = isQuilt ? @"Quilt" : @"Fabric";
    NSString *metaBase = isQuilt ? @"https://meta.quiltmc.org/v3/versions/loader" : @"https://meta.fabricmc.net/v2/versions/loader";
    if (loaderVersion.length == 0) {
        [self alertTitle:[display stringByAppendingString:@" install failed"] message:@"No loader version was selected."];
        return;
    }
    const NSUInteger kStageProfile = 0, kStageLibs = 1, kStageJSON = 2;   // PLTaskStagesFabricExtra()
    NSString *taskId = [self registerTaskNamed:[NSString stringWithFormat:@"%@-%@-%@", display.lowercaseString, gameVersion, loaderVersion]
                                       display:[NSString stringWithFormat:@"%@ %@ (%@)", display, loaderVersion, gameVersion]
                                        stages:PLTaskStagesFabricExtra()];
    DownloadTaskManager *m = [DownloadTaskManager sharedManager];
    if (taskId) {
        [m updateTaskWithId:taskId stageAtIndex:kStageProfile status:PLTaskStageStatusRunning];
        [m updateTaskWithId:taskId stageAtIndex:kStageProfile progress:-1 message:@"Fetching loader profile…"];
        [m updateTaskWithId:taskId currentStageIndex:kStageProfile];
    }
    void (^fail)(NSUInteger, NSString *) = ^(NSUInteger stage, NSString *reason) {
        if (taskId) {
            [m updateTaskWithId:taskId stageAtIndex:stage status:PLTaskStageStatusFailed];
            [m setTaskWithId:taskId completedWithError:[NSError errorWithDomain:@"TerraVersionInstaller" code:1
                                                                       userInfo:@{NSLocalizedDescriptionKey: reason}]];
        }
        [self alertTitle:[display stringByAppendingString:@" install failed"] message:reason];
    };
    NSString *url = [NSString stringWithFormat:@"%@/%@/%@/profile/json", metaBase, gameVersion, loaderVersion];
    NSURLSessionDataTask *dataTask = [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:url]
                                                               completionHandler:^(NSData *data, NSURLResponse *r, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *profileJson = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *versionId = [profileJson isKindOfClass:NSDictionary.class] ? profileJson[@"id"] : nil;
            if (error || ![versionId isKindOfClass:NSString.class]) {
                fail(kStageProfile, error.localizedDescription ?: @"The loader profile couldn't be downloaded.");
                return;
            }
            if (taskId) {
                [m updateTaskWithId:taskId stageAtIndex:kStageProfile status:PLTaskStageStatusCompleted];
                [m updateTaskWithId:taskId stageAtIndex:kStageJSON status:PLTaskStageStatusRunning];
                [m updateTaskWithId:taskId currentStageIndex:kStageJSON];
            }
            NSString *jsonPath = [TVIGameDir() stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"versions/%@/%@.json", versionId, versionId]];
            [NSFileManager.defaultManager createDirectoryAtPath:jsonPath.stringByDeletingLastPathComponent
                                    withIntermediateDirectories:YES attributes:nil error:nil];
            NSError *saveError = nil;
            NSData *out = [NSJSONSerialization dataWithJSONObject:profileJson options:NSJSONWritingPrettyPrinted error:&saveError];
            if (!out || ![out writeToFile:jsonPath options:NSDataWritingAtomic error:&saveError]) {
                fail(kStageJSON, saveError.localizedDescription ?: @"Couldn't write the version file.");
                return;
            }
            [self saveProfileForVersion:versionId];
            if (taskId) [m updateTaskWithId:taskId stageAtIndex:kStageJSON status:PLTaskStageStatusCompleted];

            NSString *done = [NSString stringWithFormat:@"%@ %@ for Minecraft %@ is installed.", display, loaderVersion, gameVersion];
            if (!installAPI || isQuilt) {
                if (taskId) {
                    [m updateTaskWithId:taskId stageAtIndex:kStageLibs status:PLTaskStageStatusSkipped];
                    [m setTaskWithId:taskId completedWithError:nil];
                }
                [self finishWithSuccess:done versionId:versionId];
                return;
            }
            if (taskId) {
                [m updateTaskWithId:taskId stageAtIndex:kStageLibs status:PLTaskStageStatusRunning];
                [m updateTaskWithId:taskId stageAtIndex:kStageLibs progress:-1 message:@"Downloading Fabric API…"];
                [m updateTaskWithId:taskId currentStageIndex:kStageLibs];
            }
            [self installFabricAPIForVersion:versionId gameVersion:gameVersion completion:^(BOOL ok) {
                if (taskId) {
                    [m updateTaskWithId:taskId stageAtIndex:kStageLibs status:ok ? PLTaskStageStatusCompleted : PLTaskStageStatusFailed];
                    [m setTaskWithId:taskId completedWithError:nil];
                }
                [self finishWithSuccess:ok ? [done stringByAppendingString:@" Fabric API was added to its mods."]
                                           : [done stringByAppendingString:@" Fabric API couldn't be downloaded — add it from Mods & More."]
                              versionId:versionId];
            }];
        });
    }];
    if (taskId) {
        [m taskWithId:taskId].rawTask = dataTask;
        [m setTaskWithId:taskId state:DownloadTaskStateDownloading];
    }
    [dataTask resume];
}

+ (void)installFabricAPIForVersion:(NSString *)versionId gameVersion:(NSString *)gameVersion completion:(void (^)(BOOL ok))completion {
    TerraBrowseTarget *target = [TerraBrowseTarget targetNamed:versionId];
    NSString *folder = [target ensureFolderForContentType:@"mod"];
    if (!folder) {
        completion(NO);
        return;
    }
    TerraBrowseAPI *api = TerraBrowseAPI.shared;
    [api versionsForProjectId:@"fabric-api" source:TerraBrowseSourceModrinth contentType:@"mod" loader:@"fabric"
                  gameVersion:gameVersion completion:^(NSArray<TerraBrowseFile *> *files, NSError *error) {
        TerraBrowseFile *file = files.firstObject;
        if (!file) {
            completion(NO);
            return;
        }
        [api downloadFile:file toFolder:folder progress:nil completion:^(NSString *path, NSError *dlError) {
            completion(path != nil);
        }];
    }];
}

#pragma mark - Forge / NeoForge

+ (void)pushForgeFlowOn:(UINavigationController *)nav gameVersion:(NSString *)gameVersion neo:(BOOL)neo
          loaderVersion:(NSString *)loaderVersion installOptiFine:(BOOL)installOptiFine {
    ForgeInstallViewController *forgeVC = [ForgeInstallViewController new];
    forgeVC.gameVersion = gameVersion;
    forgeVC.isNeoForge = neo;
    forgeVC.presetVersionString = loaderVersion;
    __weak UINavigationController *weakNav = nav;
    forgeVC.completionHandler = ^(BOOL success, NSString *profileName, id resultOrError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^continuation)(void) = ^{
                [self handleForgeResult:success profileName:profileName result:resultOrError
                            gameVersion:gameVersion neo:neo installOptiFine:installOptiFine];
            };
            UINavigationController *strongNav = weakNav;
            if (strongNav.presentingViewController) {
                [strongNav dismissViewControllerAnimated:YES completion:continuation];
            } else {
                continuation();
            }
        });
    };
    if (nav) {
        [nav pushViewController:forgeVC animated:YES];
    }
}

+ (void)handleForgeResult:(BOOL)success profileName:(NSString *)profileName result:(id)resultOrError
              gameVersion:(NSString *)gameVersion neo:(BOOL)neo installOptiFine:(BOOL)installOptiFine {
    NSString *vendor = neo ? @"NeoForge" : @"Forge";
    if (!success) {
        if ([resultOrError isKindOfClass:NSError.class]) {
            NSError *error = resultOrError;
            if ([error.domain isEqualToString:ForgeInstallerFlowErrorDomain] && error.code == ForgeInstallerFlowErrorCodeCancelled) return;
            [self alertTitle:[vendor stringByAppendingString:@" install failed"] message:error.localizedDescription ?: @""];
        }
        return;
    }
    NSString *filePath = nil;
    NSInteger scheme = 0;
    if ([resultOrError isKindOfClass:NSDictionary.class]) {
        filePath = resultOrError[@"filePath"];
        scheme = [resultOrError[@"selectedScheme"] integerValue];
    } else if ([resultOrError isKindOfClass:NSString.class]) {
        filePath = resultOrError;
    }
    if (filePath.length == 0) {
        [self alertTitle:[vendor stringByAppendingString:@" install failed"] message:@"The installer couldn't be downloaded."];
        return;
    }
    if (scheme != 1) {
        // "Run installer" scheme: the Java installer GUI lives in the legacy launcher navigation.
        LauncherNavigationController *launcherNav = [self findLauncherNavigationIn:[self topPresenter].view.window.rootViewController];
        if (launcherNav) {
            [launcherNav enterModInstallerWithPath:filePath hitEnterAfterWindowShown:YES];
        } else {
            [self alertTitle:vendor message:@"The installer GUI isn't available here. Choose the direct install option instead — it's faster and doesn't need JIT."];
        }
        return;
    }
    if (installOptiFine) {
        NSLog(@"[TerraVersionInstaller] OptiFine alongside %@ is not handled here; installing %@ only", vendor, vendor);
    }
    [self ensureVanilla:gameVersion completion:^(BOOL ok) {
        if (!ok) {
            [self alertTitle:[vendor stringByAppendingString:@" install failed"] message:[NSString stringWithFormat:
                @"Minecraft %@ has to be installed first, but the download failed.", gameVersion]];
            return;
        }
        [self runDirectInstaller:filePath profileName:profileName gameVersion:gameVersion neo:neo];
    }];
}

+ (void)runDirectInstaller:(NSString *)filePath profileName:(NSString *)profileName gameVersion:(NSString *)gameVersion neo:(BOOL)neo {
    NSString *vendor = neo ? @"NeoForge" : @"Forge";
    const NSUInteger kStageInstaller = 0, kStageResolve = 1, kStageInstall = 2;   // PLTaskStagesForgeExtra()
    const double split = neo ? 0.2 : 0.15;
    DownloadTaskManager *m = [DownloadTaskManager sharedManager];
    NSString *taskId = [self registerTaskNamed:[NSString stringWithFormat:@"%@-%@-%@", vendor.lowercaseString, gameVersion, profileName ?: @""]
                                       display:[NSString stringWithFormat:@"%@ %@ (%@)", vendor, profileName ?: @"", gameVersion]
                                        stages:PLTaskStagesForgeExtra()];
    if (taskId) {
        [m updateTaskWithId:taskId stageAtIndex:kStageInstaller status:PLTaskStageStatusCompleted];
        [m updateTaskWithId:taskId stageAtIndex:kStageResolve status:PLTaskStageStatusRunning];
        [m updateTaskWithId:taskId stageAtIndex:kStageResolve progress:0 message:nil];
        [m updateTaskWithId:taskId currentStageIndex:kStageResolve];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        void (^progress)(double, NSString *) = ^(double p, NSString *message) {
            if (!taskId) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (p < split) {
                    [m updateTaskWithId:taskId stageAtIndex:kStageResolve progress:MIN(p / split, 1.0) message:message];
                } else {
                    [m updateTaskWithId:taskId stageAtIndex:kStageResolve status:PLTaskStageStatusCompleted];
                    [m updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusRunning];
                    [m updateTaskWithId:taskId currentStageIndex:kStageInstall];
                    [m updateTaskWithId:taskId stageAtIndex:kStageInstall progress:MIN((p - split) / (1 - split), 1.0) message:message];
                }
            });
        };
        BOOL ok = neo
            ? [NeoForgeDirectInstaller installNeoForgeFromInstaller:filePath versionId:profileName progress:progress error:&error]
            : [ForgeDirectInstaller installForgeFromInstaller:filePath versionId:profileName progress:progress error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                if (taskId) {
                    [m updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusFailed];
                    [m setTaskWithId:taskId completedWithError:error ?: [NSError errorWithDomain:@"TerraVersionInstaller" code:2 userInfo:nil]];
                }
                [self alertTitle:[vendor stringByAppendingString:@" install failed"] message:error.localizedDescription ?: @"Unknown error"];
                return;
            }
            if (taskId) {
                [m updateTaskWithId:taskId stageAtIndex:kStageResolve status:PLTaskStageStatusCompleted];
                [m updateTaskWithId:taskId stageAtIndex:kStageInstall status:PLTaskStageStatusCompleted];
                [m updateTaskWithId:taskId stageAtIndex:kStageInstall progress:1 message:nil];
                [m setTaskWithId:taskId completedWithError:nil];
            }
            [self finishWithSuccess:[NSString stringWithFormat:@"%@ for Minecraft %@ is installed.", vendor, gameVersion]
                          versionId:profileName];
        });
    });
}

+ (LauncherNavigationController *)findLauncherNavigationIn:(UIViewController *)vc {
    if (!vc) return nil;
    if ([vc isKindOfClass:LauncherNavigationController.class]) return (LauncherNavigationController *)vc;
    NSMutableArray *children = [vc.childViewControllers mutableCopy];
    if ([vc isKindOfClass:UINavigationController.class]) [children addObjectsFromArray:((UINavigationController *)vc).viewControllers];
    if ([vc isKindOfClass:UISplitViewController.class]) [children addObjectsFromArray:((UISplitViewController *)vc).viewControllers];
    if (vc.presentedViewController) [children addObject:vc.presentedViewController];
    for (UIViewController *child in children) {
        LauncherNavigationController *found = [self findLauncherNavigationIn:child];
        if (found) return found;
    }
    return nil;
}

@end
