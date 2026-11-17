// ===========================================================================
//  ★ [TERRA] TerraLauncherBridge.m —— Swift UI ↔ legacy ObjC launch pipeline
//  ---------------------------------------------------------------------------
//  TerraLauncherService:
//    · attachToRoot: hosts the invisible LauncherRightPanelViewController
//      (NORIGHT mode — the full original launch pipeline) on the SwiftUI root,
//      answers FindVersionInRemoteList (version manifest fetch), and handles
//      ShowAccountManager (login flow during launch).
//    · snapshot  — instance list (Documents/instances/<name>/minecraft/),
//                  selected profile, username, version, download source.
//    · invoke:   — launch / selectInstance / deleteInstance / openMods /
//                  openSettings / openAccount / installVersion / stateRequest.
//  Created & retained by the Swift side (TerraBridge, TerraTheme.swift).
//  ===========================================================================
#import "TerraLauncherBridge.h"
#import "LauncherRightPanelViewController.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "authenticator/BaseAuthenticator.h"
#import "AccountListViewController.h"
#import "ModsManagerViewController.h"
#import "LauncherPreferencesViewController.h"
#import "ProfileSettingsViewController.h"
#import "LauncherNavigationController.h"   // global localVersionList / remoteVersionList
#import "utils.h"

@interface TerraLauncherService ()
@property(nonatomic, strong) LauncherRightPanelViewController *panel;
@property(nonatomic, strong) NSMutableArray *remoteVersions;
@property(nonatomic, strong) NSMutableArray *localVersions;
@end

@implementation TerraLauncherService

+ (instancetype)shared {
    static TerraLauncherService *svc = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ svc = [[TerraLauncherService alloc] init]; });
    return svc;
}

#pragma mark - Attach

- (void)attachToRoot:(UIViewController *)root {
    // Idempotent: the root can be rebuilt (e.g. language change) — drop the previous
    // panel and observers so notifications are never handled twice.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.panel) {
        [self.panel willMoveToParentViewController:nil];
        [self.panel.view removeFromSuperview];
        [self.panel removeFromParentViewController];
        self.panel = nil;
    }

    // Invisible right panel: full original launch pipeline (account check,
    // version resolve, JIT, download progress) — zero logic copied.
    LauncherRightPanelViewController *panel = [[LauncherRightPanelViewController alloc] init];
    [root addChildViewController:panel];
    panel.view.translatesAutoresizingMaskIntoConstraints = YES;
    panel.view.frame = CGRectZero;
    panel.view.hidden = YES;
    [root.view addSubview:panel.view];
    [panel didMoveToParentViewController:root];
    [panel norightCollapsePanelLayout:YES];   // deactivate internal required constraints
    self.panel = panel;

    // Notification wiring
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(terraShowAccountManager:)
                                                 name:@"ShowAccountManager"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(terraFindVersion:)
                                                 name:@"FindVersionInRemoteList"
                                               object:nil];

    // Version manifest (for FindVersionInRemoteList / launch pipeline)
    // ★ [TERRA-FIX] Share the legacy global lists (normally filled by LauncherRootViewController,
    //   which the Terra UI never creates). MinecraftResourceDownloadTask and other launch code
    //   read these globals directly.
    if (!remoteVersionList) remoteVersionList = [NSMutableArray new];
    if (!localVersionList) localVersionList = [NSMutableArray new];
    self.remoteVersions = remoteVersionList;
    self.localVersions = localVersionList;
    [self terraLoadLocalVersions];
    [self terraFetchRemoteVersions];

    // Ask the right panel to broadcast its state (username / version / JIT)
    [[NSNotificationCenter defaultCenter] postNotificationName:AmeRightPanelRequestStateNotification
                                                        object:nil
                                                      userInfo:nil];
}


#pragma mark - New-screen lookup

/// Instantiates a new Terra screen by class name (so the bridge compiles before/without it)
/// and passes the installation name via -setProfileName: when supported.
- (nullable UIViewController *)terraNewScreen:(NSString *)className profile:(nullable NSString *)profile {
    Class cls = NSClassFromString(className);
    if (!cls || ![cls isSubclassOfClass:UIViewController.class]) return nil;
    UIViewController *vc = [[cls alloc] init];
    if (profile.length && [vc respondsToSelector:NSSelectorFromString(@"setProfileName:")]) {
        [vc setValue:profile forKey:@"profileName"];
    }
    return vc;
}

#pragma mark - Settings access

- (id)prefValue:(NSString *)key {
    return key.length ? getPrefObject(key) : nil;
}

