//
//  TerraBrowseAPI.h
//  ★ [TERRA-BROWSE] Data layer for the redesigned "Mods & More" browser and Potato Optimize.
//
//  · TerraBrowseTarget  — an installation you can install content into (name, Minecraft
//                         version, loader, game directory). Built from PLProfiles plus the
//                         Terra launcher snapshot, so it matches what the SwiftUI UI shows.
//  · TerraBrowseAPI     — Modrinth (api.modrinth.com/v2) and CurseForge (official
//                         api.curseforge.com/v1 with x-api-key) search / project / versions /
//                         categories, a small verified downloader, installed-mod detection
//                         (Modrinth version_files by SHA-1) and one-call "install with
//                         required dependencies" built on ModDependencyResolver.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TerraBrowseSource) {
    TerraBrowseSourceModrinth = 1,
    TerraBrowseSourceCurseForge = 2,
};

typedef NS_ENUM(NSInteger, TerraBrowseSort) {
    TerraBrowseSortRelevance = 0,
    TerraBrowseSortDownloads,
    TerraBrowseSortFollows,
    TerraBrowseSortNewest,
    TerraBrowseSortUpdated,
};

/// NSError domain/codes surfaced to the UI.
extern NSString *const TerraBrowseErrorDomain;
typedef NS_ENUM(NSInteger, TerraBrowseErrorCode) {
    TerraBrowseErrorCurseForgeNeedsKey = 401,   ///< no key configured and the keyless mirror is unreachable
    TerraBrowseErrorCurseForgeKeyRejected = 403,///< key configured but CurseForge answered 401/403
    TerraBrowseErrorNoCompatibleVersion = 404,
    TerraBrowseErrorNetwork = 500,
};

#pragma mark - Target installation

@interface TerraBrowseTarget : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *versionId;     ///< profile lastVersionId (e.g. fabric-loader-0.16.9-1.21.1)
@property (nonatomic, copy) NSString *gameVersion;   ///< Minecraft version (e.g. 1.21.1)
@property (nonatomic, copy) NSString *loader;        ///< fabric / forge / neoforge / quilt / vanilla
@property (nonatomic, copy) NSString *gameDir;       ///< absolute game directory
@property (nonatomic, readonly) NSString *loaderDisplayName;
@property (nonatomic, readonly) BOOL hasModLoader;
/// mods / shaderpacks / resourcepacks / datapacks folder for a content type (created if missing).
- (nullable NSString *)ensureFolderForContentType:(NSString *)contentType;
- (NSString *)folderForContentType:(NSString *)contentType;

+ (NSArray<TerraBrowseTarget *> *)allTargets;
+ (nullable TerraBrowseTarget *)targetNamed:(nullable NSString *)name;
/// Selected profile, else first target.
+ (nullable TerraBrowseTarget *)defaultTarget;
/// Best-effort loader + Minecraft version from a version id / version JSON.
+ (void)detectVersionId:(NSString *)versionId
                gameDir:(nullable NSString *)gameDir
            gameVersion:(NSString * _Nullable * _Nullable)gameVersionOut
                 loader:(NSString * _Nullable * _Nullable)loaderOut;
@end

#pragma mark - Models

@interface TerraBrowseProject : NSObject
@property (nonatomic, assign) TerraBrowseSource source;
@property (nonatomic, copy) NSString *projectId;
@property (nonatomic, copy, nullable) NSString *slug;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy, nullable) NSString *iconURL;
@property (nonatomic, assign) long long downloads;
@property (nonatomic, assign) long long follows;
@property (nonatomic, copy) NSArray<NSString *> *categories;   ///< display names (no loaders)
@property (nonatomic, copy) NSArray<NSString *> *loaders;      ///< display names (Fabric, Forge…)
@property (nonatomic, strong, nullable) NSDate *updated;
@property (nonatomic, copy) NSString *contentType;             ///< mod / modpack / shader / resourcepack / datapack
@property (nonatomic, copy, nullable) NSString *websiteURL;
@end

@interface TerraBrowseFile : NSObject
@property (nonatomic, assign) TerraBrowseSource source;
@property (nonatomic, copy) NSString *projectId;
@property (nonatomic, copy) NSString *versionId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *versionNumber;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy, nullable) NSString *sha1;
@property (nonatomic, assign) long long size;
@property (nonatomic, copy) NSArray<NSString *> *gameVersions;
@property (nonatomic, copy) NSArray<NSString *> *loaders;      ///< lowercase (fabric, neoforge…)
@property (nonatomic, copy) NSString *releaseType;             ///< release / beta / alpha
@property (nonatomic, strong, nullable) NSDate *published;
@property (nonatomic, copy, nullable) NSDictionary *rawDictionary; ///< for ModDependencyResolver
@end

