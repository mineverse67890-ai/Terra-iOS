//
//  TerraBrowseAPI.m
//  ★ [TERRA-BROWSE] see TerraBrowseAPI.h
//

#import "TerraBrowseAPI.h"
#import <CommonCrypto/CommonDigest.h>
#import "utils.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "PLMirrorCenter.h"
#import "ModDependencyResolver.h"

/// CurseForgeAPI is looked up at runtime (its header drags in UnzipKit/ModpackUtils, which are
/// not nullability-annotated). Only these two selectors are used.
@protocol TerraCurseForgeAPIClass <NSObject>
+ (BOOL)isAPIKeyConfigured;
+ (id)sharedInstance;
@end
static Class<TerraCurseForgeAPIClass> TBCurseForgeClass(void) {
    return (Class<TerraCurseForgeAPIClass>)NSClassFromString(@"CurseForgeAPI");
}

NSString *const TerraBrowseErrorDomain = @"TerraBrowse";

static NSString *const kModrinthBase = @"https://api.modrinth.com/v2";
static NSString *const kCurseForgeBase = @"https://api.curseforge.com/v1";

#pragma mark - Small helpers

static NSString *TBStr(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

static NSString *TBEncode(NSString *value) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [value ?: @"" stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSString *TBJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
}

static NSString *TBQueryString(NSArray<NSArray<NSString *> *> *pairs) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSArray<NSString *> *pair in pairs) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", TBEncode(pair[0]), TBEncode(pair[1])]];
    }
    return [parts componentsJoinedByString:@"&"];
}

static NSDate *TBDate(id value) {
    NSString *s = TBStr(value);
    if (s.length == 0) return nil;
    static NSISO8601DateFormatter *frac, *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        frac = [NSISO8601DateFormatter new];
        frac.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        plain = [NSISO8601DateFormatter new];
        plain.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return [frac dateFromString:s] ?: [plain dateFromString:s];
}

static NSString *TBSHA1OfFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
#pragma clang diagnostic pop
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *TBGameDirEnv(void) {
    const char *env = getenv("POJAV_GAME_DIR");
    return env ? @(env) : NSHomeDirectory();
}

/// Loader / platform names that Modrinth mixes into categories.
static NSSet<NSString *> *TBLoaderTags(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"fabric", @"forge", @"neoforge", @"quilt", @"liteloader", @"modloader",
                                    @"rift", @"babric", @"bta-babric", @"java-agent", @"legacy-fabric",
                                    @"nilloader", @"ornithe", @"iris", @"optifine", @"canvas", @"vanilla",
                                    @"minecraft", @"datapack", @"bukkit", @"paper", @"spigot", @"folia",
                                    @"purpur", @"sponge", @"velocity", @"waterfall", @"bungeecord"]];
    });
    return set;
}

static NSString *TBPrettyTag(NSString *slug) {
    NSString *s = [slug stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    if (s.length == 0) return s;
    return [[s substringToIndex:1].uppercaseString stringByAppendingString:[s substringFromIndex:1]];
}

#pragma mark - Target

@implementation TerraBrowseTarget

- (NSString *)loaderDisplayName { return [TerraBrowseAPI displayNameForLoader:self.loader]; }
- (BOOL)hasModLoader { return ![self.loader isEqualToString:@"vanilla"]; }

- (NSString *)folderForContentType:(NSString *)contentType {
    NSString *sub = @"mods";
    if ([contentType isEqualToString:@"shader"]) sub = @"shaderpacks";
    else if ([contentType isEqualToString:@"resourcepack"]) sub = @"resourcepacks";
    else if ([contentType isEqualToString:@"datapack"]) sub = @"datapacks";
    return [self.gameDir stringByAppendingPathComponent:sub];
}

- (NSString *)ensureFolderForContentType:(NSString *)contentType {
    NSString *folder = [self folderForContentType:contentType];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[TerraBrowse] cannot create %@: %@", folder, error);
        return nil;
    }
    return folder;
}

+ (void)detectVersionId:(NSString *)versionId gameDir:(NSString *)gameDir
            gameVersion:(NSString **)gameVersionOut loader:(NSString **)loaderOut {
    NSString *vid = versionId ?: @"";
    if ([vid hasPrefix:@"latest-"]) {
        NSDictionary *latest = getPrefObject(@"internal.latest_version");
        NSString *resolved = [latest isKindOfClass:NSDictionary.class]
            ? TBStr(latest[[vid isEqualToString:@"latest-snapshot"] ? @"snapshot" : @"release"]) : nil;
        if (resolved.length) vid = resolved;
    }
    NSString *loader = @"vanilla";
    NSString *game = vid;
    NSMutableArray *dirs = [NSMutableArray arrayWithObject:TBGameDirEnv()];
    if (gameDir.length) [dirs addObject:gameDir];
    NSDictionary *json = nil;
    NSString *raw = nil;
    for (NSString *dir in dirs) {
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"versions/%@/%@.json", vid, vid]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:NSDictionary.class]) {
            json = obj;
            raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].lowercaseString;
            break;
        }
    }
    NSString *lowerId = vid.lowercaseString;
    NSString *haystack = raw ?: lowerId;
    if ([haystack containsString:@"net.neoforged"] || [lowerId containsString:@"neoforge"]) loader = @"neoforge";
    else if ([haystack containsString:@"org.quiltmc:quilt-loader"] || [lowerId containsString:@"quilt-loader"]) loader = @"quilt";
    else if ([haystack containsString:@"net.fabricmc:fabric-loader"] || [lowerId containsString:@"fabric-loader"]) loader = @"fabric";
    else if ([haystack containsString:@"net.minecraftforge"] || [lowerId containsString:@"forge"]) loader = @"forge";

    NSString *inherits = TBStr(json[@"inheritsFrom"]);
    if (inherits.length) {
        game = inherits;
    } else if (![loader isEqualToString:@"vanilla"]) {
        // No JSON: guess from the id ("fabric-loader-0.16-1.21.1", "1.20.1-forge-47.3.0", "neoforge-21.1.77")
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+\\.\\d+(\\.\\d+)?)" options:0 error:nil];
        NSArray<NSTextCheckingResult *> *matches = [re matchesInString:vid options:0 range:NSMakeRange(0, vid.length)];
        if ([loader isEqualToString:@"fabric"] || [loader isEqualToString:@"quilt"]) {
            if (matches.count) game = [vid substringWithRange:matches.lastObject.range];
        } else if ([loader isEqualToString:@"forge"]) {
            if (matches.count) game = [vid substringWithRange:matches.firstObject.range];
        } else if ([loader isEqualToString:@"neoforge"] && matches.count) {
            // NeoForge 21.1.x → MC 1.21.1, 20.4.x → 1.20.4
            NSArray *parts = [[vid substringWithRange:matches.firstObject.range] componentsSeparatedByString:@"."];
            if (parts.count >= 2) game = [parts[1] integerValue] == 0
                ? [NSString stringWithFormat:@"1.%@", parts[0]]
                : [NSString stringWithFormat:@"1.%@.%@", parts[0], parts[1]];
        }
    }
    if (gameVersionOut) *gameVersionOut = game;
    if (loaderOut) *loaderOut = loader;
}