- (void)setPrefValue:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    setPrefObject(key, value);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TerraPreferencesChanged" object:key];
    });
}

- (NSArray<NSDictionary *> *)rendererOptions {
    NSArray *keys = getRendererKeys(YES), *names = getRendererNames(YES);
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(keys.count, names.count); i++) {
        [out addObject:@{@"key": keys[i], @"name": names[i]}];
    }
    return out;
}

- (NSDictionary *)appInfo {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return @{
        @"version": info[@"CFBundleShortVersionString"] ?: @"",
        @"build": info[@"CFBundleVersion"] ?: @"",
        @"device": UIDevice.currentDevice.model ?: @"",
        @"system": [NSString stringWithFormat:@"%@ %@", UIDevice.currentDevice.systemName, UIDevice.currentDevice.systemVersion],
        @"memoryMB": @(NSProcessInfo.processInfo.physicalMemory / (1024 * 1024)),
    };
}

#pragma mark - JIT status

- (NSDictionary *)jitStatus {
    BOOL enabled = isJITEnabled(NO);
    // Jailbreak native JIT sets neither CS_DEBUGGED nor dynamic-codesigning: check real capability
    if (!enabled && AMEJailbreakNativeJITPathApplies() && AMEJailbreakNativeJITReady()) {
        enabled = YES;
    }
    // TXM devices: JIT can be enabled while the brk-servicing debugger has detached;
    // it reattaches on launch (recoverable), so report it separately from "not enabled".
    if (enabled && DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM) &&
        !JIT26IsLikelyDebuggerKeepAttached()) {
        return @{@"state": @"pending", @"text": localize(@"i18n_str_jit26_pending", nil)};
    }
    if (enabled) {
        return @{@"state": @"enabled", @"text": localize(@"i18n_str_421", nil)};
    }
    return @{@"state": @"disabled", @"text": localize(@"i18n_str_422", nil)};
}

#pragma mark - Snapshot

- (NSDictionary *)snapshot {
    // ★ [TERRA-FIX] Installations = launcher profiles of the current game folder
    //   (Documents/instances/<game folder>/launcher_profiles.json), exactly what the legacy
    //   launch pipeline reads. Listing the game folders themselves made PLAY select a profile
    //   that doesn't exist ("default") ⇒ "Unable to fetch version information".
    NSMutableArray *instances = [NSMutableArray array];
    NSDictionary *profiles = [PLProfiles.current profiles] ?: @{};
    // Game folder + loader per profile via TerraBrowseTarget (handles isolation + loader detection)
    NSMutableDictionary<NSString *, id> *targets = [NSMutableDictionary dictionary];
    Class targetClass = NSClassFromString(@"TerraBrowseTarget");
    if ([targetClass respondsToSelector:NSSelectorFromString(@"allTargets")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *all = [targetClass performSelector:NSSelectorFromString(@"allTargets")];
#pragma clang diagnostic pop
        for (id t in all) {
            NSString *n = [t valueForKey:@"name"];
            if (n) targets[n] = t;
        }
    }

    NSArray *names = [profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in names) {
        NSDictionary *prof = profiles[name];
        if (![prof isKindOfClass:NSDictionary.class]) continue;
        NSString *version = [prof[@"lastVersionId"] isKindOfClass:NSString.class] ? prof[@"lastVersionId"] : @"";

        NSString *gameDir = nil, *loader = @"vanilla";
        id target = targets[name];
        if (target) {
            gameDir = [target valueForKey:@"gameDir"];
            loader = [target valueForKey:@"loader"] ?: @"vanilla";
        }
        if (gameDir.length == 0) {
            const char *env = getenv("POJAV_GAME_DIR");
            gameDir = env ? @(env) : @"";
        }

        // Size of this version's files (versions/<id>), not the shared game folder
        NSString *sizeText = @"";
        if (version.length > 0 && ![version hasPrefix:@"latest-"]) {
            const char *env = getenv("POJAV_GAME_DIR");
            NSString *vdir = [[(env ? @(env) : gameDir) stringByAppendingPathComponent:@"versions"] stringByAppendingPathComponent:version];
            unsigned long long bytes = [self terraDirectorySize:vdir];
            if (bytes >= 1024ull * 1024ull * 1024ull) {
                sizeText = [NSString stringWithFormat:@"%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
            } else if (bytes >= 1024ull * 1024ull) {
                sizeText = [NSString stringWithFormat:@"%.0f MB", bytes / (1024.0 * 1024.0)];
            } else if (bytes > 0) {
                sizeText = [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
            }
        }

        NSNumber *lastPlayedNum = [prof[@"lastPlayed"] respondsToSelector:@selector(doubleValue)] ? prof[@"lastPlayed"] : nil;
        NSString *lastPlayed = @"";
        if (lastPlayedNum.doubleValue > 0) {
            NSDate *d = [NSDate dateWithTimeIntervalSince1970:lastPlayedNum.doubleValue];
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            f.dateStyle = NSDateFormatterMediumStyle;
            lastPlayed = [f stringFromDate:d];
        }

        NSString *displayVersion = version;
        if ([version isEqualToString:@"latest-release"]) displayVersion = @"Latest release";
        else if ([version isEqualToString:@"latest-snapshot"]) displayVersion = @"Latest snapshot";

        [instances addObject:@{
            @"name": name,
            @"version": displayVersion.length ? displayVersion : @"—",
            @"loader": loader,
            @"sizeText": sizeText.length ? sizeText : @"—",
            @"modsPath": [gameDir stringByAppendingPathComponent:@"mods"] ?: @"",
            @"lastPlayed": lastPlayed ?: @"",
        }];
    }

    NSString *selected = [PLProfiles.current selectedProfileName] ?: @"";
    if (!profiles[selected] && names.count > 0) selected = names.firstObject;
    NSString *username = @"Player";
    BaseAuthenticator *auth = BaseAuthenticator.current;
    NSString *authName = auth.authData[@"username"] ?: auth.authData[@"name"];
    if (authName.length > 0) username = authName;

    NSString *selVersion = profiles[selected][@"lastVersionId"] ?: @"";
    NSString *downloadSource = getPrefObject(@"general.download_source") ?: @"official";

    return @{
        @"instances": instances,
        @"selected": selected,
        @"username": username,
        @"version": selVersion,
        @"downloadSource": downloadSource,
    };
}

- (unsigned long long)terraDirectorySize:(NSString *)path {
    unsigned long long total = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enum_ = [fm enumeratorAtPath:path];
    for (NSString *rel in enum_) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:rel] error:nil];
        total += attrs.fileSize;
    }
    return total;
}