@interface TerraBrowseQuery : NSObject <NSCopying>
@property (nonatomic, assign) TerraBrowseSource source;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *loader;        ///< fabric/forge/neoforge/quilt or nil
@property (nonatomic, copy, nullable) NSString *gameVersion;   ///< nil = any
@property (nonatomic, copy) NSArray<NSString *> *categories;   ///< Modrinth slugs or CurseForge ids (as strings)
@property (nonatomic, assign) TerraBrowseSort sort;
@property (nonatomic, assign) NSInteger offset;
@property (nonatomic, assign) NSInteger limit;
@end

#pragma mark - API

@interface TerraBrowseAPI : NSObject

+ (instancetype)shared;

/// YES when a CurseForge API key is configured (Settings / compile-time / Info.plist).
+ (BOOL)curseForgeKeyConfigured;
+ (NSString *)displayNameForLoader:(NSString *)loader;
+ (NSString *)compactNumber:(long long)value;
+ (NSString *)relativeDate:(nullable NSDate *)date;

- (void)search:(TerraBrowseQuery *)query
    completion:(void (^)(NSArray<TerraBrowseProject *> * _Nullable results, NSInteger totalHits, NSError * _Nullable error))completion;

/// [{@"id": slug-or-id, @"name": display}] for the filter sidebar (cached).
- (void)categoriesForSource:(TerraBrowseSource)source
                contentType:(NSString *)contentType
                 completion:(void (^)(NSArray<NSDictionary<NSString *, NSString *> *> *categories))completion;

/// Release game versions, newest first (cached; Modrinth tag list).
- (void)releaseGameVersions:(void (^)(NSArray<NSString *> *versions))completion;

/// Long description as plain text.
- (void)descriptionForProject:(TerraBrowseProject *)project completion:(void (^)(NSString * _Nullable text))completion;

/// Versions/files of a project, newest first. loader/gameVersion nil = unfiltered.
- (void)versionsForProject:(TerraBrowseProject *)project
                    loader:(nullable NSString *)loader
               gameVersion:(nullable NSString *)gameVersion
                completion:(void (^)(NSArray<TerraBrowseFile *> * _Nullable files, NSError * _Nullable error))completion;

/// Same, by raw project id (Modrinth id or slug / CurseForge numeric id).
- (void)versionsForProjectId:(NSString *)projectId
                      source:(TerraBrowseSource)source
                 contentType:(NSString *)contentType
                      loader:(nullable NSString *)loader
                 gameVersion:(nullable NSString *)gameVersion
                  completion:(void (^)(NSArray<TerraBrowseFile *> * _Nullable files, NSError * _Nullable error))completion;

/// Download into folder/<fileName> (verified with SHA-1 when known; mirror candidates on failure).
- (void)downloadFile:(TerraBrowseFile *)file
            toFolder:(NSString *)folder
            progress:(nullable void (^)(double fraction))progress
          completion:(void (^)(NSString * _Nullable path, NSError * _Nullable error))completion;

/// Modrinth project ids of the .jar files in a mods folder (SHA-1 → version_files).
- (void)installedModrinthProjectIdsInFolder:(NSString *)folder
                                 completion:(void (^)(NSSet<NSString *> *projectIds))completion;

/// Modrinth project id/slug pairs: {slug: id}.
- (void)modrinthIdsForSlugs:(NSArray<NSString *> *)slugs
                 completion:(void (^)(NSDictionary<NSString *, NSString *> *slugToId))completion;

/// Resolve the required dependencies of an installed mod file and install them into the
/// target's mods folder. Calls completion with the display names of what was installed.
- (void)installDependenciesOfFile:(TerraBrowseFile *)file
                           target:(TerraBrowseTarget *)target
                installedProjects:(nullable NSSet<NSString *> *)installedProjects
                       completion:(void (^)(NSArray<NSString *> *installed, NSArray<NSString *> *failed))completion;

/// Download a file into the target's folder for its content type and, for mods, its required
/// dependencies. progress 0…1.
- (void)installFile:(TerraBrowseFile *)file
        contentType:(NSString *)contentType
             target:(TerraBrowseTarget *)target
           progress:(nullable void (^)(double fraction, NSString *status))progress
         completion:(void (^)(NSArray<NSString *> *dependencies, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
