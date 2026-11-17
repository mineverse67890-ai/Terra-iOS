//
//  TerraPotatoOptimizer.m
//  ★ [TERRA-BROWSE] see TerraPotatoOptimizer.h
//

#import "TerraPotatoOptimizer.h"
#import "TerraBrowseAPI.h"
#import "TerraStyle.h"
#import "TerraVersionInstaller.h"

NSString *const TerraPotatoOptimizerDidFinishNotification = @"TerraPotatoOptimizerDidFinishNotification";

typedef NS_ENUM(NSInteger, TPOState) {
    TPOStatePending = 0,
    TPOStateWorking,
    TPOStateInstalled,
    TPOStateAlready,
    TPOStateSkipped,
    TPOStateFailed,
};

#pragma mark - Item

@interface TPOItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *blurb;
@property (nonatomic, copy) NSArray<NSString *> *slugs;     ///< alternatives, first compatible wins
@property (nonatomic, copy) NSString *contentType;          ///< mod / resourcepack
@property (nonatomic, assign) TPOState state;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, strong, nullable) TerraBrowseFile *installedFile;
@end

@implementation TPOItem
+ (instancetype)name:(NSString *)name slugs:(NSArray *)slugs type:(NSString *)type blurb:(NSString *)blurb {
    TPOItem *i = [TPOItem new];
    i.name = name; i.slugs = slugs; i.contentType = type; i.blurb = blurb; i.detail = blurb;
    return i;
}
@end

static TPOItem *TPOMod(NSString *name, NSArray *slugs, NSString *blurb) { return [TPOItem name:name slugs:slugs type:@"mod" blurb:blurb]; }
static TPOItem *TPOPack(NSString *name, NSString *slug, NSString *blurb) { return [TPOItem name:name slugs:@[slug] type:@"resourcepack" blurb:blurb]; }

#pragma mark - Sheet

@interface TPOSheetController : UIViewController
@property (nonatomic, copy) NSString *heading;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy, nullable) NSString *note;
@property (nonatomic, copy) NSArray<TPOItem *> *items;
@property (nonatomic, copy) void (^onStart)(void);
@property (nonatomic, strong) NSMutableArray<UIImageView *> *iconViews;
@property (nonatomic, strong) NSMutableArray<UIActivityIndicatorView *> *spinners;
@property (nonatomic, strong) NSMutableArray<UILabel *> *detailLabels;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL finished;
- (void)refreshItem:(TPOItem *)item;
- (void)setOverallProgress:(double)progress;
- (void)finishWithSummary:(NSString *)summary;
@end

@implementation TPOSheetController

- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];
    self.iconViews = [NSMutableArray array];
    self.spinners = [NSMutableArray array];
    self.detailLabels = [NSMutableArray array];

    UIImageView *badge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:self.symbol withConfiguration:
                          [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightBold]]];
    badge.tintColor = TerraStyle.greenBright;
    badge.contentMode = UIViewContentModeCenter;
    [badge.widthAnchor constraintEqualToConstant:30].active = YES;
    UILabel *title = [UILabel new];
    title.text = self.heading;
    title.font = TerraStyle.titleFont;
    title.textColor = TerraStyle.text;
    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[badge, title]];
    titleRow.spacing = 8;
    titleRow.alignment = UIStackViewAlignmentCenter;

    UILabel *subtitle = [UILabel new];
    subtitle.text = self.subtitle;
    subtitle.font = TerraStyle.bodyFont;
    subtitle.textColor = TerraStyle.dimText;
    subtitle.numberOfLines = 0;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, subtitle]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 4;
    if (self.note.length) {
        UILabel *note = [UILabel new];
        note.text = self.note;
        note.font = TerraStyle.captionFont;
        note.textColor = TerraStyle.warning;
        note.numberOfLines = 0;
        [header addArrangedSubview:note];
    }

    UIStackView *list = [UIStackView new];
    list.axis = UILayoutConstraintAxisVertical;
    list.spacing = 6;
    for (TPOItem *item in self.items) [list addArrangedSubview:[self rowForItem:item]];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:list];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = TerraStyle.greenBright;
    self.progressView.trackTintColor = TerraStyle.raised;
    self.progressView.hidden = YES;

    self.summaryLabel = [UILabel new];
    self.summaryLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.summaryLabel.textColor = TerraStyle.text;
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.text = [NSString stringWithFormat:@"%lu item%@ will be downloaded from Modrinth. Anything already installed or without a version for this installation is skipped.",
                              (unsigned long)self.items.count, self.items.count == 1 ? @"" : @"s"];
    self.summaryLabel.textColor = TerraStyle.dimText;

    self.secondaryButton = [TerraStyle blockButtonWithTitle:@"Cancel" symbol:nil primary:NO];
    [self.secondaryButton addTarget:self action:@selector(secondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    self.primaryButton = [TerraStyle blockButtonWithTitle:[NSString stringWithFormat:@"Install %lu", (unsigned long)self.items.count]
                                                   symbol:@"arrow.down.circle.fill" primary:YES];
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[self.secondaryButton, self.primaryButton]];
    buttons.spacing = 10;
    buttons.distribution = UIStackViewDistributionFillEqually;

    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[self.progressView, self.summaryLabel, buttons]];
    footer.axis = UILayoutConstraintAxisVertical;
    footer.spacing = 12;

    for (UIView *v in @[header, scroll, footer]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:v];
    }
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:g.topAnchor constant:22],
        [header.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-14],
        [list.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [list.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [list.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [footer.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [footer.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-18],
    ]];
}

- (UIView *)rowForItem:(TPOItem *)item {
    UIView *card = [TerraStyle cardView];
    UIImageView *icon = [UIImageView new];
    icon.contentMode = UIViewContentModeCenter;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = TerraStyle.greenBright;
    spinner.hidesWhenStopped = YES;
    UILabel *name = [UILabel new];
    name.text = item.name;
    name.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    name.textColor = TerraStyle.text;
    UILabel *kind = [TerraStyle chipWithText:[item.contentType isEqualToString:@"mod"] ? @"Mod" : @"Resource pack"
                                       color:[item.contentType isEqualToString:@"mod"] ? TerraStyle.greenBright : TerraStyle.warning];
    UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[name, kind, [UIView new]]];
    nameRow.spacing = 8;
    nameRow.alignment = UIStackViewAlignmentCenter;
    UILabel *detail = [UILabel new];
    detail.font = TerraStyle.captionFont;
    detail.textColor = TerraStyle.dimText;
    detail.numberOfLines = 2;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, detail]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    for (UIView *v in @[icon, spinner, text]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [icon.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [spinner.centerXAnchor constraintEqualToAnchor:icon.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:icon.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [text.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [text.topAnchor constraintEqualToAnchor:card.topAnchor constant:9],
        [text.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-9],
    ]];
    [self.iconViews addObject:icon];
    [self.spinners addObject:spinner];
    [self.detailLabels addObject:detail];
    [self applyItem:item index:self.iconViews.count - 1];
    return card;
}

- (void)applyItem:(TPOItem *)item index:(NSUInteger)index {
    if (index >= self.iconViews.count) return;
    UIImageView *icon = self.iconViews[index];
    UIActivityIndicatorView *spinner = self.spinners[index];
    UILabel *detail = self.detailLabels[index];
    detail.text = item.detail;
    NSString *symbol = @"circle";
    UIColor *tint = TerraStyle.dimText;
    switch (item.state) {
        case TPOStatePending: break;
        case TPOStateWorking: symbol = nil; break;
        case TPOStateInstalled: symbol = @"checkmark.circle.fill"; tint = TerraStyle.greenBright; break;
        case TPOStateAlready: symbol = @"checkmark.circle"; tint = TerraStyle.greenBright; break;
        case TPOStateSkipped: symbol = @"minus.circle"; tint = TerraStyle.dimText; break;
        case TPOStateFailed: symbol = @"xmark.circle.fill"; tint = TerraStyle.danger; break;
    }
    if (symbol) {
        [spinner stopAnimating];
        icon.hidden = NO;
        icon.image = [UIImage systemImageNamed:symbol withConfiguration:
                      [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]];
        icon.tintColor = tint;
    } else {
        icon.hidden = YES;
        [spinner startAnimating];
    }
}

- (void)refreshItem:(TPOItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index != NSNotFound && self.isViewLoaded) [self applyItem:item index:index];
}

- (void)setOverallProgress:(double)progress {
    [self.progressView setProgress:(float)progress animated:YES];
}