#pragma mark - Command channel

- (void)invoke:(NSString *)cmd payload:(NSDictionary *)payload {
    NSString *name = payload[@"name"];
    NSString *versionId = payload[@"versionId"];

    if ([cmd isEqualToString:@"launch"]) {
        if (name.length > 0) {
            [PLProfiles.current setSelectedProfileName:name];
            [PLProfiles.current save];
        }
        [LauncherRightPanelViewController norightPostAction:@"launch"];
    } else if ([cmd isEqualToString:@"selectInstance"]) {
        if (name.length > 0) {
            [PLProfiles.current setSelectedProfileName:name];
            [PLProfiles.current save];
            [self terraPostInstancesChanged];
        }
    } else if ([cmd isEqualToString:@"deleteInstance"]) {
        [self terraDeleteInstanceNamed:name];
    } else if ([cmd isEqualToString:@"openMods"]) {
        // New sidebar Mods manager (TerraModsManagerViewController) when present, else legacy.
        UIViewController *vc = [self terraNewScreen:@"TerraModsManagerViewController" profile:name];
        if (vc) [self terraPresentLegacyVC:vc title:nil];
        else [self terraPresentModsManagerForProfile:name];
    } else if ([cmd isEqualToString:@"openInstanceSettings"]) {
        // Per-installation settings: new screen when present, else legacy ProfileSettings.
        if (name.length > 0) {
            UIViewController *vc = [self terraNewScreen:@"TerraInstanceSettingsViewController" profile:name];
            if (!vc) {
                ProfileSettingsViewController *legacy = [[ProfileSettingsViewController alloc] init];
                legacy.profileName = name;
                vc = legacy;
            }
            [self terraPresentLegacyVC:vc title:name];
        }
    } else if ([cmd isEqualToString:@"openLegacyClass"]) {
        // Any screen by class name (used by the new Settings for advanced pages).
        // payload: className (required), profileName (optional, set via KVC if supported), title (optional)
        Class cls = NSClassFromString(payload[@"className"] ?: @"");
        if (cls && [cls isSubclassOfClass:UIViewController.class]) {
            UIViewController *vc = [[cls alloc] init];
            NSString *profile = payload[@"profileName"];
            if (profile.length && [vc respondsToSelector:NSSelectorFromString(@"setProfileName:")]) {
                [vc setValue:profile forKey:@"profileName"];
            }
            [self terraPresentLegacyVC:vc title:payload[@"title"]];
        } else {
            NSLog(@"[TERRA] openLegacyClass: unknown class %@", payload[@"className"]);
        }
    } else if ([cmd isEqualToString:@"openSettings"]) {
        [self terraPresentLegacyVC:[[LauncherPreferencesViewController alloc] init] title:nil];
    } else if ([cmd isEqualToString:@"openAccount"]) {
        [self terraShowAccountManager:nil];
    } else if ([cmd isEqualToString:@"installVersion"]) {
        [self terraInstallVersion:versionId];
    } else if ([cmd isEqualToString:@"stateRequest"]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:AmeRightPanelRequestStateNotification
                                                            object:nil
                                                          userInfo:nil];
    }
}