+ (TerraBrowseTarget *)targetWithName:(NSString *)name versionId:(NSString *)versionId gameDir:(NSString *)gameDir {
    TerraBrowseTarget *t = [TerraBrowseTarget new];
    t.name = name;
    t.versionId = versionId ?: @"";
    t.gameDir = gameDir.length ? gameDir : TBGameDirEnv();
    NSString *game = nil, *loader = nil;
    [self detectVersionId:t.versionId gameDir:t.gameDir gameVersion:&game loader:&loader];
    t.gameVersion = game ?: @"";
    t.loader = loader ?: @"vanilla";
    return t;
}

+ (NSArray<TerraBrowseTarget *> *)allTargets {
    NSMutableArray<TerraBrowseTarget *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSDictionary *profiles = PLProfiles.current.profiles ?: @{};
    for (NSString *name in [profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        NSDictionary *prof = profiles[name];
        if (![prof isKindOfClass:NSDictionary.class]) continue;
        NSString *versionId = TBStr(prof[@"lastVersionId"]);
        if (versionId.length == 0) continue;
        NSString *gameDir = nil;
        @try { gameDir = amePCLVersionGameDirAbsolute(prof, nil); } @catch (NSException *e) { gameDir = nil; }
        if (![gameDir isKindOfClass:NSString.class] || gameDir.length == 0) gameDir = TBGameDirEnv();
        [out addObject:[self targetWithName:name versionId:versionId gameDir:gameDir]];
        [seen addObject:name];
    }
    // Installation folders the Terra launcher lists (Documents/instances/<name>[/minecraft]).
    // Same rules as TerraLauncherService -snapshot, without its expensive folder-size walk.
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *root = [docs stringByAppendingPathComponent:@"instances"];
    for (NSString *name in [[fm contentsOfDirectoryAtPath:root error:nil] ?: @[] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        if ([seen containsObject:name] || [name hasPrefix:@"."]) continue;
        NSString *dir = [root stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSString *mcDir = [dir stringByAppendingPathComponent:@"minecraft"];
        if (![fm fileExistsAtPath:mcDir]) mcDir = dir;
        NSString *version = nil;
        NSString *versionsDir = [mcDir stringByAppendingPathComponent:@"versions"];
        for (NSString *v in [fm contentsOfDirectoryAtPath:versionsDir error:nil] ?: @[]) {
            BOOL vDir = NO;
            if ([fm fileExistsAtPath:[versionsDir stringByAppendingPathComponent:v] isDirectory:&vDir] && vDir) { version = v; break; }
        }
        [out addObject:[self targetWithName:name versionId:version ?: @"" gameDir:mcDir]];
        [seen addObject:name];
    }
    return out;
}

+ (TerraBrowseTarget *)targetNamed:(NSString *)name {
    if (name.length == 0) return nil;
    for (TerraBrowseTarget *t in [self allTargets]) {
        if ([t.name isEqualToString:name]) return t;
    }
    return nil;
}

+ (TerraBrowseTarget *)defaultTarget {
    NSArray *all = [self allTargets];
    NSString *selected = PLProfiles.current.selectedProfileName;
    for (TerraBrowseTarget *t in all) {
        if ([t.name isEqualToString:selected]) return t;
    }
    return all.firstObject;
}

@end

#pragma mark - Models

@implementation TerraBrowseProject
- (instancetype)init {
    if ((self = [super init])) {
        _projectId = @""; _title = @""; _author = @""; _summary = @"";
        _categories = @[]; _loaders = @[]; _contentType = @"mod";
    }
    return self;
}
@end

@implementation TerraBrowseFile
- (instancetype)init {
    if ((self = [super init])) {
        _projectId = @""; _versionId = @""; _name = @""; _versionNumber = @""; _fileName = @""; _url = @"";
        _gameVersions = @[]; _loaders = @[]; _releaseType = @"release";
    }
    return self;
}
@end

@implementation TerraBrowseQuery
- (instancetype)init {
    if ((self = [super init])) {
        _source = TerraBrowseSourceModrinth; _contentType = @"mod"; _text = @""; _categories = @[]; _limit = 20;
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone {
    TerraBrowseQuery *q = [TerraBrowseQuery new];
    q.source = self.source; q.contentType = self.contentType; q.text = self.text; q.loader = self.loader;
    q.gameVersion = self.gameVersion; q.categories = self.categories; q.sort = self.sort;
    q.offset = self.offset; q.limit = self.limit;
    return q;
}
@end

#pragma mark - API

@interface TerraBrowseAPI ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableArray *resolverQueue;
@property (nonatomic, assign) BOOL resolverBusy;
@end

@implementation TerraBrowseAPI

+ (instancetype)shared {
    static TerraBrowseAPI *api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ api = [TerraBrowseAPI new]; });
    return api;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.HTTPAdditionalHeaders = @{@"User-Agent": @"Terra-iOS-Launcher/1.0", @"Accept": @"application/json"};
        cfg.timeoutIntervalForRequest = 25;
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _cache = [NSCache new];
        _resolverQueue = [NSMutableArray array];
    }
    return self;
}

#pragma mark Formatting

+ (BOOL)curseForgeKeyConfigured { return [TBCurseForgeClass() isAPIKeyConfigured]; }

+ (NSString *)displayNameForLoader:(NSString *)loader {
    NSString *l = loader.lowercaseString ?: @"";
    if ([l isEqualToString:@"neoforge"]) return @"NeoForge";
    if ([l isEqualToString:@"forge"]) return @"Forge";
    if ([l isEqualToString:@"fabric"]) return @"Fabric";
    if ([l isEqualToString:@"quilt"]) return @"Quilt";
    if ([l isEqualToString:@"vanilla"] || l.length == 0) return @"Vanilla";
    return TBPrettyTag(l);
}

+ (NSString *)compactNumber:(long long)v {
    if (v >= 1000000000) return [NSString stringWithFormat:@"%.1fB", v / 1e9];
    if (v >= 1000000) return [NSString stringWithFormat:@"%.1fM", v / 1e6];
    if (v >= 1000) return [NSString stringWithFormat:@"%.1fk", v / 1e3];
    return [NSString stringWithFormat:@"%lld", v];
}

+ (NSString *)relativeDate:(NSDate *)date {
    if (!date) return @"";
    NSTimeInterval s = -date.timeIntervalSinceNow;
    long days = (long)(s / 86400);
    if (days < 1) return @"today";
    if (days == 1) return @"yesterday";
    if (days < 31) return [NSString stringWithFormat:@"%ld days ago", days];
    long months = days / 30;
    if (months < 12) return months == 1 ? @"a month ago" : [NSString stringWithFormat:@"%ld months ago", months];
    long years = days / 365;
    return years <= 1 ? @"a year ago" : [NSString stringWithFormat:@"%ld years ago", years];
}

#pragma mark Networking

/// completion on main: (json, HTTP status, error)
- (void)requestURL:(NSString *)urlString
           headers:(NSDictionary *)headers
              body:(NSData *)body
           timeout:(NSTimeInterval)timeout
        completion:(void (^)(id json, NSInteger status, NSError *error))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil, 0, [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid request URL"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout > 0 ? timeout : 25;
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [req setValue:obj forHTTPHeaderField:key];
    }];
    if (body) {
        req.HTTPMethod = @"POST";
        req.HTTPBody = body;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSError *outError = error;
        if (!outError && (status < 200 || status >= 300)) {
            outError = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                       userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The server answered HTTP %ld.", (long)status]}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json, status, outError); });
    }] resume];
}

