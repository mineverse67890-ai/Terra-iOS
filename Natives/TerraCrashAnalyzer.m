//
//  TerraCrashAnalyzer.m
//  ★ [TERRA-DIAG] Rule-based launch / crash diagnosis. Rules run in priority order; the first
//  match wins. Every rule returns a plain-English cause, the log line that proves it, and
//  fixes that point at the exact place in Terra's UI.
//

#import "TerraCrashAnalyzer.h"
#import "PLProfiles.h"
#import "utils.h"

#pragma mark - TerraDiagnosis

@implementation TerraDiagnosis

- (NSString *)reportText {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%@\n\n%@\n", self.title, self.summary];
    if (self.evidence.length > 0) {
        [s appendFormat:@"\nFound in the log:\n%@\n", self.evidence];
    }
    if (self.fixes.count > 0) {
        [s appendString:@"\nHow to fix:\n"];
        [self.fixes enumerateObjectsUsingBlock:^(NSString *fix, NSUInteger i, BOOL *stop) {
            [s appendFormat:@"%lu. %@\n", (unsigned long)(i + 1), fix];
        }];
    }
    return s;
}

@end

#pragma mark - Helpers

static TerraDiagnosis *TDMake(NSString *identifier, TerraDiagnosisSeverity severity, NSString *title,
                              NSString *summary, NSString *_Nullable evidence, NSArray<NSString *> *fixes) {
    TerraDiagnosis *d = [TerraDiagnosis new];
    d.identifier = identifier;
    d.severity = severity;
    d.title = title;
    d.summary = summary;
    d.evidence = evidence;
    d.fixes = fixes;
    return d;
}

/// First (or last) original-case line whose lowercase form contains any needle.
static NSString *_Nullable TDLine(NSArray<NSString *> *lines, NSArray<NSString *> *needles, BOOL last) {
    // Needles are in priority order: the most specific pattern wins, wherever it appears.
    for (NSString *n in needles) {
        NSEnumerator *e = last ? lines.reverseObjectEnumerator : lines.objectEnumerator;
        for (NSString *line in e) {
            if ([line.lowercaseString containsString:n]) {
                NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                return t.length > 300 ? [[t substringToIndex:300] stringByAppendingString:@"…"] : t;
            }
        }
    }
    return nil;
}

static BOOL TDHas(NSString *lower, NSArray<NSString *> *needles) {
    for (NSString *n in needles) if ([lower containsString:n]) return YES;
    return NO;
}

/// First capture group of the first regex match (case-insensitive).
static NSString *_Nullable TDCapture(NSString *text, NSString *pattern, NSUInteger group) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges <= group || [m rangeAtIndex:group].location == NSNotFound) return nil;
    return [text substringWithRange:[m rangeAtIndex:group]];
}

/// Reads at most maxBytes from the end of a file (logs can be many MB).
static NSString *TDTail(NSString *path, NSUInteger maxBytes) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return @"";
    unsigned long long size = [fh seekToEndOfFile];
    unsigned long long start = size > maxBytes ? size - maxBytes : 0;
    [fh seekToFileOffset:start];
    NSData *data = [fh readDataToEndOfFile];
    [fh closeFile];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    return s ?: @"";
}

static NSString *TDSettingsPath(NSString *setting) {
    return [NSString stringWithFormat:@"Installations → ⚙ (your installation) → %@", setting];
}

#pragma mark - TerraCrashAnalyzer

@implementation TerraCrashAnalyzer

+ (NSString *)latestLogPath {
    return [NSString stringWithFormat:@"%s/latestlog.txt", getenv("POJAV_HOME") ?: ""];
}

/// Folders a game may write crash-reports / hs_err files to (shared or version-isolated).
+ (NSArray<NSString *> *)candidateGameDirs {
    NSMutableOrderedSet<NSString *> *dirs = [NSMutableOrderedSet orderedSet];
    const char *gameDir = getenv("POJAV_GAME_DIR");
    NSString *profileName = PLProfiles.current.selectedProfileName;
    NSString *versionId = [PLProfiles.current.selectedProfile[@"lastVersionId"] description];
    if (gameDir) {
        NSString *g = @(gameDir);
        [dirs addObject:g];
        if (versionId.length) [dirs addObject:[[g stringByAppendingPathComponent:@"versions"] stringByAppendingPathComponent:versionId]];
    }
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs && profileName.length) {
        [dirs addObject:[[[docs stringByAppendingPathComponent:@"instances"] stringByAppendingPathComponent:profileName]
                          stringByAppendingPathComponent:@"minecraft"]];
    }
    return dirs.array;
}