- (void)primaryTapped {
    if (self.finished) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    if (self.running) return;
    self.running = YES;
    self.modalInPresentation = YES;
    self.progressView.hidden = NO;
    self.summaryLabel.text = @"Installing…";
    self.summaryLabel.textColor = TerraStyle.dimText;
    [self.primaryButton setTitle:@"Installing…" forState:UIControlStateNormal];
    self.primaryButton.enabled = NO;
    [self.secondaryButton setTitle:@"Hide" forState:UIControlStateNormal];
    if (self.onStart) self.onStart();
}

- (void)secondaryTapped {
    // Hide keeps the work going in the background; Cancel before start drops the pending run.
    if (!self.running) self.onStart = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishWithSummary:(NSString *)summary {
    self.finished = YES;
    self.running = NO;
    self.modalInPresentation = NO;
    [self setOverallProgress:1];
    self.summaryLabel.text = summary;
    self.summaryLabel.textColor = TerraStyle.text;
    [self.primaryButton setTitle:@"Done" forState:UIControlStateNormal];
    [self.primaryButton setImage:nil forState:UIControlStateNormal];
    self.primaryButton.enabled = YES;
    self.secondaryButton.hidden = YES;
}

@end

#pragma mark - Engine

@interface TPORun : NSObject
@property (nonatomic, copy) NSString *runName;
@property (nonatomic, strong) TerraBrowseTarget *target;
@property (nonatomic, copy) NSArray<TPOItem *> *items;
@property (nonatomic, strong) TPOSheetController *sheet;
@property (nonatomic, strong) NSMutableSet<NSString *> *installedIds;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *slugToId;
@property (nonatomic, strong) NSMutableArray<NSString *> *dependencyNames;
@property (nonatomic, assign) BOOL updateOptions;
@end

@implementation TPORun

static NSMutableSet<TPORun *> *TPOActiveRuns(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSMutableSet set]; });
    return set;
}

- (void)start {
    [TPOActiveRuns() addObject:self];   // keep alive while the sheet may be hidden
    self.installedIds = [NSMutableSet set];
    self.dependencyNames = [NSMutableArray array];
    TerraBrowseAPI *api = TerraBrowseAPI.shared;
    NSString *modsFolder = [self.target ensureFolderForContentType:@"mod"];
    NSMutableArray *slugs = [NSMutableArray array];
    for (TPOItem *i in self.items) if ([i.contentType isEqualToString:@"mod"]) [slugs addObjectsFromArray:i.slugs];
    void (^go)(void) = ^{ [self processIndex:0]; };
    if (slugs.count == 0 || !modsFolder) {
        go();
        return;
    }
    [api installedModrinthProjectIdsInFolder:modsFolder completion:^(NSSet<NSString *> *ids) {
        [self.installedIds unionSet:ids];
        [api modrinthIdsForSlugs:slugs completion:^(NSDictionary<NSString *, NSString *> *map) {
            self.slugToId = map;
            go();
        }];
    }];
}

- (void)update:(TPOItem *)item state:(TPOState)state detail:(NSString *)detail {
    item.state = state;
    item.detail = detail;
    [self.sheet refreshItem:item];
}

- (void)processIndex:(NSUInteger)index {
    [self.sheet setOverallProgress:self.items.count ? 0.9 * index / self.items.count : 0.9];
    if (index >= self.items.count) {
        [self installDependencies];
        return;
    }
    TPOItem *item = self.items[index];
    void (^next)(void) = ^{ [self processIndex:index + 1]; };
    if ([item.contentType isEqualToString:@"mod"]) {
        for (NSString *slug in item.slugs) {
            NSString *pid = self.slugToId[slug];
            if (pid && [self.installedIds containsObject:pid]) {
                [self update:item state:TPOStateAlready detail:@"Already installed"];
                next();
                return;
            }
        }
    }
    [self update:item state:TPOStateWorking detail:@"Finding a compatible version…"];
    [self findFileForItem:item slugIndex:0 completion:^(TerraBrowseFile *file) {
        if (!file) {
            [self update:item state:TPOStateSkipped detail:[NSString stringWithFormat:@"No version for %@ %@",
                [item.contentType isEqualToString:@"mod"] ? self.target.loaderDisplayName : @"Minecraft", self.target.gameVersion]];
            next();
            return;
        }
        NSString *folder = [self.target ensureFolderForContentType:item.contentType];
        if (!folder) {
            [self update:item state:TPOStateFailed detail:@"Couldn't create the folder"];
            next();
            return;
        }
        if ([NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:file.fileName]]) {
            item.installedFile = file;
            [self update:item state:TPOStateAlready detail:@"Already installed"];
            next();
            return;
        }
        [self update:item state:TPOStateWorking detail:[NSString stringWithFormat:@"Downloading %@…", file.versionNumber]];
        [TerraBrowseAPI.shared downloadFile:file toFolder:folder progress:nil completion:^(NSString *path, NSError *error) {
            if (path) {
                item.installedFile = file;
                if (file.projectId.length) [self.installedIds addObject:file.projectId];
                [self update:item state:TPOStateInstalled detail:[NSString stringWithFormat:@"Installed %@", file.versionNumber]];
            } else {
                [self update:item state:TPOStateFailed detail:error.localizedDescription ?: @"Download failed"];
            }
            next();
        }];
    }];
}