- (void)modrinthGET:(NSString *)pathAndQuery completion:(void (^)(id json, NSError *error))completion {
    [self requestURL:[kModrinthBase stringByAppendingString:pathAndQuery] headers:nil body:nil timeout:25
          completion:^(id json, NSInteger status, NSError *error) {
        if (error) {
            NSError *friendly = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                                userInfo:@{NSLocalizedDescriptionKey: @"Couldn't reach Modrinth. Check your connection and try again.",
                                                           NSUnderlyingErrorKey: error}];
            completion(nil, friendly);
        } else {
            completion(json, nil);
        }
    }];
}

- (NSString *)curseForgeKey {
    NSString *key = nil;
    @try { key = [[TBCurseForgeClass() sharedInstance] valueForKey:@"apiKey"]; } @catch (NSException *e) { key = nil; }
    return [key isKindOfClass:NSString.class] ? key : @"";
}

/// Official API with x-api-key when a key exists; otherwise one quick keyless try at the MCIM
/// mirror (works in mainland China only) and a "needs key" error if that fails.
- (void)curseForgeGET:(NSString *)pathAndQuery completion:(void (^)(id json, NSError *error))completion {
    NSString *key = [self curseForgeKey];
    BOOL haveKey = key.length > 0;
    NSString *base = haveKey ? kCurseForgeBase : [PLMirrorCenter mcimCurseForgeAPIBaseURL];
    NSDictionary *headers = haveKey ? @{@"x-api-key": key} : nil;
    [self requestURL:[base stringByAppendingString:pathAndQuery] headers:headers body:nil timeout:haveKey ? 25 : 8
          completion:^(id json, NSInteger status, NSError *error) {
        if (!error && [json isKindOfClass:NSDictionary.class]) {
            completion(json, nil);
            return;
        }
        NSError *out;
        if (!haveKey) {
            out = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorCurseForgeNeedsKey
                                  userInfo:@{NSLocalizedDescriptionKey: @"CurseForge needs an API key."}];
        } else if (status == 401 || status == 403) {
            out = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorCurseForgeKeyRejected
                                  userInfo:@{NSLocalizedDescriptionKey: @"CurseForge rejected the API key."}];
        } else {
            out = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                  userInfo:@{NSLocalizedDescriptionKey: @"Couldn't reach CurseForge. Check your connection and try again."}];
        }
        completion(nil, out);
    }];
}

#pragma mark CurseForge mappings

static NSInteger TBCurseForgeClassId(NSString *type) {
    if ([type isEqualToString:@"modpack"]) return 4471;
    if ([type isEqualToString:@"shader"]) return 6552;
    if ([type isEqualToString:@"resourcepack"]) return 12;
    if ([type isEqualToString:@"datapack"]) return 6945;
    return 6;
}

/// Official CurseForge ModLoaderType: 1 Forge, 4 Fabric, 5 Quilt, 6 NeoForge.
static NSInteger TBCurseForgeLoaderType(NSString *loader) {
    NSString *l = loader.lowercaseString;
    if ([l isEqualToString:@"forge"]) return 1;
    if ([l isEqualToString:@"fabric"]) return 4;
    if ([l isEqualToString:@"quilt"]) return 5;
    if ([l isEqualToString:@"neoforge"]) return 6;
    return 0;
}

static NSString *TBCurseForgeLoaderName(NSInteger type) {
    switch (type) {
        case 1: return @"forge";
        case 4: return @"fabric";
        case 5: return @"quilt";
        case 6: return @"neoforge";
        default: return nil;
    }
}

static BOOL TBUsesLoader(NSString *contentType) {
    return [contentType isEqualToString:@"mod"] || [contentType isEqualToString:@"modpack"];
}

#pragma mark Search

- (void)search:(TerraBrowseQuery *)query
    completion:(void (^)(NSArray<TerraBrowseProject *> *, NSInteger, NSError *))completion {
    if (query.source == TerraBrowseSourceCurseForge) {
        [self searchCurseForge:query completion:completion];
    } else {
        [self searchModrinth:query completion:completion];
    }
}