/// Newest file in `dir` matching prefix/suffix modified in the last `maxAge` seconds.
+ (NSString *_Nullable)newestFileIn:(NSString *)dir prefix:(NSString *)prefix suffix:(NSString *)suffix maxAge:(NSTimeInterval)maxAge {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *best = nil; NSDate *bestDate = nil;
    for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
        if (![name hasPrefix:prefix] || ![name hasSuffix:suffix]) continue;
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSDate *mod = [fm attributesOfItemAtPath:path error:nil].fileModificationDate;
        if (!mod || -mod.timeIntervalSinceNow > maxAge) continue;
        if (!bestDate || [mod compare:bestDate] == NSOrderedDescending) { best = path; bestDate = mod; }
    }
    return best;
}

/// Recent Minecraft crash report and JVM fatal-error file (only ones from this session-ish).
+ (NSArray<NSString *> *)recentCrashFiles {
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *dir in [self candidateGameDirs]) {
        NSString *report = [self newestFileIn:[dir stringByAppendingPathComponent:@"crash-reports"]
                                       prefix:@"crash-" suffix:@".txt" maxAge:30 * 60];
        if (report && ![files containsObject:report]) [files addObject:report];
        NSString *hsErr = [self newestFileIn:dir prefix:@"hs_err" suffix:@".log" maxAge:30 * 60];
        if (hsErr && ![files containsObject:hsErr]) [files addObject:hsErr];
    }
    return files;
}

+ (NSArray<NSURL *> *)logFileURLs {
    NSMutableArray *urls = [NSMutableArray array];
    if ([NSFileManager.defaultManager fileExistsAtPath:[self latestLogPath]]) {
        [urls addObject:[NSURL fileURLWithPath:[self latestLogPath]]];
    }
    for (NSString *f in [self recentCrashFiles]) [urls addObject:[NSURL fileURLWithPath:f]];
    return urls;
}

+ (NSString *)latestLogTail:(NSUInteger)maxBytes {
    return TDTail([self latestLogPath], maxBytes);
}

+ (BOOL)currentJITEnabled {
    BOOL enabled = isJITEnabled(NO);
    if (!enabled && AMEJailbreakNativeJITPathApplies() && AMEJailbreakNativeJITReady()) enabled = YES;
    return enabled;
}

+ (TerraDiagnosis *)diagnoseWithExitCode:(NSInteger)exitCode stageName:(NSString *)stageName {
    NSMutableString *text = [[self latestLogTail:768 * 1024] mutableCopy];
    for (NSString *f in [self recentCrashFiles]) {
        [text appendFormat:@"\n\n===== %@ =====\n", f.lastPathComponent];
        [text appendString:TDTail(f, 256 * 1024)];
    }
    return [self diagnoseLog:text exitCode:exitCode jitEnabled:[self currentJITEnabled] stageName:stageName];
}