/// "1.21.4" → "1.21"
static NSString *TPOMajorMinor(NSString *version) {
    NSArray *parts = [version componentsSeparatedByString:@"."];
    return parts.count >= 2 ? [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]] : version;
}

- (void)findFileForItem:(TPOItem *)item slugIndex:(NSUInteger)slugIndex completion:(void (^)(TerraBrowseFile *))completion {
    if (slugIndex >= item.slugs.count) {
        completion(nil);
        return;
    }
    NSString *slug = item.slugs[slugIndex];
    TerraBrowseAPI *api = TerraBrowseAPI.shared;
    BOOL isMod = [item.contentType isEqualToString:@"mod"];
    NSString *gameVersion = self.target.gameVersion;
    [api versionsForProjectId:slug source:TerraBrowseSourceModrinth contentType:item.contentType
                       loader:isMod ? self.target.loader : nil gameVersion:gameVersion
                   completion:^(NSArray<TerraBrowseFile *> *files, NSError *error) {
        TerraBrowseFile *pick = files.firstObject;
        if (pick) {
            completion(pick);
            return;
        }
        if (isMod) {
            [self findFileForItem:item slugIndex:slugIndex + 1 completion:completion];
            return;
        }
        // Resource packs: fall back to the newest version for the same major.minor.
        NSString *mm = TPOMajorMinor(gameVersion);
        [api versionsForProjectId:slug source:TerraBrowseSourceModrinth contentType:item.contentType
                           loader:nil gameVersion:nil completion:^(NSArray<TerraBrowseFile *> *all, NSError *e2) {
            for (TerraBrowseFile *f in all) {
                for (NSString *gv in f.gameVersions) {
                    if ([gv isEqualToString:mm] || [gv hasPrefix:[mm stringByAppendingString:@"."]]) {
                        completion(f);
                        return;
                    }
                }
            }
            [self findFileForItem:item slugIndex:slugIndex + 1 completion:completion];
        }];
    }];
}

- (void)installDependencies {
    NSMutableArray<TerraBrowseFile *> *mods = [NSMutableArray array];
    for (TPOItem *i in self.items) {
        if (i.state == TPOStateInstalled && [i.contentType isEqualToString:@"mod"] && i.installedFile) [mods addObject:i.installedFile];
    }
    if (mods.count == 0) {
        [self finish];
        return;
    }
    self.sheet.summaryLabel.text = @"Checking required dependencies…";
    [self installDependenciesOf:mods index:0];
}

- (void)installDependenciesOf:(NSArray<TerraBrowseFile *> *)mods index:(NSUInteger)index {
    if (index >= mods.count) {
        [self finish];
        return;
    }
    [TerraBrowseAPI.shared installDependenciesOfFile:mods[index] target:self.target installedProjects:[self.installedIds copy]
                                          completion:^(NSArray<NSString *> *installed, NSArray<NSString *> *failed) {
        for (NSString *name in installed) {
            if (![self.dependencyNames containsObject:name]) [self.dependencyNames addObject:name];
        }
        // Record what the dependency downloads added so later mods don't fetch them again.
        [TerraBrowseAPI.shared installedModrinthProjectIdsInFolder:[self.target folderForContentType:@"mod"]
                                                        completion:^(NSSet<NSString *> *ids) {
            [self.installedIds unionSet:ids];
            [self installDependenciesOf:mods index:index + 1];
        }];
    }];
}