- (void)searchModrinth:(TerraBrowseQuery *)q
            completion:(void (^)(NSArray<TerraBrowseProject *> *, NSInteger, NSError *))completion {
    NSMutableArray *facets = [NSMutableArray arrayWithObject:@[[NSString stringWithFormat:@"project_type:%@", q.contentType]]];
    if (q.loader.length && TBUsesLoader(q.contentType)) {
        [facets addObject:@[[NSString stringWithFormat:@"categories:%@", q.loader]]];
    }
    if (q.gameVersion.length) [facets addObject:@[[NSString stringWithFormat:@"versions:%@", q.gameVersion]]];
    for (NSString *c in q.categories) [facets addObject:@[[NSString stringWithFormat:@"categories:%@", c]]];
    NSArray *indexes = @[@"relevance", @"downloads", @"follows", @"newest", @"updated"];
    NSString *index = indexes[MIN((NSUInteger)q.sort, indexes.count - 1)];
    NSString *qs = TBQueryString(@[@[@"query", q.text ?: @""], @[@"facets", TBJSON(facets)], @[@"index", index],
                                   @[@"offset", @(q.offset).stringValue], @[@"limit", @(q.limit).stringValue]]);
    NSString *contentType = q.contentType;
    [self modrinthGET:[@"/search?" stringByAppendingString:qs] completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:NSDictionary.class]) {
            completion(nil, 0, error);
            return;
        }
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *hit in json[@"hits"]) {
            if (![hit isKindOfClass:NSDictionary.class]) continue;
            TerraBrowseProject *p = [TerraBrowseProject new];
            p.source = TerraBrowseSourceModrinth;
            p.projectId = TBStr(hit[@"project_id"]) ?: @"";
            p.slug = TBStr(hit[@"slug"]);
            p.title = TBStr(hit[@"title"]) ?: @"";
            p.author = TBStr(hit[@"author"]) ?: @"";
            p.summary = TBStr(hit[@"description"]) ?: @"";
            p.iconURL = TBStr(hit[@"icon_url"]);
            p.downloads = [hit[@"downloads"] longLongValue];
            p.follows = [hit[@"follows"] longLongValue];
            p.updated = TBDate(hit[@"date_modified"]);
            p.contentType = contentType;
            NSArray *cats = [hit[@"display_categories"] isKindOfClass:NSArray.class] ? hit[@"display_categories"] : hit[@"categories"];
            NSMutableArray *categories = [NSMutableArray array], *loaders = [NSMutableArray array];
            for (NSString *c in ([hit[@"categories"] isKindOfClass:NSArray.class] ? hit[@"categories"] : @[])) {
                if (![c isKindOfClass:NSString.class]) continue;
                if ([@[@"fabric", @"forge", @"neoforge", @"quilt"] containsObject:c]) [loaders addObject:[TerraBrowseAPI displayNameForLoader:c]];
            }
            for (NSString *c in ([cats isKindOfClass:NSArray.class] ? cats : @[])) {
                if (![c isKindOfClass:NSString.class] || [TBLoaderTags() containsObject:c]) continue;
                if ([c rangeOfString:@"^[0-9]+x$" options:NSRegularExpressionSearch].location != NSNotFound) continue;
                [categories addObject:TBPrettyTag(c)];
            }
            p.categories = categories;
            p.loaders = loaders;
            NSString *typePath = [contentType isEqualToString:@"datapack"] ? @"datapack" : contentType;
            p.websiteURL = [NSString stringWithFormat:@"https://modrinth.com/%@/%@", typePath, p.slug ?: p.projectId];
            [out addObject:p];
        }
        completion(out, [json[@"total_hits"] integerValue], nil);
    }];
}

- (TerraBrowseProject *)projectFromCurseForge:(NSDictionary *)m contentType:(NSString *)contentType {
    TerraBrowseProject *p = [TerraBrowseProject new];
    p.source = TerraBrowseSourceCurseForge;
    p.projectId = TBStr(m[@"id"]) ?: @"";
    p.slug = TBStr(m[@"slug"]);
    p.title = TBStr(m[@"name"]) ?: @"";
    p.summary = TBStr(m[@"summary"]) ?: @"";
    NSArray *authors = [m[@"authors"] isKindOfClass:NSArray.class] ? m[@"authors"] : nil;
    p.author = authors.count ? (TBStr(authors.firstObject[@"name"]) ?: @"") : @"";
    NSDictionary *logo = [m[@"logo"] isKindOfClass:NSDictionary.class] ? m[@"logo"] : nil;
    p.iconURL = TBStr(logo[@"thumbnailUrl"]) ?: TBStr(logo[@"url"]);
    p.downloads = [m[@"downloadCount"] longLongValue];
    p.follows = [m[@"thumbsUpCount"] longLongValue];
    p.updated = TBDate(m[@"dateModified"]);
    p.contentType = contentType;
    NSMutableArray *cats = [NSMutableArray array];
    for (NSDictionary *c in ([m[@"categories"] isKindOfClass:NSArray.class] ? m[@"categories"] : @[])) {
        NSString *name = [c isKindOfClass:NSDictionary.class] ? TBStr(c[@"name"]) : nil;
        if (name.length && ![cats containsObject:name]) [cats addObject:name];
    }
    p.categories = cats;
    NSMutableOrderedSet *loaders = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *idx in ([m[@"latestFilesIndexes"] isKindOfClass:NSArray.class] ? m[@"latestFilesIndexes"] : @[])) {
        NSString *l = [idx isKindOfClass:NSDictionary.class] ? TBCurseForgeLoaderName([idx[@"modLoader"] integerValue]) : nil;
        if (l) [loaders addObject:[TerraBrowseAPI displayNameForLoader:l]];
    }
    p.loaders = loaders.array;
    NSDictionary *links = [m[@"links"] isKindOfClass:NSDictionary.class] ? m[@"links"] : nil;
    p.websiteURL = TBStr(links[@"websiteUrl"]);
    return p;
}