+ (TerraDiagnosis *)diagnoseLog:(NSString *)log exitCode:(NSInteger)exitCode
                     jitEnabled:(BOOL)jitEnabled stageName:(NSString *)stageName {
    BOOL loading = (exitCode == NSNotFound);
    NSString *lower = log.lowercaseString;
    NSArray<NSString *> *lines = [log componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSString *ev = nil;

    // 1. JIT — without it the JVM is unusably slow or crashes outright on iOS.
    if (!jitEnabled) {
        return TDMake(@"jit", TerraDiagnosisSeverityProblem, @"JIT is not enabled",
            @"Java needs JIT (just-in-time compilation) to run Minecraft at a usable speed. iOS only allows it while a debugger is attached, so it has to be turned on with a sideloading tool. Without it the game hangs on loading or crashes.",
            TDLine(lines, @[@"jit", @"cs_debugged"], YES),
            @[@"TrollStore: JIT is enabled automatically — reinstall Terra with the .tipa build if you used the .ipa.",
              @"StikDebug / SideStore: open the tool and enable JIT for Terra, then come back. The JIT status above the PLAY button turns green when it works.",
              @"AltStore: make sure AltServer is running on a computer on the same Wi-Fi, then use Enable JIT.",
              @"iOS 17 or later needs a computer the first time — see the JIT guide linked in the README."]);
    }

    // 2. Out of memory (Java heap or iOS killing the app).
    if (exitCode == 9 ||
        TDHas(lower, @[@"outofmemoryerror", @"java heap space", @"gc overhead limit", @"cannot allocate memory",
                       @"failed to allocate", @"insufficient memory", @"jetsam"])) {
        ev = TDLine(lines, @[@"outofmemoryerror", @"java heap space", @"gc overhead", @"cannot allocate", @"failed to allocate", @"jetsam"], NO);
        return TDMake(@"oom", TerraDiagnosisSeverityProblem, @"Not enough memory",
            @"The game ran out of memory. Either Java's memory limit was too small for this game and its mods, or iOS closed Terra because the device itself ran low on memory.",
            ev,
            @[@"Close other apps (especially games and browsers), then try again.",
              [NSString stringWithFormat:@"If the log mentions \"Java heap space\": raise %@ a little.", TDSettingsPath(@"Memory Allocation")],
              @"If iOS closed the app (no Java error, sudden exit): lower the memory allocation instead — around half of your device's RAM is the safe maximum.",
              @"Remove heavy mods, high-resolution resource packs and shader packs.",
              @"Lower render distance in the game's Video Settings.",
              @"TrollStore installs get a higher memory limit than AltStore/SideStore."]);
    }

    // 3. Java too old for the game or a mod.
    NSString *classVer = TDCapture(log, @"class file version (\\d+)(?:\\.\\d+)?\\), this version", 1)
                      ?: TDCapture(log, @"compiled by a more recent version of the java runtime \\(class file version (\\d+)", 1);
    if (classVer || TDHas(lower, @[@"unsupportedclassversionerror", @"unsupported major.minor version"])) {
        NSInteger needed = classVer.integerValue > 44 ? classVer.integerValue - 44 : 0;
        NSString *need = needed > 0 ? [NSString stringWithFormat:@"Java %ld", (long)needed] : @"a newer Java version";
        return TDMake(@"java-version", TerraDiagnosisSeverityProblem,
            [NSString stringWithFormat:@"Needs %@", need],
            [NSString stringWithFormat:@"The game or one of its mods was built for %@, but an older Java was used to launch it.", need],
            TDLine(lines, @[@"unsupportedclassversionerror", @"class file version"], NO),
            @[[NSString stringWithFormat:@"Open %@ and choose Auto (recommended) or %@.", TDSettingsPath(@"Java Version"), need],
              @"If only one mod causes this, that mod is for a newer Minecraft version — remove it or download the version made for your game version.",
              @"Global defaults live in Settings → Full Preferences → Manage Java runtimes."]);
    }

    // 4. Missing mod dependency (Fabric / Quilt / Forge resolution errors).
    NSString *needer = TDCapture(log, @"mod '([^']+)'[^\\n]*?requires[^\\n]*?'([^']+)'[^\\n]*?which is missing", 1);
    NSString *missing = TDCapture(log, @"mod '([^']+)'[^\\n]*?requires[^\\n]*?'([^']+)'[^\\n]*?which is missing", 2);
    if (!missing) missing = TDCapture(log, @"mod id: '([^']+)', requested by", 1);
    if (missing || TDHas(lower, @[@"missing or unsupported mandatory dependencies", @"incompatible mod set",
                                  @"which is missing!", @"missing dependency"])) {
        ev = TDLine(lines, @[@"which is missing", @"requested by", @"incompatible mod set", @"mandatory dependencies"], NO);
        NSString *what = missing ? [NSString stringWithFormat:@"\"%@\"", missing] : @"a required mod";
        NSString *who = needer ? [NSString stringWithFormat:@"\"%@\"", needer] : @"One of your mods";
        return TDMake(@"missing-dependency", TerraDiagnosisSeverityProblem, @"A required mod is missing",
            [NSString stringWithFormat:@"%@ needs %@ to work, but it isn't installed (or the installed version is wrong).", who, what],
            ev,
            @[[NSString stringWithFormat:@"Install %@: Download Center → Fabric Mods, search for it, and install it into this installation.", what],
              @"Make sure it's the version made for your Minecraft version and mod loader.",
              [NSString stringWithFormat:@"Or remove %@ from %@.", needer ? who : @"the mod that needs it", TDSettingsPath(@"Mod Manager")]]);
    }

    // 5. Duplicate mods.
    if (TDHas(lower, @[@"duplicate mod", @"duplicatemodsfoundexception", @"found duplicate mods", @"duplicate mods"])) {
        return TDMake(@"duplicate-mods", TerraDiagnosisSeverityProblem, @"The same mod is installed twice",
            @"Two copies of the same mod (often two different versions) are in the mods folder, so the mod loader refuses to start.",
            TDLine(lines, @[@"duplicate mod", @"duplicate"], NO),
            @[[NSString stringWithFormat:@"Open %@ and delete the older copy.", TDSettingsPath(@"Mod Manager")],
              @"Updating a mod keeps the old file by default — check for leftovers after updates."]);
    }

    // 6. Mixin failure (a mod failed to patch the game).
    if (TDHas(lower, @[@"mixin apply failed", @"mixinapplyerror", @"invalidmixinexception", @"invalidinjectionexception",
                       @"mixin transformation of", @"mixintransformererror", @"injection failure", @"mixinexception"])) {
        NSString *modId = TDCapture(log, @"mixin apply(?: for mod)? ([a-z0-9_\\-]+) failed", 1)
                       ?: TDCapture(log, @"from mod ([a-z0-9_\\-]+)", 1)
                       ?: TDCapture(log, @"([a-z0-9_\\-]+)\\.mixins?\\.json", 1);
        NSString *mod = modId ? [NSString stringWithFormat:@"\"%@\"", modId] : @"one of your mods";
        return TDMake(@"mixin", TerraDiagnosisSeverityProblem, @"A mod is incompatible",
            [NSString stringWithFormat:@"%@ tried to modify the game and failed. This usually means the mod is made for a different Minecraft version, or it conflicts with another mod.", modId ? [@"The mod " stringByAppendingString:mod] : @"A mod"],
            TDLine(lines, @[@"mixin apply", @"mixinapplyerror", @"invalidmixin", @"invalidinjection", @"mixin transformation", @"injection failure", @"mixinexception"], NO),
            @[[NSString stringWithFormat:@"Update or remove %@ in %@.", mod, TDSettingsPath(@"Mod Manager")],
              @"Check the mod's download page says it supports your exact Minecraft version.",
              @"If you added several mods at once, remove them one by one to find the conflict."]);
    }

    // 7. Mod / version incompatibility at runtime.
    //    (skipped while loading: healthy logs often contain these from optional mod-compat probes)
    if (!loading && TDHas(lower, @[@"nosuchmethoderror", @"nosuchfielderror", @"abstractmethoderror", @"incompatibleclasschangeerror",
                       @"classcastexception", @"illegalaccesserror"])) {
        return TDMake(@"incompatible-mod", TerraDiagnosisSeverityProblem, @"Mod or version mismatch",
            @"Code from a mod expected something in the game (or in another mod) that isn't there. A mod is built for a different Minecraft or mod-loader version.",
            TDLine(lines, @[@"nosuchmethoderror", @"nosuchfielderror", @"abstractmethoderror", @"incompatibleclasschange",
                            @"classcastexception", @"illegalaccesserror"], NO),
            @[@"The mod named in the line above (or in the lines just before it) is the likely cause.",
              [NSString stringWithFormat:@"Update it, or remove it from %@.", TDSettingsPath(@"Mod Manager")],
              @"Make sure Fabric API / Forge is up to date for your Minecraft version."]);
    }

    // 8. Missing classes: missing dependency, wrong loader, or broken install.
    //    (skipped while loading: optional integrations log ClassNotFoundException harmlessly)
    if (!loading && TDHas(lower, @[@"classnotfoundexception", @"noclassdeffounderror"])) {
        return TDMake(@"missing-class", TerraDiagnosisSeverityProblem, @"Missing game or mod files",
            @"Something the game needs couldn't be found. Usually a mod depends on another mod that isn't installed, a mod is for a different mod loader (Forge mod on Fabric, or the reverse), or the game files are incomplete.",
            TDLine(lines, @[@"classnotfoundexception", @"noclassdeffounderror"], NO),
            @[@"If the missing name contains a mod's name (e.g. \"fabric\", \"cloth\", \"architectury\"), install that library mod from the Download Center.",
              @"Check every mod matches this installation's loader (Fabric / Forge / Quilt).",
              @"If no mods are involved, reinstall this Minecraft version from the Download Center to re-download its files."]);
    }

    // 9. Native library missing / failed to load.
    if (TDHas(lower, @[@"unsatisfiedlinkerror", @"failed to load library", @"dlopen("])) {
        return TDMake(@"native-library", TerraDiagnosisSeverityProblem, @"A native library failed to load",
            @"A part of the game written for the device (graphics, sound or a mod's native code) couldn't be loaded on iOS.",
            TDLine(lines, @[@"unsatisfiedlinkerror", @"failed to load library", @"dlopen("], NO),
            @[[NSString stringWithFormat:@"Switch renderer: %@ → try Auto, then MobileGlues, then Zink.", TDSettingsPath(@"Renderer")],
              @"Mods with native code built for PC (some performance or voice-chat mods) don't work on iOS — remove them.",
              @"Reinstall the app if the problem appears with no mods at all."]);
    }

    // 10. Shader packs.
    if (TDHas(lower, @[@"iris", @"oculus", @"shaderpack"]) &&
        TDHas(lower, @[@"failed to compile", @"shader compilation", @"shaderpack error", @"error while loading shader",
                       @"exception while loading shader"])) {
        return TDMake(@"shaders", TerraDiagnosisSeverityProblem, @"Shader pack failed",
            @"The selected shader pack couldn't be compiled for this device's graphics.",
            TDLine(lines, @[@"failed to compile", @"shader compilation", @"shaderpack"], NO),
            @[[NSString stringWithFormat:@"Turn the shader pack off in %@, or delete it.", TDSettingsPath(@"Shader Manager")],
              @"Try a lighter shader pack (e.g. \"lite\" / \"low\" versions).",
              [NSString stringWithFormat:@"Some shaders only work with a specific renderer — try another in %@.", TDSettingsPath(@"Renderer")]]);
    }

    // 11. Graphics / renderer.
    if (TDHas(lower, @[@"failed to create context", @"no opengl context", @"glfw error", @"egl_bad", @"eglcreatecontext",
                       @"pixel format not accelerated", @"opengl error", @"gl_invalid", @"does not support mc", @"samplerbuffer"])) {
        return TDMake(@"renderer", TerraDiagnosisSeverityProblem, @"Graphics renderer problem",
            @"The graphics translation layer couldn't give Minecraft what it needs on this device.",
            TDLine(lines, @[@"failed to create context", @"no opengl context", @"glfw error", @"egl_", @"pixel format",
                            @"opengl error", @"gl_invalid", @"does not support mc", @"samplerbuffer"], NO),
            @[[NSString stringWithFormat:@"Change the renderer in %@: start with Auto, then MobileGlues, then Zink.", TDSettingsPath(@"Renderer")],
              @"LTW doesn't support Minecraft 26.x — use MobileGlues or Zink for new versions.",
              @"Disable shader packs while testing.",
              @"Lower the resolution scale in Settings → Full Preferences → Video if the device is older."]);
    }

    // 12. Sign-in / session.
    if (TDHas(lower, @[@"invalid session", @"failed to verify username", @"not authenticated", @"invalidcredentials",
                       @"401 unauthorized", @"couldn't log in", @"token expired"])) {
        return TDMake(@"auth", TerraDiagnosisSeverityWarning, @"Account sign-in expired",
            @"Your account's session is no longer valid, so online features (servers, skins, Realms) are refused.",
            TDLine(lines, @[@"invalid session", @"failed to verify", @"not authenticated", @"invalidcredentials", @"401", @"couldn't log in", @"token expired"], NO),
            @[@"Tap your account at the top of the sidebar, remove it, and sign in again.",
              @"Make sure the device's date and time are set automatically."]);
    }

    // 13. Corrupted world.
    if (!loading &&
        (TDHas(lower, @[@"failed to load level", @"exception reading level", @"corrupted chunk", @"corrupt level.dat"]) ||
         ([lower containsString:@"level.dat"] && [lower containsString:@"corrupt"]))) {
        return TDMake(@"world", TerraDiagnosisSeverityProblem, @"World data looks damaged",
            @"The game crashed while reading a world's save files.",
            TDLine(lines, @[@"failed to load level", @"exception reading", @"level.dat", @"region file"], NO),
            @[[NSString stringWithFormat:@"Open %@ and restore a backup (level.dat_old) or try another world.", TDSettingsPath(@"World Manager")],
              @"If it happened after adding a mod that adds blocks or items, the world may need that mod installed."]);
    }

    // 14. JVM native crash.
    BOOL nativeCrash = exitCode == 11 || exitCode == 10 ||
        TDHas(lower, @[@"a fatal error has been detected by the java runtime", @"sigsegv", @"sigbus", @"exc_bad_access"]);
    if (nativeCrash) {
        return TDMake(@"native-crash", TerraDiagnosisSeverityProblem, @"The game crashed at a low level",
            @"Java itself crashed (a memory access error), usually in graphics code or a mod with native code.",
            TDLine(lines, @[@"fatal error has been detected", @"sigsegv", @"sigbus", @"problematic frame", @"exc_bad_access"], NO),
            @[[NSString stringWithFormat:@"Try a different renderer in %@ (Auto → MobileGlues → Zink).", TDSettingsPath(@"Renderer")],
              @"Check the JIT status above the PLAY button is green.",
              @"Remove recently added mods and shader packs.",
              @"Restart Terra (and the device if it keeps happening) to free memory."]);
    }

    // 15. Generic Java exception: show the root cause.
    NSString *rootCause = TDLine(lines, @[@"caused by:"], YES)
                       ?: TDLine(lines, @[@"exception in thread \"main\"", @"exception in thread \"render thread\""], NO);
    if (!loading && rootCause) {
        return TDMake(@"java-exception", TerraDiagnosisSeverityProblem, @"The game hit an error",
            @"Minecraft stopped because of an error in Java code. The line below is the root cause.",
            rootCause,
            @[@"If the line names a mod (or a package like com.<author>.<mod>), update or remove that mod.",
              @"If you just added mods, remove them and add them back one at a time.",
              @"Share the log (button below) when asking for help — it contains the full error."]);
    }

    if (loading) {
        NSString *stage = stageName.length ? stageName : @"starting";
        return TDMake(@"loading-ok", TerraDiagnosisSeverityOK, @"No problems found so far",
            [NSString stringWithFormat:@"Nothing in the log points to a problem yet. Current step: %@.", stage],
            nil,
            @[@"The first launch of a version can take a few minutes while files are prepared.",
              @"If it stays on one step for more than 2–3 minutes, tap Re-check — new errors show up here as they happen.",
              @"Keep Terra in the foreground; iOS pauses apps in the background."]);
    }

    if (exitCode == 0) {
        return TDMake(@"normal-exit", TerraDiagnosisSeverityOK, @"The game closed normally",
            @"Minecraft exited without an error.", nil, @[]);
    }

    return TDMake(@"unknown", TerraDiagnosisSeverityWarning,
        [NSString stringWithFormat:@"Game stopped (code %ld)", (long)exitCode],
        @"No known cause was found in the log.",
        TDLine(lines, @[@"error", @"exception"], YES),
        @[@"Try launching once more — some failures are one-off.",
          [NSString stringWithFormat:@"Try another renderer in %@.", TDSettingsPath(@"Renderer")],
          @"Remove recently added mods.",
          @"Share the log (button below) when asking for help."]);
}

@end