- (BOOL)addPacksToOptions:(NSArray<NSString *> *)fileNames {
    NSString *path = [self.target.gameDir stringByAppendingPathComponent:@"options.txt"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0 || fileNames.count == 0) return NO;
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    NSInteger lineIndex = -1;
    NSMutableArray *packs = [NSMutableArray array];
    for (NSUInteger i = 0; i < lines.count; i++) {
        if ([lines[i] hasPrefix:@"resourcePacks:"]) {
            lineIndex = (NSInteger)i;
            NSString *value = [lines[i] substringFromIndex:@"resourcePacks:".length];
            id parsed = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([parsed isKindOfClass:NSArray.class]) [packs addObjectsFromArray:parsed];
            break;
        }
    }
    [packs removeObject:@"vanilla"];
    [packs insertObject:@"vanilla" atIndex:0];
    // Later entries have higher priority: the base pack (first in fileNames) goes below the overlays.
    for (NSString *name in fileNames) {
        NSString *entry = [@"file/" stringByAppendingString:name];
        if (![packs containsObject:entry]) [packs addObject:entry];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:packs options:0 error:nil];
    if (!json) return NO;
    NSString *line = [@"resourcePacks:" stringByAppendingString:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    line = [line stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    if (lineIndex >= 0) lines[lineIndex] = line;
    else [lines insertObject:line atIndex:MAX((NSInteger)lines.count - 1, 0)];
    return [[lines componentsJoinedByString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)finish {
    NSUInteger total = self.items.count, installed = 0, already = 0;
    NSMutableArray *skipped = [NSMutableArray array], *failed = [NSMutableArray array];
    NSMutableArray *packFiles = [NSMutableArray array];
    BOOL anyPack = NO;
    for (TPOItem *i in self.items) {
        if (i.state == TPOStateInstalled) installed++;
        else if (i.state == TPOStateAlready) already++;
        else if (i.state == TPOStateSkipped) [skipped addObject:i.name];
        else if (i.state == TPOStateFailed) [failed addObject:i.name];
        if ([i.contentType isEqualToString:@"resourcepack"]) {
            anyPack = YES;
            if (i.installedFile && (i.state == TPOStateInstalled || i.state == TPOStateAlready)) [packFiles addObject:i.installedFile.fileName];
        }
    }
    NSMutableString *summary = [NSMutableString stringWithFormat:@"Installed %lu of %lu", (unsigned long)installed, (unsigned long)total];
    if (already) [summary appendFormat:@" — %lu already installed", (unsigned long)already];
    if (skipped.count) {
        [summary appendFormat:@" — skipped %lu: no version for %@ (%@)", (unsigned long)skipped.count,
         self.target.gameVersion, [skipped componentsJoinedByString:@", "]];
    }
    if (failed.count) [summary appendFormat:@" — failed: %@", [failed componentsJoinedByString:@", "]];
    [summary appendString:@"."];
    if (self.dependencyNames.count) {
        [summary appendFormat:@"\nAlso added required dependencies: %@.", [self.dependencyNames componentsJoinedByString:@", "]];
    }
    if (!self.target.hasModLoader && anyPack) {
        [summary appendString:@"\nThis installation has no mod loader, so only resource packs were installed."];
    }
    if (anyPack && packFiles.count) {
        if (self.updateOptions && [self addPacksToOptions:packFiles]) {
            [summary appendString:@"\nThe resource packs were enabled in your game options."];
        } else {
            [summary appendString:@"\nEnable the resource packs in Options → Resource Packs."];
        }
    }
    [self.sheet finishWithSummary:summary];
    self.sheet.onStart = nil;   // break sheet → block → run cycle
    [NSNotificationCenter.defaultCenter postNotificationName:TerraPotatoOptimizerDidFinishNotification object:nil
                                                    userInfo:@{@"profileName": self.target.name ?: @"", @"kind": self.runName ?: @""}];
    [TPOActiveRuns() removeObject:self];
}

@end

#pragma mark - Public

@implementation TerraPotatoOptimizer

+ (NSArray<TPOItem *> *)potatoItemsForLoader:(NSString *)loader {
    if ([loader isEqualToString:@"fabric"] || [loader isEqualToString:@"quilt"]) {
        return @[TPOMod(@"Sodium", @[@"sodium"], @"Modern rendering engine — the biggest FPS boost"),
                 TPOMod(@"Lithium", @[@"lithium"], @"Faster game logic, ticking and AI"),
                 TPOMod(@"FerriteCore", @[@"ferrite-core"], @"Cuts memory usage"),
                 TPOMod(@"ImmediatelyFast", @[@"immediatelyfast"], @"Faster HUD, text and entity rendering"),
                 TPOMod(@"Entity Culling", @[@"entityculling"], @"Skips rendering entities you can't see"),
                 TPOMod(@"ModernFix", @[@"modernfix"], @"Faster loading and less memory"),
                 TPOMod(@"More Culling", @[@"moreculling"], @"Culls more hidden block faces")];
    }
    if ([loader isEqualToString:@"neoforge"]) {
        return @[TPOMod(@"Sodium / Embeddium", @[@"sodium", @"embeddium"], @"Modern rendering engine — the biggest FPS boost"),
                 TPOMod(@"Lithium", @[@"lithium"], @"Faster game logic, ticking and AI"),
                 TPOMod(@"FerriteCore", @[@"ferrite-core"], @"Cuts memory usage"),
                 TPOMod(@"ModernFix", @[@"modernfix"], @"Faster loading and less memory"),
                 TPOMod(@"Entity Culling", @[@"entityculling"], @"Skips rendering entities you can't see"),
                 TPOMod(@"ImmediatelyFast", @[@"immediatelyfast"], @"Faster HUD, text and entity rendering")];
    }
    if ([loader isEqualToString:@"forge"]) {
        return @[TPOMod(@"Embeddium", @[@"embeddium"], @"Sodium-based rendering engine for Forge"),
                 TPOMod(@"FerriteCore", @[@"ferrite-core"], @"Cuts memory usage"),
                 TPOMod(@"ModernFix", @[@"modernfix"], @"Faster loading and less memory"),
                 TPOMod(@"Entity Culling", @[@"entityculling"], @"Skips rendering entities you can't see"),
                 TPOMod(@"ImmediatelyFast", @[@"immediatelyfast"], @"Faster HUD, text and entity rendering")];
    }
    return @[];
}

+ (NSArray<TPOItem *> *)competitiveItemsForLoader:(NSString *)loader {
    NSMutableArray *items = [NSMutableArray array];
    if ([loader isEqualToString:@"fabric"] || [loader isEqualToString:@"quilt"]) {
        [items addObjectsFromArray:@[
            TPOMod(@"Sodium", @[@"sodium"], @"Performance base: modern renderer"),
            TPOMod(@"Lithium", @[@"lithium"], @"Performance base: faster game logic"),
            TPOMod(@"Entity Culling", @[@"entityculling"], @"Performance base: hidden-entity culling"),
            TPOMod(@"ImmediatelyFast", @[@"immediatelyfast"], @"Performance base: faster HUD rendering"),
            TPOMod(@"Zoomify", @[@"zoomify"], @"Smooth configurable zoom"),
            TPOMod(@"Freelook", @[@"freelook"], @"Look around without turning"),
            TPOMod(@"uku's Armor HUD", @[@"ukus-armor-hud"], @"Armor durability on the hotbar"),
            TPOMod(@"TotemCounter", @[@"totemcounter"], @"Totem count and pops"),
            TPOMod(@"EvergreenHUD", @[@"evergreenhud"], @"FPS / CPS / keystrokes HUD"),
            TPOMod(@"Combat Hitboxes", @[@"combat-hitboxes"], @"Cleaner, clearer hitboxes")]];
    } else if ([loader isEqualToString:@"forge"] || [loader isEqualToString:@"neoforge"]) {
        BOOL neo = [loader isEqualToString:@"neoforge"];
        [items addObjectsFromArray:@[
            TPOMod(neo ? @"Sodium / Embeddium" : @"Embeddium", neo ? @[@"sodium", @"embeddium"] : @[@"embeddium"], @"Performance base: modern renderer"),
            TPOMod(@"FerriteCore", @[@"ferrite-core"], @"Performance base: less memory"),
            TPOMod(@"Entity Culling", @[@"entityculling"], @"Performance base: hidden-entity culling"),
            TPOMod(@"Just Zoom", @[@"just-zoom"], @"Zoom key"),
            TPOMod(@"FreeLook", @[@"freelook-og"], @"Look around without turning"),
            TPOMod(@"Armor HUD", neo ? @[@"ukus-armor-hud", @"armor-hud"] : @[@"armor-hud"], @"Armor durability on screen")]];
        if (neo) [items addObject:TPOMod(@"TotemCounter", @[@"totemcounter"], @"Totem count and pops")];
    }
    [items addObjectsFromArray:@[
        TPOPack(@"Spunky PvP", @"spunky-pvp-texture-pack", @"Base PvP texture pack"),
        TPOPack(@"Low Fire", @"low-fire-pack", @"Lower fire overlay"),
        TPOPack(@"Short PvP Swords", @"short-pvp-swords", @"Smaller sword models"),
        TPOPack(@"Small Shield & Totem", @"small-shield-totem", @"Smaller shield and totem in hand"),
        TPOPack(@"PvP Crosshair", @"pvp-crosshair", @"Clear crosshair"),
        TPOPack(@"Clearer Slot Highlight", @"clearer-slot-highlight", @"Easier to see the selected slot")]];
    return items;
}

+ (void)runNamed:(NSString *)runName symbol:(NSString *)symbol profile:(NSString *)profileName presenter:(UIViewController *)presenter
     competitive:(BOOL)competitive {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *host = presenter ?: [TerraVersionInstaller topPresenter];
        while (host.presentedViewController && !host.presentedViewController.isBeingDismissed) host = host.presentedViewController;
        TerraBrowseTarget *target = profileName.length ? [TerraBrowseTarget targetNamed:profileName] : nil;
        if (!target) target = [TerraBrowseTarget defaultTarget];
        if (!target) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:runName
                message:@"Create an installation first (Download Center → Minecraft Versions), then try again."
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [host presentViewController:alert animated:YES completion:nil];
            return;
        }
        if (!competitive && !target.hasModLoader) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mods need a mod loader"
                message:[NSString stringWithFormat:@"\"%@\" is plain Minecraft %@. Performance mods run on Fabric (recommended), Forge or NeoForge. Install Fabric for %@, then run Potato Optimize on it.",
                         target.name, target.gameVersion, target.gameVersion]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Install Fabric…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                [TerraVersionInstaller presentInstallForVersion:target.gameVersion from:host];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [host presentViewController:alert animated:YES completion:nil];
            return;
        }
        NSArray *items = competitive ? [self competitiveItemsForLoader:target.loader] : [self potatoItemsForLoader:target.loader];

        TPORun *run = [TPORun new];
        run.runName = runName;
        run.target = target;
        run.items = items;
        run.updateOptions = competitive;

        TPOSheetController *sheet = [TPOSheetController new];
        sheet.heading = runName;
        sheet.symbol = symbol;
        sheet.items = items;
        sheet.subtitle = [NSString stringWithFormat:@"Into \"%@\" · %@ %@", target.name, target.loaderDisplayName, target.gameVersion];
        if (competitive && !target.hasModLoader) {
            sheet.note = @"This installation has no mod loader, so only the resource packs will be installed. Install Fabric to get the PvP mods too.";
        }
        __weak TPOSheetController *weakSheet = sheet;
        sheet.onStart = ^{
            run.sheet = weakSheet;
            [run start];
        };
        sheet.modalPresentationStyle = UIModalPresentationFormSheet;
        sheet.preferredContentSize = CGSizeMake(540, 680);
        // The run holds the sheet strongly while working so "Hide" doesn't lose progress updates.
        run.sheet = sheet;
        [host presentViewController:sheet animated:YES completion:nil];
    });
}

+ (void)optimizeProfile:(NSString *)profileName presenter:(UIViewController *)presenter {
    [self runNamed:@"Potato Optimize" symbol:@"bolt.fill" profile:profileName presenter:presenter competitive:NO];
}

+ (void)competitiveProfile:(NSString *)profileName presenter:(UIViewController *)presenter {
    [self runNamed:@"Competitive Download" symbol:@"trophy.fill" profile:profileName presenter:presenter competitive:YES];
}

@end