- (void)searchCurseForge:(TerraBrowseQuery *)q
              completion:(void (^)(NSArray<TerraBrowseProject *> *, NSInteger, NSError *))completion {
    NSInteger index = q.offset;
    NSInteger pageSize = q.limit;
    if (index + pageSize > 10000) {   // CurseForge hard limit
        completion(@[], index, nil);
        return;
    }
    NSMutableArray *pairs = [@[@[@"gameId", @"432"], @[@"classId", @(TBCurseForgeClassId(q.contentType)).stringValue],
                               @[@"index", @(index).stringValue], @[@"pageSize", @(pageSize).stringValue],
                               @[@"sortOrder", @"desc"]] mutableCopy];
    if (q.text.length) [pairs addObject:@[@"searchFilter", q.text]];
    if (q.gameVersion.length) [pairs addObject:@[@"gameVersion", q.gameVersion]];
    NSInteger loaderType = TBUsesLoader(q.contentType) ? TBCurseForgeLoaderType(q.loader) : 0;
    if (loaderType > 0) [pairs addObject:@[@"modLoaderType", @(loaderType).stringValue]];
    if (q.categories.count == 1) {
        [pairs addObject:@[@"categoryId", q.categories.firstObject]];
    } else if (q.categories.count > 1) {
        [pairs addObject:@[@"categoryIds", [NSString stringWithFormat:@"[%@]", [q.categories componentsJoinedByString:@","]]]];
    }
    // sortField: 2 Popularity, 3 LastUpdated, 6 TotalDownloads, 11 ReleasedDate
    NSInteger sortField = 0;
    switch (q.sort) {
        case TerraBrowseSortRelevance: sortField = q.text.length ? 0 : 2; break;
        case TerraBrowseSortDownloads: sortField = 6; break;
        case TerraBrowseSortFollows: sortField = 2; break;
        case TerraBrowseSortNewest: sortField = 11; break;
        case TerraBrowseSortUpdated: sortField = 3; break;
    }
    if (sortField > 0) [pairs addObject:@[@"sortField", @(sortField).stringValue]];
    NSString *contentType = q.contentType;
    [self curseForgeGET:[@"/mods/search?" stringByAppendingString:TBQueryString(pairs)] completion:^(id json, NSError *error) {
        if (error) {
            completion(nil, 0, error);
            return;
        }
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *m in ([json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : @[])) {
            if (![m isKindOfClass:NSDictionary.class]) continue;
            if ([m[@"isAvailable"] isKindOfClass:NSNumber.class] && ![m[@"isAvailable"] boolValue]) continue;
            [out addObject:[self projectFromCurseForge:m contentType:contentType]];
        }
        NSDictionary *pagination = [json[@"pagination"] isKindOfClass:NSDictionary.class] ? json[@"pagination"] : nil;
        NSInteger total = pagination ? MIN([pagination[@"totalCount"] integerValue], 10000) : (NSInteger)out.count;
        completion(out, total, nil);
    }];
}

#pragma mark Categories / versions lists

- (void)categoriesForSource:(TerraBrowseSource)source contentType:(NSString *)contentType
                 completion:(void (^)(NSArray<NSDictionary<NSString *, NSString *> *> *))completion {
    NSString *cacheKey = [NSString stringWithFormat:@"cat-%ld-%@", (long)source, contentType];
    NSArray *cached = [self.cache objectForKey:cacheKey];
    if (cached) {
        completion(cached);
        return;
    }
    if (source == TerraBrowseSourceCurseForge) {
        NSString *path = [NSString stringWithFormat:@"/categories?gameId=432&classId=%ld", (long)TBCurseForgeClassId(contentType)];
        [self curseForgeGET:path completion:^(id json, NSError *error) {
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *c in ([json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : @[])) {
                if (![c isKindOfClass:NSDictionary.class] || [c[@"isClass"] boolValue]) continue;
                NSString *cid = TBStr(c[@"id"]), *name = TBStr(c[@"name"]);
                if (cid.length && name.length) [out addObject:@{@"id": cid, @"name": name}];
            }
            [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            }];
            if (out.count) [self.cache setObject:out forKey:cacheKey];
            completion(out);
        }];
        return;
    }
    NSString *modrinthType = [contentType isEqualToString:@"datapack"] ? @"mod" : contentType;
    [self modrinthGET:@"/tag/category" completion:^(id json, NSError *error) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *c in ([json isKindOfClass:NSArray.class] ? json : @[])) {
            if (![c isKindOfClass:NSDictionary.class]) continue;
            if (![TBStr(c[@"project_type"]) isEqualToString:modrinthType]) continue;
            if (![TBStr(c[@"header"]) isEqualToString:@"categories"]) continue;
            NSString *name = TBStr(c[@"name"]);
            if (name.length) [out addObject:@{@"id": name, @"name": TBPrettyTag(name)}];
        }
        [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
        }];
        if (out.count) [self.cache setObject:out forKey:cacheKey];
        completion(out);
    }];
}

- (void)releaseGameVersions:(void (^)(NSArray<NSString *> *))completion {
    NSArray *cached = [self.cache objectForKey:@"gameVersions"];
    if (cached) {
        completion(cached);
        return;
    }
    [self modrinthGET:@"/tag/game_version" completion:^(id json, NSError *error) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *v in ([json isKindOfClass:NSArray.class] ? json : @[])) {
            if ([v isKindOfClass:NSDictionary.class] && [TBStr(v[@"version_type"]) isEqualToString:@"release"]) {
                NSString *ver = TBStr(v[@"version"]);
                if (ver.length) [out addObject:ver];
            }
        }
        if (out.count) [self.cache setObject:out forKey:@"gameVersions"];
        completion(out);
    }];
}

#pragma mark Description