#pragma mark - Commands (implementations)

- (void)terraDeleteInstanceNamed:(NSString *)name {
    // ★ [TERRA-FIX] Delete only the installation (profile), like the official launcher.
    //   Game files (versions, worlds, mods) are shared by the game folder and stay untouched.
    if (name.length == 0) return;
    PLProfiles *profiles = PLProfiles.current;
    if (!profiles.profiles[name]) return;
    [profiles.profiles removeObjectForKey:name];
    if ([profiles.selectedProfileName isEqualToString:name]) {
        NSString *next = [profiles.profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)].firstObject;
        if (next) [profiles setSelectedProfileName:next];
    }
    [profiles save];
    [self terraLoadLocalVersions];
    [self terraPostInstancesChanged];
}

- (void)terraInstallVersion:(NSString *)versionId {
    if (versionId.length == 0) return;
    PLProfiles *profiles = PLProfiles.current;
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    profile[@"lastVersionId"] = versionId;
    profile[@"profileName"] = versionId;
    profile[@"gameDir"] = @".";
    profile[@"icon"] = @"default";
    [profiles saveProfile:profile withName:versionId];
    [profiles setSelectedProfileName:versionId];
    [profiles save];
    [self terraLoadLocalVersions];
    [self terraPostInstancesChanged];
}

- (void)terraPostInstancesChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TerraInstancesChanged"
                                                            object:nil
                                                          userInfo:nil];
    });
}

- (void)terraPresentModsManagerForProfile:(NSString *)profileName {
    ModsManagerViewController *mods = [[ModsManagerViewController alloc] init];
    mods.profileName = profileName;
    [self terraPresentLegacyVC:mods title:@"Mods"];
}

- (void)terraShowAccountManager:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        AccountListViewController *vc = [[AccountListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        vc.whenItemSelected = ^void() {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
        };
        vc.whenDelete = ^void(NSString *name) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"UpdateAccountInfo" object:nil];
        };
        [self terraPresentLegacyVC:vc title:nil];
    });
}

/// Present a legacy VC full-screen from the topmost presenter (SwiftUI root safe)
- (void)terraPresentLegacyVC:(UIViewController *)vc title:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = UIApplication.sharedApplication.windows.firstObject.rootViewController;
        NSUInteger guardCount = 0;
        while (guardCount++ < 16) {
            UIViewController *next = presenter.presentedViewController;
            if (next) { presenter = next; continue; }
            break;
        }
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        // Always show the bar: several legacy screens (Full Preferences, profile settings) have no
        // close button of their own, so a hidden bar left the user stuck with no way back.
        nav.navigationBarHidden = NO;
        if (title) vc.navigationItem.title = title;
        // Done button unless the screen already provides its own left item (screens that set
        // one later in viewDidLoad simply replace this).
        if (!vc.navigationItem.leftBarButtonItem) {
            __weak UINavigationController *weakNav = nav;
            vc.navigationItem.leftBarButtonItem =
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                       primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
                    [weakNav dismissViewControllerAnimated:YES completion:^{
                        // settings/mods may have changed the instance (version, loader, size)
                        [self terraPostInstancesChanged];
                    }];
                }]];
        }
        [presenter presentViewController:nav animated:YES completion:nil];
    });
}

#pragma mark - Version lists (launch pipeline support)

/// Local versions: <POJAV_GAME_DIR>/versions/<id> (same as legacy root VC)
- (void)terraLoadLocalVersions {
    [self.localVersions removeAllObjects];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    if (!gameDir) return;
    NSString *versionsPath = [NSString stringWithFormat:@"%s/versions/", gameDir];
    NSArray *list = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:versionsPath error:nil] ?: @[];
    for (NSString *versionId in list) {
        NSString *p = [NSString stringWithFormat:@"%s/versions/%@", gameDir, versionId];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&isDir] && isDir) {
            [self.localVersions addObject:@{@"id": versionId, @"type": @"custom"}];
        }
    }
}

