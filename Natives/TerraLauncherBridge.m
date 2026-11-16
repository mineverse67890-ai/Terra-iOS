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
    self.remoteVersions = [NSMutableArray new];
    self.localVersions = [NSMutableArray new];
    [self terraLoadLocalVersions];
    [self terraFetchRemoteVersions];

    // Ask the right panel to broadcast its state (username / version / JIT)
    [[NSNotificationCenter defaultCenter] postNotificationName:AmeRightPanelRequestStateNotification
                                                        object:nil
                                                      userInfo:nil];
}


#pragma mark - Snapshot

- (NSDictionary *)snapshot {
    NSMutableArray *instances = [NSMutableArray array];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *instancesRoot = [docs stringByAppendingPathComponent:@"instances"];
    NSDictionary *profiles = [PLProfiles.current profiles] ?: @{};

    NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:instancesRoot error:nil] ?: @[];
    for (NSString *dirName in dirs) {
        NSString *instanceRoot = [instancesRoot stringByAppendingPathComponent:dirName];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:instanceRoot isDirectory:&isDir] || !isDir) continue;

        // Game dir: <instance>/minecraft (preferred) or the instance dir itself
        NSString *mcDir = [instanceRoot stringByAppendingPathComponent:@"minecraft"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:mcDir]) mcDir = instanceRoot;

        // Version: profile lastVersionId, else first folder in versions/
        NSString *version = profiles[dirName][@"lastVersionId"];
        if (version.length == 0) {
            NSString *versionsDir = [mcDir stringByAppendingPathComponent:@"versions"];
            NSArray *vers = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:versionsDir error:nil];
            for (NSString *v in vers) {
                BOOL vIsDir = NO;
                NSString *vPath = [versionsDir stringByAppendingPathComponent:v];
                if ([[NSFileManager defaultManager] fileExistsAtPath:vPath isDirectory:&vIsDir] && vIsDir) {
                    version = v;
                    break;
                }
            }
        }

        // Loader detection: peek into the version JSON
        NSString *loader = @"vanilla";
        if (version.length > 0) {
            NSString *jsonPath = [[mcDir stringByAppendingPathComponent:@"versions"]
                                   stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@.json", version, version]];
            NSString *json = [NSString stringWithContentsOfFile:jsonPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
            if ([json containsString:@"fabric-loader"]) loader = @"fabric";
            else if ([json containsString:@"forge"]) loader = @"forge";
        }

        // Folder size (human readable)
        unsigned long long bytes = [self terraDirectorySize:mcDir];
        NSString *sizeText;
        if (bytes >= 1024ull * 1024ull * 1024ull) {
            sizeText = [NSString stringWithFormat:@"%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
        } else if (bytes >= 1024ull * 1024ull) {
            sizeText = [NSString stringWithFormat:@"%.0f MB", bytes / (1024.0 * 1024.0)];
        } else {
            sizeText = [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
        }

        // Last played (profile lastPlayed timestamp)
        NSNumber *lastPlayedNum = profiles[dirName][@"lastPlayed"];
        NSString *lastPlayed = @"";
        if (lastPlayedNum.doubleValue > 0) {
            NSDate *d = [NSDate dateWithTimeIntervalSince1970:lastPlayedNum.doubleValue];
            NSDateFormatter *f = [[NSDateFormatter alloc] init];
            f.dateStyle = NSDateFormatterMediumStyle;
            lastPlayed = [f stringFromDate:d];
        }

        [instances addObject:@{
            @"name": dirName,
            @"version": version ?: @"—",
            @"loader": loader,
            @"sizeText": sizeText ?: @"—",
            @"modsPath": [mcDir stringByAppendingPathComponent:@"mods"] ?: @"",
            @"lastPlayed": lastPlayed ?: @"",
        }];
    }

    NSString *selected = [PLProfiles.current selectedProfileName] ?: @"";
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
        [self terraPresentModsManagerForProfile:name];
    } else if ([cmd isEqualToString:@"openInstanceSettings"]) {
        // Per-installation settings: Java version, renderer, memory, JVM args, version isolation…
        if (name.length > 0) {
            ProfileSettingsViewController *vc = [[ProfileSettingsViewController alloc] init];
            vc.profileName = name;
            [self terraPresentLegacyVC:vc title:name];
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
    if (name.length == 0) return;
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *instanceRoot = [[docs stringByAppendingPathComponent:@"instances"]
                               stringByAppendingPathComponent:name];
    // Safety: only delete inside Documents/instances
    if (![instanceRoot hasPrefix:[docs stringByAppendingPathComponent:@"instances"]]) return;
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:instanceRoot error:&err];
    if (err) NSLog(@"[TERRA] delete instance failed: %@", err);
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

/// Answers FindVersionInRemoteList posted by the right panel during launch
- (void)terraFindVersion:(NSNotification *)note {
    NSString *versionId = note.userInfo[@"versionId"];
    void (^callback)(NSDictionary *) = note.userInfo[@"callback"];
    if (!versionId || !callback) return;

    NSDictionary *versionObject = nil;
    for (NSDictionary *v in self.remoteVersions) {
        if ([v[@"id"] isEqualToString:versionId]) { versionObject = v; break; }
    }
    if (!versionObject) {
        for (NSDictionary *v in self.localVersions) {
            if ([v[@"id"] isEqualToString:versionId]) { versionObject = v; break; }
        }
    }
    callback(versionObject);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end