static NSString *TBPlainText(NSString *text, BOOL html) {
    if (text.length == 0) return @"";
    NSMutableString *s = [text mutableCopy];
    void (^replace)(NSString *, NSString *) = ^(NSString *pattern, NSString *with) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                            options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                                              error:nil];
        [re replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:with];
    };
    if (html) {
        replace(@"<(br|/p|/div|/li|/h[1-6])\\s*/?>", @"\n");
        replace(@"<li[^>]*>", @"• ");
    }
    replace(@"!\\[[^\\]]*\\]\\([^)]*\\)", @"");          // images
    replace(@"\\[([^\\]]*)\\]\\([^)]*\\)", @"$1");        // links
    replace(@"<[^>]+>", @"");                              // tags
    replace(@"^\\s{0,3}#{1,6}\\s*", @"");                  // headings
    replace(@"(\\*\\*|__|`{1,3})", @"");
    replace(@"^\\s*[-*+]\\s+", @"• ");
    replace(@"^\\s*>\\s?", @"");
    NSDictionary *entities = @{@"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'", @"&nbsp;": @" "};
    for (NSString *k in entities) [s replaceOccurrencesOfString:k withString:entities[k] options:0 range:NSMakeRange(0, s.length)];
    replace(@"[ \\t]+\\n", @"\n");
    replace(@"\\n{3,}", @"\n\n");
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)descriptionForProject:(TerraBrowseProject *)project completion:(void (^)(NSString *))completion {
    if (project.source == TerraBrowseSourceCurseForge) {
        [self curseForgeGET:[NSString stringWithFormat:@"/mods/%@/description", project.projectId] completion:^(id json, NSError *error) {
            completion(TBPlainText(TBStr(json[@"data"]), YES));
        }];
        return;
    }
    [self modrinthGET:[NSString stringWithFormat:@"/project/%@", TBEncode(project.projectId)] completion:^(id json, NSError *error) {
        NSString *body = [json isKindOfClass:NSDictionary.class] ? TBStr(json[@"body"]) : nil;
        completion(TBPlainText(body, YES));
    }];
}

#pragma mark Versions

- (void)versionsForProject:(TerraBrowseProject *)project loader:(NSString *)loader gameVersion:(NSString *)gameVersion
                completion:(void (^)(NSArray<TerraBrowseFile *> *, NSError *))completion {
    [self versionsForProjectId:project.projectId source:project.source contentType:project.contentType
                        loader:loader gameVersion:gameVersion completion:completion];
}

- (void)versionsForProjectId:(NSString *)projectId source:(TerraBrowseSource)source contentType:(NSString *)contentType
                      loader:(NSString *)loader gameVersion:(NSString *)gameVersion
                  completion:(void (^)(NSArray<TerraBrowseFile *> *, NSError *))completion {
    if (source == TerraBrowseSourceCurseForge) {
        NSMutableArray *pairs = [@[@[@"pageSize", @"50"], @[@"index", @"0"]] mutableCopy];
        if (gameVersion.length) [pairs addObject:@[@"gameVersion", gameVersion]];
        NSInteger lt = TBUsesLoader(contentType) ? TBCurseForgeLoaderType(loader) : 0;
        if (lt > 0) [pairs addObject:@[@"modLoaderType", @(lt).stringValue]];
        NSString *path = [NSString stringWithFormat:@"/mods/%@/files?%@", TBEncode(projectId), TBQueryString(pairs)];
        [self curseForgeGET:path completion:^(id json, NSError *error) {
            if (error) {
                completion(nil, error);
                return;
            }
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *f in ([json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : @[])) {
                if (![f isKindOfClass:NSDictionary.class]) continue;
                if ([f[@"isAvailable"] isKindOfClass:NSNumber.class] && ![f[@"isAvailable"] boolValue]) continue;
                if ([f[@"isServerPack"] boolValue]) continue;
                [out addObject:[self fileFromCurseForge:f]];
            }
            [out sortUsingComparator:^NSComparisonResult(TerraBrowseFile *a, TerraBrowseFile *b) {
                return [b.published ?: NSDate.distantPast compare:a.published ?: NSDate.distantPast];
            }];
            completion(out, nil);
        }];
        return;
    }
    NSMutableArray *pairs = [NSMutableArray array];
    NSArray *loaders = nil;
    if ([contentType isEqualToString:@"datapack"]) loaders = @[@"datapack"];
    else if (TBUsesLoader(contentType) && loader.length && ![loader isEqualToString:@"vanilla"]) {
        loaders = [loader isEqualToString:@"quilt"] ? @[@"quilt", @"fabric"] : @[loader];
    }
    if (loaders) [pairs addObject:@[@"loaders", TBJSON(loaders)]];
    if (gameVersion.length) [pairs addObject:@[@"game_versions", TBJSON(@[gameVersion])]];
    NSString *path = [NSString stringWithFormat:@"/project/%@/version%@%@", TBEncode(projectId),
                      pairs.count ? @"?" : @"", TBQueryString(pairs)];
    [self modrinthGET:path completion:^(id json, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSMutableArray *out = [NSMutableArray array];
        for (NSDictionary *v in ([json isKindOfClass:NSArray.class] ? json : @[])) {
            if (![v isKindOfClass:NSDictionary.class]) continue;
            TerraBrowseFile *file = [self fileFromModrinth:v];
            if (file.url.length) [out addObject:file];
        }
        completion(out, nil);
    }];
}

- (TerraBrowseFile *)fileFromModrinth:(NSDictionary *)v {
    TerraBrowseFile *f = [TerraBrowseFile new];
    f.source = TerraBrowseSourceModrinth;
    f.projectId = TBStr(v[@"project_id"]) ?: @"";
    f.versionId = TBStr(v[@"id"]) ?: @"";
    f.name = TBStr(v[@"name"]) ?: @"";
    f.versionNumber = TBStr(v[@"version_number"]) ?: @"";
    f.releaseType = TBStr(v[@"version_type"]) ?: @"release";
    f.published = TBDate(v[@"date_published"]);
    f.gameVersions = [v[@"game_versions"] isKindOfClass:NSArray.class] ? v[@"game_versions"] : @[];
    f.loaders = [v[@"loaders"] isKindOfClass:NSArray.class] ? v[@"loaders"] : @[];
    NSArray *files = [v[@"files"] isKindOfClass:NSArray.class] ? v[@"files"] : @[];
    NSDictionary *primary = nil;
    for (NSDictionary *file in files) {
        if ([file isKindOfClass:NSDictionary.class] && [file[@"primary"] boolValue]) { primary = file; break; }
    }
    if (!primary && files.count && [files.firstObject isKindOfClass:NSDictionary.class]) primary = files.firstObject;
    f.fileName = TBStr(primary[@"filename"]) ?: @"";
    f.url = TBStr(primary[@"url"]) ?: @"";
    NSDictionary *hashes = [primary[@"hashes"] isKindOfClass:NSDictionary.class] ? primary[@"hashes"] : nil;
    f.sha1 = TBStr(hashes[@"sha1"]);
    f.size = [primary[@"size"] longLongValue];
    f.rawDictionary = v;
    return f;
}