/// Remote versions: version_manifest_v2 (Mojang / bmclapi per preference)
- (void)terraFetchRemoteVersions {
    [self.remoteVersions removeAllObjects];
    [self.remoteVersions addObjectsFromArray:@[
        @{@"id": @"latest-release", @"type": @"release"},
        @{@"id": @"latest-snapshot", @"type": @"snapshot"},
    ]];

    NSString *source = getPrefObject(@"general.download_source");
    NSString *manifestURL = [source isEqualToString:@"bmclapi"]
        ? @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
        : @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:manifestURL]
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (json[@"versions"]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.remoteVersions addObjectsFromArray:json[@"versions"]];
                    setPrefObject(@"internal.latest_version", json[@"latest"]);
                    NSLog(@"[TERRA] loaded %lu remote versions", (unsigned long)self.remoteVersions.count);
                });
            }
        } else {
            NSLog(@"[TERRA] failed to fetch version list: %@", error.localizedDescription);
        }
    }];
    [task resume];
}

/// Answers FindVersionInRemoteList posted by the right panel during launch.
/// ★ [TERRA-FIX] Robust lookup: re-scan local versions every time (installs happen after app
/// start), fetch the manifest on demand if it hasn't loaded, and accept any version whose JSON
/// exists on disk. Previously a not-yet-loaded / failed manifest ⇒ "Version information not found".
- (void)terraFindVersion:(NSNotification *)note {
    NSString *versionId = note.userInfo[@"versionId"];
    void (^callback)(NSDictionary *) = note.userInfo[@"callback"];
    if (!versionId || !callback) return;

    NSDictionary *(^lookup)(void) = ^NSDictionary *{
        if ([versionId isEqualToString:@"latest-release"] || [versionId isEqualToString:@"latest-snapshot"]) {
            NSDictionary *latest = getPrefObject(@"internal.latest_version");
            NSString *real = [latest isKindOfClass:NSDictionary.class]
                ? latest[[versionId isEqualToString:@"latest-release"] ? @"release" : @"snapshot"] : nil;
            if (real.length) {
                for (NSDictionary *v in self.remoteVersions) {
                    if ([v[@"id"] isEqual:real] && v[@"url"]) return v;
                }
            }
        }
        for (NSDictionary *v in self.remoteVersions) {
            if ([v[@"id"] isEqual:versionId] && (v[@"url"] || [versionId hasPrefix:@"latest-"])) return v;
        }
        [self terraLoadLocalVersions];
        for (NSDictionary *v in self.localVersions) {
            if ([v[@"id"] isEqual:versionId]) return v;
        }
        return nil;
    };

    NSDictionary *found = lookup();
    BOOL manifestLoaded = self.remoteVersions.count > 2;
    if (found && (manifestLoaded || ![versionId hasPrefix:@"latest-"])) {
        callback(found);
        return;
    }

    // Manifest not loaded yet (or failed earlier): fetch it now, then answer.
    NSString *source = getPrefObject(@"general.download_source");
    NSArray<NSString *> *urls = [source isEqualToString:@"bmclapi"]
        ? @[@"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json", @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"]
        : @[@"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json", @"https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"];
    [self terraFetchManifestFrom:urls index:0 completion:^{ callback(lookup()); }];
}

/// Fetch version_manifest_v2 from urls[index...] (first that works); completion on main queue.
- (void)terraFetchManifestFrom:(NSArray<NSString *> *)urls index:(NSUInteger)index completion:(void (^)(void))completion {
    if (index >= urls.count) {
        dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urls[index]]];
    req.timeoutInterval = 15;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *versions = [json isKindOfClass:NSDictionary.class] ? json[@"versions"] : nil;
        if (![versions isKindOfClass:NSArray.class]) {
            [self terraFetchManifestFrom:urls index:index + 1 completion:completion];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.remoteVersions removeAllObjects];
            [self.remoteVersions addObjectsFromArray:@[
                @{@"id": @"latest-release", @"type": @"release"},
                @{@"id": @"latest-snapshot", @"type": @"snapshot"},
            ]];
            [self.remoteVersions addObjectsFromArray:versions];
            if ([json[@"latest"] isKindOfClass:NSDictionary.class]) setPrefObject(@"internal.latest_version", json[@"latest"]);
            completion();
        });
    }] resume];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end