- (TerraBrowseFile *)fileFromCurseForge:(NSDictionary *)d {
    TerraBrowseFile *f = [TerraBrowseFile new];
    f.source = TerraBrowseSourceCurseForge;
    f.projectId = TBStr(d[@"modId"]) ?: @"";
    f.versionId = TBStr(d[@"id"]) ?: @"";
    f.name = TBStr(d[@"displayName"]) ?: @"";
    f.fileName = TBStr(d[@"fileName"]) ?: @"";
    f.versionNumber = f.name;
    NSInteger rt = [d[@"releaseType"] integerValue];
    f.releaseType = rt == 2 ? @"beta" : (rt == 3 ? @"alpha" : @"release");
    f.published = TBDate(d[@"fileDate"]);
    f.size = [d[@"fileLength"] longLongValue];
    NSMutableArray *versions = [NSMutableArray array], *loaders = [NSMutableArray array];
    for (NSString *gv in ([d[@"gameVersions"] isKindOfClass:NSArray.class] ? d[@"gameVersions"] : @[])) {
        if (![gv isKindOfClass:NSString.class]) continue;
        NSString *l = gv.lowercaseString;
        if ([@[@"forge", @"fabric", @"quilt", @"neoforge"] containsObject:l]) [loaders addObject:l];
        else if ([gv rangeOfString:@"^\\d" options:NSRegularExpressionSearch].location != NSNotFound) [versions addObject:gv];
    }
    f.gameVersions = versions;
    f.loaders = loaders;
    for (NSDictionary *h in ([d[@"hashes"] isKindOfClass:NSArray.class] ? d[@"hashes"] : @[])) {
        if ([h isKindOfClass:NSDictionary.class] && [h[@"algo"] integerValue] == 1) f.sha1 = TBStr(h[@"value"]);
    }
    NSString *url = TBStr(d[@"downloadUrl"]);
    if (url.length == 0 && f.fileName.length) {
        // Projects that opt out of third-party distribution return null; the CDN path is deterministic.
        long long fid = [d[@"id"] longLongValue];
        url = [NSString stringWithFormat:@"https://edge.forgecdn.net/files/%lld/%lld/%@", fid / 1000, fid % 1000,
               [f.fileName stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
    }
    f.url = url ?: @"";
    f.rawDictionary = d;
    return f;
}

#pragma mark Download

- (void)downloadFile:(TerraBrowseFile *)file toFolder:(NSString *)folder
            progress:(void (^)(double))progress completion:(void (^)(NSString *, NSError *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *original = [NSURL URLWithString:file.url];
        if (!original || file.fileName.length == 0) {
            completion(nil, [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                            userInfo:@{NSLocalizedDescriptionKey: @"This file has no download link."}]);
            return;
        }
        NSArray<NSURL *> *candidates = [PLMirrorCenter candidateURLsForOriginalURL:original
                                                                      resourceType:PLMirrorResourceTypeAssetDownload];
        if (candidates.count == 0) candidates = @[original];
        [self tryDownloadCandidates:candidates index:0 file:file folder:folder progress:progress lastError:nil completion:completion];
    });
}

- (void)tryDownloadCandidates:(NSArray<NSURL *> *)candidates index:(NSUInteger)index file:(TerraBrowseFile *)file
                       folder:(NSString *)folder progress:(void (^)(double))progress lastError:(NSError *)lastError
                   completion:(void (^)(NSString *, NSError *))completion {
    if (index >= candidates.count) {
        completion(nil, lastError ?: [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Download failed."}]);
        return;
    }
    NSString *safeName = [file.fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *dest = [folder stringByAppendingPathComponent:safeName];
    NSString *expectedSHA1 = file.sha1.lowercaseString;
    long long expectedSize = file.size;
    __block NSTimer *timer = nil;
    NSURLSessionDownloadTask *task = [self.session downloadTaskWithURL:candidates[index]
                                                     completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 200;
        NSError *failure = error;
        if (!failure && (status < 200 || status >= 300 || !location)) {
            failure = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                      userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Download failed (HTTP %ld).", (long)status]}];
        }
        if (!failure && expectedSHA1.length) {
            NSString *actual = TBSHA1OfFile(location.path);
            if (actual && ![actual isEqualToString:expectedSHA1]) {
                failure = [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                          userInfo:@{NSLocalizedDescriptionKey: @"The downloaded file was corrupted (checksum mismatch)."}];
            }
        }
        if (!failure) {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
            [fm removeItemAtPath:dest error:nil];
            NSError *moveError = nil;
            if (![fm moveItemAtPath:location.path toPath:dest error:&moveError]) failure = moveError;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [timer invalidate];
            if (failure) {
                NSLog(@"[TerraBrowse] download %@ failed from %@: %@", file.fileName, candidates[index].host, failure);
                [self tryDownloadCandidates:candidates index:index + 1 file:file folder:folder progress:progress
                                  lastError:failure completion:completion];
            } else {
                if (progress) progress(1.0);
                completion(dest, nil);
            }
        });
    }];
    if (progress) {
        timer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *t) {
            long long total = task.countOfBytesExpectedToReceive > 0 ? task.countOfBytesExpectedToReceive : expectedSize;
            if (total > 0) progress(MIN(0.99, (double)task.countOfBytesReceived / (double)total));
        }];
    }
    [task resume];
}

#pragma mark Installed detection

- (void)installedModrinthProjectIdsInFolder:(NSString *)folder completion:(void (^)(NSSet<NSString *> *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *hashes = [NSMutableArray array];
        for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] ?: @[]) {
            NSString *lower = name.lowercaseString;
            if (![lower hasSuffix:@".jar"] && ![lower hasSuffix:@".jar.disabled"]) continue;
            NSString *sha = TBSHA1OfFile([folder stringByAppendingPathComponent:name]);
            if (sha) [hashes addObject:sha];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (hashes.count == 0) {
                completion([NSSet set]);
                return;
            }
            NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"hashes": hashes, @"algorithm": @"sha1"} options:0 error:nil];
            [self requestURL:[kModrinthBase stringByAppendingString:@"/version_files"] headers:nil body:body timeout:25
                  completion:^(id json, NSInteger status, NSError *error) {
                NSMutableSet *ids = [NSMutableSet set];
                if ([json isKindOfClass:NSDictionary.class]) {
                    for (NSDictionary *v in [json allValues]) {
                        NSString *pid = [v isKindOfClass:NSDictionary.class] ? TBStr(v[@"project_id"]) : nil;
                        if (pid) [ids addObject:pid];
                    }
                }
                completion(ids);
            }];
        });
    });
}

- (void)modrinthIdsForSlugs:(NSArray<NSString *> *)slugs completion:(void (^)(NSDictionary<NSString *, NSString *> *))completion {
    NSString *qs = TBQueryString(@[@[@"ids", TBJSON(slugs)]]);
    [self modrinthGET:[@"/projects?" stringByAppendingString:qs] completion:^(id json, NSError *error) {
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (NSDictionary *p in ([json isKindOfClass:NSArray.class] ? json : @[])) {
            if (![p isKindOfClass:NSDictionary.class]) continue;
            NSString *slug = TBStr(p[@"slug"]), *pid = TBStr(p[@"id"]);
            if (slug && pid) map[slug] = pid;
        }
        completion(map);
    }];
}

#pragma mark Dependencies

/// ModDependencyResolver is a singleton with per-call state, so calls are serialized here.
- (void)enqueueResolverWork:(void (^)(dispatch_block_t done))work {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.resolverQueue addObject:[work copy]];
        [self runNextResolverWork];
    });
}

- (void)runNextResolverWork {
    if (self.resolverBusy || self.resolverQueue.count == 0) return;
    self.resolverBusy = YES;
    void (^work)(dispatch_block_t) = self.resolverQueue.firstObject;
    [self.resolverQueue removeObjectAtIndex:0];
    work(^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.resolverBusy = NO;
            [self runNextResolverWork];
        });
    });
}

- (void)installDependenciesOfFile:(TerraBrowseFile *)file target:(TerraBrowseTarget *)target
                installedProjects:(NSSet<NSString *> *)installedProjects
                       completion:(void (^)(NSArray<NSString *> *, NSArray<NSString *> *))completion {
    NSString *folder = [target ensureFolderForContentType:@"mod"];
    if (!file.rawDictionary || !folder) {
        completion(@[], @[]);
        return;
    }
    [self enqueueResolverWork:^(dispatch_block_t done) {
        [[ModDependencyResolver sharedResolver] resolveDependenciesFromVersionDetail:file.rawDictionary
                                                                           apiSource:file.source
                                                                installedProjectIds:installedProjects
                                                                              loader:target.loader
                                                                         gameVersion:target.gameVersion
                                                                          completion:^(ModDependencyPlan *plan, NSError *error) {
            done();
            [self installDependencyItems:plan.required index:0 target:target folder:folder
                               installed:[NSMutableArray array] failed:[NSMutableArray array] completion:completion];
        }];
    }];
}

- (void)installDependencyItems:(NSArray<ModDependencyItem *> *)items index:(NSUInteger)index
                        target:(TerraBrowseTarget *)target folder:(NSString *)folder
                     installed:(NSMutableArray *)installed failed:(NSMutableArray *)failed
                    completion:(void (^)(NSArray<NSString *> *, NSArray<NSString *> *))completion {
    if (index >= items.count) {
        completion(installed, failed);
        return;
    }
    ModDependencyItem *dep = items[index];
    TerraBrowseSource source = dep.apiSource == 2 ? TerraBrowseSourceCurseForge : TerraBrowseSourceModrinth;
    void (^next)(void) = ^{
        [self installDependencyItems:items index:index + 1 target:target folder:folder
                           installed:installed failed:failed completion:completion];
    };
    [self versionsForProjectId:dep.projectId source:source contentType:@"mod" loader:target.loader
                   gameVersion:target.gameVersion completion:^(NSArray<TerraBrowseFile *> *files, NSError *error) {
        TerraBrowseFile *pick = files.firstObject;
        NSString *label = dep.displayName.length ? dep.displayName
            : (pick.fileName.length ? pick.fileName.stringByDeletingPathExtension : dep.projectId);
        if (!pick) {
            [failed addObject:label];
            next();
            return;
        }
        if ([NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:pick.fileName]]) {
            next();
            return;
        }
        [self downloadFile:pick toFolder:folder progress:nil completion:^(NSString *path, NSError *dlError) {
            [(path ? installed : failed) addObject:label];
            next();
        }];
    }];
}

- (void)installFile:(TerraBrowseFile *)file contentType:(NSString *)contentType target:(TerraBrowseTarget *)target
           progress:(void (^)(double, NSString *))progress
         completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    NSString *folder = [target ensureFolderForContentType:contentType];
    if (!folder) {
        completion(@[], [NSError errorWithDomain:TerraBrowseErrorDomain code:TerraBrowseErrorNetwork
                                        userInfo:@{NSLocalizedDescriptionKey: @"Couldn't create the destination folder."}]);
        return;
    }
    BOOL isMod = [contentType isEqualToString:@"mod"];
    if (progress) progress(0, @"Downloading…");
    [self downloadFile:file toFolder:folder progress:^(double f) {
        if (progress) progress(isMod ? f * 0.8 : f, @"Downloading…");
    } completion:^(NSString *path, NSError *error) {
        if (!path) {
            completion(@[], error);
            return;
        }
        if (!isMod) {
            completion(@[], nil);
            return;
        }
        if (progress) progress(0.85, @"Checking dependencies…");
        void (^resolve)(NSSet *) = ^(NSSet *installedIds) {
            NSMutableSet *ids = [installedIds mutableCopy] ?: [NSMutableSet set];
            if (file.projectId.length) [ids addObject:file.projectId];
            [self installDependenciesOfFile:file target:target installedProjects:ids
                                 completion:^(NSArray<NSString *> *installed, NSArray<NSString *> *failed) {
                if (progress) progress(1, @"Installed");
                completion(installed, nil);
            }];
        };
        if (file.source == TerraBrowseSourceModrinth) {
            [self installedModrinthProjectIdsInFolder:folder completion:resolve];
        } else {
            resolve([NSSet set]);
        }
    }];
}

@end
