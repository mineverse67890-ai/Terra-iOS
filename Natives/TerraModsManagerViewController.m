//
//  TerraModsManagerViewController.m
//  ★ [TERRA-MODS] see TerraModsManagerViewController.h
//
//  Layout
//   - Regular width: 240pt sidebar (content sections with counts, Show filter, Sort, actions)
//     + main area (title, search field, list).
//   - Narrow width: sidebar hidden; a segmented control picks the section and the "..." menu
//     carries filter / sort / actions.
//  Data comes from the existing services; nothing here touches the files directly except
//  "Import Files" (copies picked files into the section folder).
//

#import "TerraModsManagerViewController.h"
#import "TerraStyle.h"
#import "ModService.h"
#import "ShaderService.h"
#import "ResourcePackService.h"
#import "DataPackService.h"
#import "DownloadViewController.h"
#import "DownloadTaskManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString * const TerraModsContentDidChangeNotification = @"TerraModsContentDidChangeNotification";
static NSString * const TerraModsPotatoDidFinishNotification = @"TerraPotatoOptimizerDidFinishNotification";

typedef NS_ENUM(NSInteger, TerraModsKind) {
    TerraModsKindMod = 0,
    TerraModsKindShader,
    TerraModsKindResourcePack,
    TerraModsKindDataPack,
    TerraModsKindCount
};

typedef NS_ENUM(NSInteger, TerraModsFilter) {
    TerraModsFilterAll = 0,
    TerraModsFilterEnabled,
    TerraModsFilterDisabled,
};

typedef NS_ENUM(NSInteger, TerraModsSort) {
    TerraModsSortName = 0,
    TerraModsSortRecent,
    TerraModsSortSize,
};

static NSString *TerraModsKindTitle(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"Mods";
        case TerraModsKindShader: return @"Shader Packs";
        case TerraModsKindResourcePack: return @"Resource Packs";
        default: return @"Data Packs";
    }
}

static NSString *TerraModsKindShortTitle(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"Mods";
        case TerraModsKindShader: return @"Shaders";
        case TerraModsKindResourcePack: return @"Resources";
        default: return @"Data";
    }
}

static NSString *TerraModsKindSingular(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"mod";
        case TerraModsKindShader: return @"shader pack";
        case TerraModsKindResourcePack: return @"resource pack";
        default: return @"data pack";
    }
}

static NSString *TerraModsKindSymbol(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"puzzlepiece.extension";
        case TerraModsKindShader: return @"sparkles";
        case TerraModsKindResourcePack: return @"photo.stack";
        default: return @"tray.full";
    }
}

/// contentType string understood by TerraBrowseViewController.
static NSString *TerraModsKindContentType(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"mod";
        case TerraModsKindShader: return @"shader";
        case TerraModsKindResourcePack: return @"resourcepack";
        default: return @"datapack";
    }
}

/// Modrinth project-type path used for "Search on Modrinth".
static NSString *TerraModsKindModrinthPath(TerraModsKind k) {
    switch (k) {
        case TerraModsKindMod: return @"mods";
        case TerraModsKindShader: return @"shaders";
        case TerraModsKindResourcePack: return @"resourcepacks";
        default: return @"datapacks";
    }
}

static NSString *TerraModsString(id value) {
    if ([value isKindOfClass:NSString.class]) {
        NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return s.length ? s : nil;
    }
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue];
    return nil;
}

#pragma mark - Entry (uniform wrapper over ModItem / ShaderItem / ResourcePackItem / DataPackItem)

@interface TerraModsEntry : NSObject
@property (nonatomic, assign) TerraModsKind kind;
@property (nonatomic, strong) id item;
@property (nonatomic, assign) long long fileSize;
@property (nonatomic, strong) NSDate *addedDate;
- (NSString *)title;
- (NSString *)version;
- (NSString *)author;
- (NSString *)fileName;
- (NSString *)filePath;
- (NSString *)summary;
- (NSString *)homepage;
- (NSString *)sources;
- (NSString *)gameVersion;
- (NSString *)loaderName;
- (NSNumber *)packFormat;
- (UIImage *)icon;
- (BOOL)disabled;
@end

@implementation TerraModsEntry

- (id)value:(NSString *)key {
    @try { return [self.item valueForKey:key]; } @catch (NSException *e) { return nil; }
}

- (NSString *)fileName { return TerraModsString([self value:@"fileName"]) ?: @""; }
- (NSString *)filePath { return TerraModsString([self value:@"filePath"]) ?: @""; }

- (NSString *)title {
    NSString *name = TerraModsString([self value:@"displayName"]);
    if (name) return name;
    NSString *file = self.fileName;
    for (NSString *suffix in @[@".disabled", @".jar", @".zip"]) {
        if ([file.lowercaseString hasSuffix:suffix]) file = [file substringToIndex:file.length - suffix.length];
    }
    return file.length ? file : @"Unknown";
}

- (NSString *)version { return TerraModsString([self value:@"version"]); }
- (NSString *)homepage { return TerraModsString([self value:@"homepage"]); }
- (NSString *)sources { return TerraModsString([self value:@"sources"]); }
- (NSString *)gameVersion { return TerraModsString([self value:@"gameVersion"]); }

- (NSString *)author {
    id raw = [self value:@"author"];
    if ([raw isKindOfClass:NSArray.class]) {
        NSMutableArray *names = [NSMutableArray array];
        for (id a in (NSArray *)raw) {
            NSString *s = [a isKindOfClass:NSDictionary.class] ? TerraModsString(((NSDictionary *)a)[@"name"]) : TerraModsString(a);
            if (s) [names addObject:s];
        }
        return names.count ? [names componentsJoinedByString:@", "] : nil;
    }
    NSString *s = TerraModsString(raw);
    // fabric.mod.json allows {"name": ...} author objects; ModService joins their -description.
    if ([s containsString:@"name ="]) {
        NSMutableArray *names = [NSMutableArray array];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"name = \"?([^;\"]+)\"?;" options:0 error:nil];
        for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
            [names addObject:[s substringWithRange:[m rangeAtIndex:1]]];
        }
        if (names.count) return [names componentsJoinedByString:@", "];
    }
    return s;
}

- (NSString *)summary {
    NSString *key = @"modDescription";
    switch (self.kind) {
        case TerraModsKindShader: key = @"shaderDescription"; break;
        case TerraModsKindResourcePack: key = @"resourcePackDescription"; break;
        case TerraModsKindDataPack: key = @"dataPackDescription"; break;
        default: break;
    }
    return TerraModsString([self value:key]);
}

- (NSString *)loaderName {
    if (self.kind != TerraModsKindMod) return nil;
    if ([[self value:@"isFabric"] boolValue]) return @"Fabric";
    if ([[self value:@"isNeoForge"] boolValue]) return @"NeoForge";
    if ([[self value:@"isForge"] boolValue]) return @"Forge";
    return nil;
}

- (NSNumber *)packFormat {
    if (self.kind != TerraModsKindResourcePack && self.kind != TerraModsKindDataPack) return nil;
    id v = [self value:@"packFormat"];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

- (UIImage *)icon {
    id v = [self value:@"icon"];
    return [v isKindOfClass:UIImage.class] ? v : nil;
}

- (BOOL)disabled { return [[self value:@"disabled"] boolValue]; }

- (void)refreshFileAttributes {
    NSDictionary *attrs = self.filePath.length ? [NSFileManager.defaultManager attributesOfItemAtPath:self.filePath error:nil] : nil;
    self.fileSize = [attrs[NSFileSize] longLongValue];
    self.addedDate = attrs[NSFileCreationDate] ?: attrs[NSFileModificationDate] ?: NSDate.distantPast;
}

@end

#pragma mark - Service adapter

static void TerraModsScan(TerraModsKind kind, NSString *profile, void (^done)(NSArray *items)) {
    void (^finish)(NSArray *) = ^(NSArray *items) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(items ?: @[]); });
    };
    if (kind == TerraModsKindMod) {
        [ModService.sharedService scanModsForProfile:profile completion:^(NSArray<ModItem *> *mods) { finish(mods); }];
    } else if (kind == TerraModsKindShader) {
        [ShaderService.sharedService scanShadersForProfile:profile completion:^(NSArray<ShaderItem *> *s) { finish(s); }];
    } else if (kind == TerraModsKindResourcePack) {
        [ResourcePackService.sharedService scanResourcePacksForProfile:profile completion:^(NSArray<ResourcePackItem *> *r) { finish(r); }];
    } else {
        [DataPackService.sharedService scanDataPacksForProfile:profile completion:^(NSArray<DataPackItem *> *d) { finish(d); }];
    }
}

static BOOL TerraModsToggle(TerraModsEntry *e, NSError **error) {
    switch (e.kind) {
        case TerraModsKindMod: return [ModService.sharedService toggleEnableForMod:e.item error:error];
        case TerraModsKindShader: return [ShaderService.sharedService toggleEnableForShader:e.item error:error];
        case TerraModsKindResourcePack: return [ResourcePackService.sharedService toggleEnableForResourcePack:e.item error:error];
        default: return [DataPackService.sharedService toggleEnableForDataPack:e.item error:error];
    }
}

static BOOL TerraModsDelete(TerraModsEntry *e, NSError **error) {
    switch (e.kind) {
        case TerraModsKindMod: return [ModService.sharedService deleteMod:e.item error:error];
        case TerraModsKindShader: return [ShaderService.sharedService deleteShader:e.item error:error];
        case TerraModsKindResourcePack: return [ResourcePackService.sharedService deleteResourcePack:e.item error:error];
        default: return [DataPackService.sharedService deleteDataPack:e.item error:error];
    }
}

static NSString *TerraModsFolder(TerraModsKind kind, NSString *profile, NSError **error) {
    switch (kind) {
        case TerraModsKindMod: return [ModService.sharedService ensureModsFolderForProfile:profile error:error];
        case TerraModsKindShader: return [ShaderService.sharedService ensureShadersFolderForProfile:profile error:error];
        case TerraModsKindResourcePack: return [ResourcePackService.sharedService ensureResourcePacksFolderForProfile:profile error:error];
        default: return [DataPackService.sharedService ensureDataPacksFolderForProfile:profile error:error];
    }
}

static NSString *TerraModsFormatSize(long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

#pragma mark - Icon view (metadata icon, grass block fallback)

@interface TerraModsIconView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *grass;
- (instancetype)initWithSize:(CGFloat)size;
- (void)setIcon:(UIImage *)icon;
@end

@implementation TerraModsIconView

- (instancetype)initWithSize:(CGFloat)size {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = TerraStyle.raised;
        self.layer.cornerRadius = 4;
        self.clipsToBounds = YES;
        _imageView = [UIImageView new];
        _imageView.translatesAutoresizingMaskIntoConstraints = NO;
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.layer.magnificationFilter = kCAFilterNearest; // pixel-art icons stay crisp
        [self addSubview:_imageView];
        _grass = [TerraStyle grassBlockOfSize:round(size * 0.72 / 4.0) * 4.0];
        [self addSubview:_grass];
        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:size],
            [self.heightAnchor constraintEqualToConstant:size],
            [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_grass.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_grass.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setIcon:(UIImage *)icon {
    self.imageView.image = icon;
    self.imageView.hidden = (icon == nil);
    self.grass.hidden = (icon != nil);
}

@end

#pragma mark - Row cell

@interface TerraModsCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIStackView *dimmable;
@property (nonatomic, strong) TerraModsIconView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *loaderChip;
@property (nonatomic, strong) UILabel *disabledChip;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UILabel *fileLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, copy) void (^onToggle)(BOOL enabled);
@property (nonatomic, copy) void (^onDelete)(void);
- (void)configureWithEntry:(TerraModsEntry *)entry;
@end

@implementation TerraModsCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _card = [TerraStyle cardView];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_card];

        _iconView = [[TerraModsIconView alloc] initWithSize:44];

        _nameLabel = [UILabel new];
        _nameLabel.font = TerraStyle.headlineFont;
        _nameLabel.textColor = TerraStyle.text;
        [_nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        _loaderChip = [TerraStyle chipWithText:@"Fabric" color:TerraStyle.greenBright];
        _disabledChip = [TerraStyle chipWithText:@"Disabled" color:TerraStyle.dimText];
        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _loaderChip, _disabledChip, spacer]];
        nameRow.spacing = 8;
        nameRow.alignment = UIStackViewAlignmentCenter;

        _metaLabel = [UILabel new];
        _metaLabel.font = TerraStyle.captionFont;
        _metaLabel.textColor = TerraStyle.dimText;

        _fileLabel = [UILabel new];
        _fileLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        _fileLabel.textColor = [TerraStyle.dimText colorWithAlphaComponent:0.7];
        _fileLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, _metaLabel, _fileLabel]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 3;

        _dimmable = [[UIStackView alloc] initWithArrangedSubviews:@[_iconView, texts]];
        _dimmable.spacing = 14;
        _dimmable.alignment = UIStackViewAlignmentCenter;

        _toggle = [UISwitch new];
        _toggle.onTintColor = TerraStyle.green;
        [_toggle addTarget:self action:@selector(toggleChanged) forControlEvents:UIControlEventValueChanged];

        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
        _deleteButton.tintColor = TerraStyle.danger;
        _deleteButton.accessibilityLabel = @"Delete";
        [_deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [_deleteButton.widthAnchor constraintEqualToConstant:36].active = YES;
        [_deleteButton.heightAnchor constraintEqualToConstant:36].active = YES;

        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_dimmable, _toggle, _deleteButton]];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        [_card addSubview:row];

        [NSLayoutConstraint activateConstraints:@[
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [row.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:12],
            [row.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-8],
            [row.topAnchor constraintEqualToAnchor:_card.topAnchor constant:12],
            [row.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-12],
        ]];
    }
    return self;
}

- (void)configureWithEntry:(TerraModsEntry *)entry {
    BOOL disabled = entry.disabled;
    self.nameLabel.text = entry.title;
    [self.iconView setIcon:entry.icon];

    NSString *loader = entry.loaderName;
    self.loaderChip.hidden = (loader == nil);
    if (loader) self.loaderChip.text = [NSString stringWithFormat:@"  %@  ", loader];
    self.disabledChip.hidden = !disabled;

    NSMutableArray *meta = [NSMutableArray array];
    if (entry.version) [meta addObject:[entry.version hasPrefix:@"v"] ? entry.version : [@"v" stringByAppendingString:entry.version]];
    if (entry.author) [meta addObject:[@"by " stringByAppendingString:entry.author]];
    if (entry.packFormat) [meta addObject:[NSString stringWithFormat:@"pack format %@", entry.packFormat]];
    if (meta.count == 0) [meta addObject:TerraModsFormatSize(entry.fileSize)];
    self.metaLabel.text = [meta componentsJoinedByString:@"  ·  "];
    self.fileLabel.text = entry.fileName;

    self.toggle.on = !disabled;
    self.dimmable.alpha = disabled ? 0.45 : 1.0;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", entry.title, disabled ? @"disabled" : @"enabled"];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.card.backgroundColor = highlighted ? TerraStyle.raised : TerraStyle.surface;
}

- (void)toggleChanged { if (self.onToggle) self.onToggle(self.toggle.on); }
- (void)deleteTapped { if (self.onDelete) self.onDelete(); }

@end

#pragma mark - Detail screen

@interface TerraModsDetailViewController : UIViewController
@property (nonatomic, strong) TerraModsEntry *entry;
@property (nonatomic, copy) BOOL (^onToggle)(TerraModsEntry *entry);   ///< returns success
@property (nonatomic, copy) void (^onDelete)(TerraModsEntry *entry, void (^deleted)(void));
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation TerraModsDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];
    self.title = self.entry.title;

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    [scroll addSubview:self.stack];

    UILayoutGuide *content = scroll.contentLayoutGuide;
    NSLayoutConstraint *maxWidth = [self.stack.widthAnchor constraintLessThanOrEqualToConstant:720];
    NSLayoutConstraint *fill = [self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40];
    fill.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [self.stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-28],
        [self.stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],
        [self.stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:20],
        maxWidth, fill,
    ]];
    [self rebuild];
}

- (UIView *)cardWithContent:(UIView *)inner {
    UIView *card = [TerraStyle cardView];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
    ]];
    return card;
}

- (UIView *)infoRow:(NSString *)key value:(NSString *)value {
    UILabel *k = [UILabel new];
    k.text = key;
    k.font = TerraStyle.captionFont;
    k.textColor = TerraStyle.dimText;
    [k.widthAnchor constraintEqualToConstant:110].active = YES;
    UILabel *v = [UILabel new];
    v.text = value;
    v.font = TerraStyle.bodyFont;
    v.textColor = TerraStyle.text;
    v.numberOfLines = 0;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[k, v]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentFirstBaseline;
    return row;
}

- (void)rebuild {
    for (UIView *v in self.stack.arrangedSubviews) [v removeFromSuperview];
    TerraModsEntry *e = self.entry;

    // Header
    TerraModsIconView *icon = [[TerraModsIconView alloc] initWithSize:64];
    [icon setIcon:e.icon];
    icon.alpha = e.disabled ? 0.5 : 1;
    UILabel *name = [UILabel new];
    name.text = e.title;
    name.font = TerraStyle.titleFont;
    name.textColor = TerraStyle.text;
    name.numberOfLines = 2;
    UILabel *sub = [UILabel new];
    NSMutableArray *parts = [NSMutableArray array];
    if (e.version) [parts addObject:[@"Version " stringByAppendingString:e.version]];
    if (e.author) [parts addObject:[@"by " stringByAppendingString:e.author]];
    sub.text = parts.count ? [parts componentsJoinedByString:@"  ·  "] : TerraModsKindSingular(e.kind).capitalizedString;
    sub.font = TerraStyle.bodyFont;
    sub.textColor = TerraStyle.dimText;
    sub.numberOfLines = 2;
    NSMutableArray *chips = [NSMutableArray array];
    [chips addObject:e.disabled ? [TerraStyle chipWithText:@"Disabled" color:TerraStyle.dimText]
                                : [TerraStyle chipWithText:@"Enabled" color:TerraStyle.greenBright]];
    if (e.loaderName) [chips addObject:[TerraStyle chipWithText:e.loaderName color:TerraStyle.warning]];
    [chips addObject:[UIView new]];
    UIStackView *chipRow = [[UIStackView alloc] initWithArrangedSubviews:chips];
    chipRow.spacing = 6;
    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[name, sub, chipRow]];
    titles.axis = UILayoutConstraintAxisVertical;
    titles.spacing = 6;
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[icon, titles]];
    header.spacing = 16;
    header.alignment = UIStackViewAlignmentCenter;
    [self.stack addArrangedSubview:[self cardWithContent:header]];

    // Actions
    UIButton *toggle = [TerraStyle blockButtonWithTitle:e.disabled ? @"Enable" : @"Disable"
                                                 symbol:e.disabled ? @"checkmark" : @"pause.fill"
                                                primary:e.disabled];
    [toggle addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *del = [TerraStyle dangerButtonWithTitle:@"Delete" symbol:@"trash"];
    [del addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[toggle, del]];
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    [self.stack addArrangedSubview:actions];

    // Description
    [self.stack setCustomSpacing:20 afterView:actions];
    [self.stack addArrangedSubview:[TerraStyle sectionLabel:@"Description"]];
    UILabel *desc = [UILabel new];
    desc.text = e.summary ?: @"No description provided.";
    desc.font = TerraStyle.bodyFont;
    desc.textColor = e.summary ? TerraStyle.text : TerraStyle.dimText;
    desc.numberOfLines = 0;
    [self.stack addArrangedSubview:[self cardWithContent:desc]];

    // File
    [self.stack addArrangedSubview:[TerraStyle sectionLabel:@"File"]];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[self infoRow:@"File name" value:e.fileName]];
    [rows addObject:[self infoRow:@"Size" value:TerraModsFormatSize(e.fileSize)]];
    if (e.addedDate && ![e.addedDate isEqualToDate:NSDate.distantPast]) {
        [rows addObject:[self infoRow:@"Added" value:[NSDateFormatter localizedStringFromDate:e.addedDate
            dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]]];
    }
    if (e.gameVersion) [rows addObject:[self infoRow:@"Minecraft" value:e.gameVersion]];
    if (e.packFormat) [rows addObject:[self infoRow:@"Pack format" value:e.packFormat.stringValue]];
    [rows addObject:[self infoRow:@"Folder" value:e.filePath.stringByDeletingLastPathComponent.lastPathComponent]];
    UIStackView *fileStack = [[UIStackView alloc] initWithArrangedSubviews:rows];
    fileStack.axis = UILayoutConstraintAxisVertical;
    fileStack.spacing = 10;
    [self.stack addArrangedSubview:[self cardWithContent:fileStack]];

    // Links
    [self.stack addArrangedSubview:[TerraStyle sectionLabel:@"Links"]];
    NSMutableArray *links = [NSMutableArray array];
    if (e.homepage) [links addObject:@[@"Homepage", @"house", e.homepage]];
    if (e.sources) [links addObject:@[@"Source Code", @"chevron.left.forwardslash.chevron.right", e.sources]];
    NSString *query = [e.title stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet] ?: @"";
    [links addObject:@[@"Search on Modrinth", @"magnifyingglass",
                       [NSString stringWithFormat:@"https://modrinth.com/%@?q=%@", TerraModsKindModrinthPath(e.kind), query]]];
    UIStackView *linkStack = [UIStackView new];
    linkStack.axis = UILayoutConstraintAxisVertical;
    linkStack.spacing = 8;
    for (NSArray *l in links) {
        UIButton *b = [TerraStyle blockButtonWithTitle:l[0] symbol:l[1] primary:NO];
        b.accessibilityValue = l[2];
        [b addTarget:self action:@selector(linkTapped:) forControlEvents:UIControlEventTouchUpInside];
        [linkStack addArrangedSubview:b];
    }
    [self.stack addArrangedSubview:linkStack];
}

- (void)linkTapped:(UIButton *)sender {
    NSURL *url = [NSURL URLWithString:sender.accessibilityValue ?: @""];
    if (url.scheme.length) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)toggleTapped {
    if (self.onToggle && self.onToggle(self.entry)) {
        [self rebuild];
    }
}

- (void)deleteTapped {
    if (!self.onDelete) return;
    __weak typeof(self) weakSelf = self;
    self.onDelete(self.entry, ^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    });
}

@end

#pragma mark - Manager

@interface TerraModsManagerViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIDocumentPickerDelegate>
// State
@property (nonatomic, assign) TerraModsKind kind;
@property (nonatomic, assign) TerraModsFilter filter;
@property (nonatomic, assign) TerraModsSort sort;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<TerraModsEntry *> *> *entries;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *scanGeneration;
@property (nonatomic, strong) NSArray<TerraModsEntry *> *visible;
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, assign) BOOL layoutResolved;

// Sidebar
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) NSArray<UIButton *> *kindRows;
@property (nonatomic, strong) NSArray<UILabel *> *kindCounts;
@property (nonatomic, strong) NSArray<UIButton *> *filterRows;
@property (nonatomic, strong) NSArray<UILabel *> *filterCounts;
@property (nonatomic, strong) NSArray<UIButton *> *sortRows;
@property (nonatomic, strong) UIButton *potatoButton;

// Main
@property (nonatomic, strong) UIView *main;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) UISearchTextField *searchField;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyTitle;
@property (nonatomic, strong) UILabel *emptyMessage;
@property (nonatomic, strong) UIButton *emptyButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *wideConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *compactConstraints;
@property (nonatomic, strong) UIBarButtonItem *moreItem;
@property (nonatomic, strong) UIBarButtonItem *addItem;
@end

@implementation TerraModsManagerViewController

- (NSString *)profile { return self.profileName.length ? self.profileName : @"default"; }

- (BOOL)potatoAvailable {
    Class cls = NSClassFromString(@"TerraPotatoOptimizer");
    return cls && [cls respondsToSelector:NSSelectorFromString(@"optimizeProfile:presenter:")];
}

/// "Competitive Download" (PvP mods + PvP resource packs) lives next to the Potato optimizer.
- (Class)competitiveClass {
    SEL sel = NSSelectorFromString(@"competitiveProfile:presenter:");
    for (NSString *name in @[@"TerraPotatoOptimizer", @"TerraCompetitiveDownloader"]) {
        Class cls = NSClassFromString(name);
        if ([cls respondsToSelector:sel]) return cls;
    }
    return nil;
}

#pragma mark Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.entries = [NSMutableDictionary dictionary];
    self.scanGeneration = [NSMutableDictionary dictionary];
    self.visible = @[];
    NSString *type = self.contentType.lowercaseString;
    for (NSInteger k = 0; k < TerraModsKindCount; k++) {
        if ([type isEqualToString:TerraModsKindContentType(k)]) self.kind = k;
    }

    self.title = @"Manage Content";
    [TerraStyle applyToViewController:self];
    [self buildSidebar];
    [self buildMain];
    [self buildBarItems];

    NSLayoutConstraint *sidebarWidth = [self.sidebar.widthAnchor constraintEqualToConstant:240];
    self.wideConstraints = @[
        [self.main.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
    ];
    self.compactConstraints = @[
        [self.main.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    ];
    [NSLayoutConstraint activateConstraints:@[
        sidebarWidth,
        [self.sidebar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.sidebar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.sidebar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.main.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.main.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.main.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(contentChanged:) name:TerraModsContentDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(contentChanged:) name:TerraModsPotatoDidFinishNotification object:nil];
    [nc addObserver:self selector:@selector(contentChanged:) name:DownloadTaskManagerTaskCompletedNotification object:nil];

    [self refreshSelectionUI];
    [self applyFilter];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TerraStyle applyToViewController:self];
    [self reloadAll]; // also covers returning from the browser / optimizer screens
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    BOOL compact = self.view.bounds.size.width < 620;
    if (self.layoutResolved && compact == self.compact) return;
    self.layoutResolved = YES;
    self.compact = compact;
    [NSLayoutConstraint deactivateConstraints:compact ? self.wideConstraints : self.compactConstraints];
    [NSLayoutConstraint activateConstraints:compact ? self.compactConstraints : self.wideConstraints];
    self.sidebar.hidden = compact;
    self.segment.hidden = !compact;
    self.main.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(compact ? 12 : 20, compact ? 16 : 24, 0, compact ? 16 : 24);
    [self buildBarItems];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)contentChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.viewIfLoaded.window) [self reloadAll];
    });
}

#pragma mark Build: sidebar

- (UIButton *)sidebarRow:(NSString *)title symbol:(NSString *)symbol tag:(NSInteger)tag action:(SEL)action count:(UILabel **)countOut {
    UIButton *row = [TerraStyle sidebarRowWithTitle:title symbol:symbol];
    row.tag = tag;
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    if (countOut) {
        UILabel *count = [UILabel new];
        count.translatesAutoresizingMaskIntoConstraints = NO;
        count.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        count.textColor = TerraStyle.dimText;
        count.textAlignment = NSTextAlignmentRight;
        count.userInteractionEnabled = NO;
        [row addSubview:count];
        [NSLayoutConstraint activateConstraints:@[
            [count.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
            [count.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];
        *countOut = count;
    }
    return row;
}

- (void)buildSidebar {
    UIView *sidebar = [UIView new];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.backgroundColor = TerraStyle.surface;
    [self.view addSubview:sidebar];
    self.sidebar = sidebar;

    UIView *hairline = [UIView new];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = TerraStyle.border;
    [sidebar addSubview:hairline];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceVertical = NO;
    [sidebar addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    [scroll addSubview:stack];

    // Installation header
    UILabel *instLabel = [TerraStyle sectionLabel:@"Installation"];
    UIView *grass = [TerraStyle grassBlockOfSize:20];
    UILabel *instName = [UILabel new];
    instName.text = self.profileName.length ? self.profileName : @"Default";
    instName.font = TerraStyle.headlineFont;
    instName.textColor = TerraStyle.text;
    instName.lineBreakMode = NSLineBreakByTruncatingTail;
    UIStackView *inst = [[UIStackView alloc] initWithArrangedSubviews:@[grass, instName]];
    inst.spacing = 10;
    inst.alignment = UIStackViewAlignmentCenter;
    inst.layoutMarginsRelativeArrangement = YES;
    inst.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(4, 16, 4, 12);
    UIStackView *instHeader = [[UIStackView alloc] initWithArrangedSubviews:@[[self paddedLabel:instLabel], inst]];
    instHeader.axis = UILayoutConstraintAxisVertical;
    instHeader.spacing = 6;
    [stack addArrangedSubview:instHeader];
    [stack setCustomSpacing:20 afterView:instHeader];

    // Content sections
    UIView *contentLabel = [self paddedLabel:[TerraStyle sectionLabel:@"Content"]];
    [stack addArrangedSubview:contentLabel];
    [stack setCustomSpacing:6 afterView:contentLabel];
    NSMutableArray *kindRows = [NSMutableArray array], *kindCounts = [NSMutableArray array];
    for (NSInteger k = 0; k < TerraModsKindCount; k++) {
        UILabel *count = nil;
        UIButton *row = [self sidebarRow:TerraModsKindTitle(k) symbol:TerraModsKindSymbol(k) tag:k action:@selector(kindTapped:) count:&count];
        [stack addArrangedSubview:row];
        [kindRows addObject:row];
        [kindCounts addObject:count];
    }
    self.kindRows = kindRows;
    self.kindCounts = kindCounts;
    [stack setCustomSpacing:20 afterView:kindRows.lastObject];

    // Filter
    UIView *showLabel = [self paddedLabel:[TerraStyle sectionLabel:@"Show"]];
    [stack addArrangedSubview:showLabel];
    [stack setCustomSpacing:6 afterView:showLabel];
    NSArray *filterDefs = @[@[@"All", @"square.grid.2x2"], @[@"Enabled", @"checkmark.circle"], @[@"Disabled", @"slash.circle"]];
    NSMutableArray *filterRows = [NSMutableArray array], *filterCounts = [NSMutableArray array];
    for (NSUInteger i = 0; i < filterDefs.count; i++) {
        UILabel *count = nil;
        UIButton *row = [self sidebarRow:filterDefs[i][0] symbol:filterDefs[i][1] tag:i action:@selector(filterTapped:) count:&count];
        [stack addArrangedSubview:row];
        [filterRows addObject:row];
        [filterCounts addObject:count];
    }
    self.filterRows = filterRows;
    self.filterCounts = filterCounts;
    [stack setCustomSpacing:20 afterView:filterRows.lastObject];

    // Sort
    UIView *sortLabel = [self paddedLabel:[TerraStyle sectionLabel:@"Sort by"]];
    [stack addArrangedSubview:sortLabel];
    [stack setCustomSpacing:6 afterView:sortLabel];
    NSArray *sortDefs = @[@[@"Name", @"textformat"], @[@"Recently added", @"clock"], @[@"Size", @"internaldrive"]];
    NSMutableArray *sortRows = [NSMutableArray array];
    for (NSUInteger i = 0; i < sortDefs.count; i++) {
        UIButton *row = [self sidebarRow:sortDefs[i][0] symbol:sortDefs[i][1] tag:i action:@selector(sortTapped:) count:NULL];
        [stack addArrangedSubview:row];
        [sortRows addObject:row];
    }
    self.sortRows = sortRows;

    // Bottom actions
    UIButton *getMore = [TerraStyle blockButtonWithTitle:@"Get More…" symbol:@"plus" primary:YES];
    [getMore addTarget:self action:@selector(getMoreTapped) forControlEvents:UIControlEventTouchUpInside];
    UIButton *potato = [TerraStyle blockButtonWithTitle:@"Potato Optimize" symbol:@"bolt.fill" primary:NO];
    [potato addTarget:self action:@selector(potatoTapped) forControlEvents:UIControlEventTouchUpInside];
    potato.hidden = ![self potatoAvailable];
    self.potatoButton = potato;
    UIButton *competitive = [TerraStyle blockButtonWithTitle:@"Competitive Download" symbol:@"trophy.fill" primary:NO];
    [competitive addTarget:self action:@selector(competitiveTapped) forControlEvents:UIControlEventTouchUpInside];
    competitive.hidden = ![self competitiveClass];
    UIButton *folder = [TerraStyle blockButtonWithTitle:@"Open Folder" symbol:@"folder" primary:NO];
    [folder addTarget:self action:@selector(openFolderTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[getMore, potato, competitive, folder]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisVertical;
    actions.spacing = 8;
    [sidebar addSubview:actions];

    [NSLayoutConstraint activateConstraints:@[
        [hairline.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [hairline.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [hairline.bottomAnchor constraintEqualToAnchor:sidebar.bottomAnchor],
        [hairline.widthAnchor constraintEqualToConstant:1],

        [scroll.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:hairline.leadingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:sidebar.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-12],

        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-12],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-20],

        [actions.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:16],
        [actions.trailingAnchor constraintEqualToAnchor:hairline.leadingAnchor constant:-16],
        [actions.bottomAnchor constraintEqualToAnchor:sidebar.safeAreaLayoutGuide.bottomAnchor constant:-16],
    ]];
}

- (UIView *)paddedLabel:(UILabel *)label {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[label]];
    s.layoutMarginsRelativeArrangement = YES;
    s.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 16, 0, 12);
    return s;
}

#pragma mark Build: main

- (void)buildMain {
    UIView *main = [UIView new];
    main.translatesAutoresizingMaskIntoConstraints = NO;
    main.backgroundColor = TerraStyle.background;
    main.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(20, 24, 0, 24);
    [self.view addSubview:main];
    self.main = main;

    self.titleLabel = [UILabel new];
    self.titleLabel.font = TerraStyle.titleFont;
    self.titleLabel.textColor = TerraStyle.text;
    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.font = TerraStyle.captionFont;
    self.subtitleLabel.textColor = TerraStyle.dimText;
    self.subtitleLabel.numberOfLines = 2;

    NSMutableArray *titles = [NSMutableArray array];
    for (NSInteger k = 0; k < TerraModsKindCount; k++) [titles addObject:TerraModsKindShortTitle(k)];
    self.segment = [[UISegmentedControl alloc] initWithItems:titles];
    self.segment.selectedSegmentTintColor = TerraStyle.green;
    self.segment.backgroundColor = TerraStyle.raised;
    [self.segment setTitleTextAttributes:@{NSForegroundColorAttributeName: TerraStyle.dimText} forState:UIControlStateNormal];
    [self.segment setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor,
                                           NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]}
                                forState:UIControlStateSelected];
    [self.segment addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    self.segment.hidden = YES;

    self.searchField = [TerraStyle searchFieldWithPlaceholder:@"Search installed content"];
    self.searchField.returnKeyType = UIReturnKeyDone;
    self.searchField.delegate = self;
    self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.searchField addTarget:self action:@selector(applyFilter) forControlEvents:UIControlEventEditingChanged];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel, self.segment, self.searchField]];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 4;
    [header setCustomSpacing:14 afterView:self.subtitleLabel];
    [header setCustomSpacing:12 afterView:self.segment];
    [main addSubview:header];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.backgroundColor = UIColor.clearColor;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.rowHeight = UITableViewAutomaticDimension;
    table.estimatedRowHeight = 80;
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    table.dataSource = self;
    table.delegate = self;
    table.contentInset = UIEdgeInsetsMake(6, 0, 20, 0);
    [table registerClass:TerraModsCell.class forCellReuseIdentifier:@"TerraModsCell"];
    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = TerraStyle.dimText;
    [refresh addTarget:self action:@selector(pulledToRefresh) forControlEvents:UIControlEventValueChanged];
    table.refreshControl = refresh;
    [main addSubview:table];
    self.tableView = table;

    [self buildEmptyView];

    UILayoutGuide *m = main.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:m.topAnchor],
        [table.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [table.bottomAnchor constraintEqualToAnchor:main.bottomAnchor],
    ]];
}

- (void)buildEmptyView {
    UIView *empty = [UIView new];
    UIView *grass = [TerraStyle grassBlockOfSize:56];
    self.emptyTitle = [UILabel new];
    self.emptyTitle.font = TerraStyle.headlineFont;
    self.emptyTitle.textColor = TerraStyle.text;
    self.emptyTitle.textAlignment = NSTextAlignmentCenter;
    self.emptyMessage = [UILabel new];
    self.emptyMessage.font = TerraStyle.bodyFont;
    self.emptyMessage.textColor = TerraStyle.dimText;
    self.emptyMessage.textAlignment = NSTextAlignmentCenter;
    self.emptyMessage.numberOfLines = 0;
    self.emptyButton = [TerraStyle blockButtonWithTitle:@"Get More…" symbol:@"plus" primary:YES];
    [self.emptyButton addTarget:self action:@selector(getMoreTapped) forControlEvents:UIControlEventTouchUpInside];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = TerraStyle.dimText;
    self.spinner.hidesWhenStopped = YES;

    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, grass, self.emptyTitle, self.emptyMessage, self.emptyButton]];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    s.axis = UILayoutConstraintAxisVertical;
    s.alignment = UIStackViewAlignmentCenter;
    s.spacing = 10;
    [s setCustomSpacing:18 afterView:grass];
    [s setCustomSpacing:18 afterView:self.emptyMessage];
    [empty addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor],
        [s.centerYAnchor constraintEqualToAnchor:empty.centerYAnchor constant:-40],
        [s.widthAnchor constraintLessThanOrEqualToConstant:380],
        [s.leadingAnchor constraintGreaterThanOrEqualToAnchor:empty.leadingAnchor constant:16],
    ]];
    self.emptyView = empty;
}

- (void)buildBarItems {
    if (!self.moreItem) {
        self.moreItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:nil];
        self.moreItem.accessibilityLabel = @"More";
        self.addItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"]
                                                        style:UIBarButtonItemStylePlain target:self action:@selector(getMoreTapped)];
        self.addItem.accessibilityLabel = @"Get More";
    }
    self.navigationItem.rightBarButtonItems = self.compact ? @[self.moreItem, self.addItem] : @[self.moreItem];
    [self rebuildMenu];
}

- (void)rebuildMenu {
    if (!self.moreItem) return;
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    if (self.compact) {
        NSArray *filterNames = @[@"All", @"Enabled", @"Disabled"];
        NSMutableArray *filters = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            UIAction *a = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ (%ld)", filterNames[i], (long)[self countForFilter:i]]
                                              image:nil identifier:nil handler:^(UIAction *action) {
                weakSelf.filter = i; [weakSelf refreshSelectionUI]; [weakSelf applyFilter];
            }];
            a.state = (self.filter == i) ? UIMenuElementStateOn : UIMenuElementStateOff;
            [filters addObject:a];
        }
        [items addObject:[UIMenu menuWithTitle:@"Show" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:filters]];
        NSArray *sortNames = @[@"Name", @"Recently added", @"Size"];
        NSMutableArray *sorts = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            UIAction *a = [UIAction actionWithTitle:sortNames[i] image:nil identifier:nil handler:^(UIAction *action) {
                weakSelf.sort = i; [weakSelf refreshSelectionUI]; [weakSelf applyFilter];
            }];
            a.state = (self.sort == i) ? UIMenuElementStateOn : UIMenuElementStateOff;
            [sorts addObject:a];
        }
        [items addObject:[UIMenu menuWithTitle:@"Sort by" image:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                    identifier:nil options:0 children:sorts]];
    }
    NSMutableArray *actions = [NSMutableArray array];
    if (self.compact && [self potatoAvailable]) {
        [actions addObject:[UIAction actionWithTitle:@"Potato Optimize" image:[UIImage systemImageNamed:@"bolt.fill"]
                                          identifier:nil handler:^(UIAction *a) { [weakSelf potatoTapped]; }]];
    }
    if (self.compact && [self competitiveClass]) {
        [actions addObject:[UIAction actionWithTitle:@"Competitive Download" image:[UIImage systemImageNamed:@"trophy.fill"]
                                          identifier:nil handler:^(UIAction *a) { [weakSelf competitiveTapped]; }]];
    }
    [actions addObject:[UIAction actionWithTitle:@"Import Files…" image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                      identifier:nil handler:^(UIAction *a) { [weakSelf importTapped]; }]];
    [actions addObject:[UIAction actionWithTitle:@"Open Folder" image:[UIImage systemImageNamed:@"folder"]
                                      identifier:nil handler:^(UIAction *a) { [weakSelf openFolderTapped]; }]];
    [actions addObject:[UIAction actionWithTitle:@"Refresh" image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                      identifier:nil handler:^(UIAction *a) { [weakSelf reloadAll]; }]];
    [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:actions]];
    self.moreItem.menu = [UIMenu menuWithTitle:@"" children:items];
}

#pragma mark Data

- (NSArray<TerraModsEntry *> *)currentEntries {
    return self.entries[@(self.kind)] ?: @[];
}

- (NSInteger)countForFilter:(TerraModsFilter)filter {
    NSInteger n = 0;
    for (TerraModsEntry *e in self.currentEntries) {
        if (filter == TerraModsFilterAll || (filter == TerraModsFilterEnabled) == !e.disabled) n++;
    }
    return n;
}

- (void)reloadAll {
    for (NSInteger k = 0; k < TerraModsKindCount; k++) [self scanKind:k];
}

- (void)scanKind:(TerraModsKind)kind {
    NSInteger gen = [self.scanGeneration[@(kind)] integerValue] + 1;
    self.scanGeneration[@(kind)] = @(gen);
    if (kind == self.kind && !self.entries[@(kind)]) [self applyFilter]; // shows the spinner
    __weak typeof(self) weakSelf = self;
    TerraModsScan(kind, self.profile, ^(NSArray *items) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSMutableArray *wrapped = [NSMutableArray arrayWithCapacity:items.count];
            for (id item in items) {
                TerraModsEntry *e = [TerraModsEntry new];
                e.kind = kind;
                e.item = item;
                [e refreshFileAttributes];
                [wrapped addObject:e];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || [self.scanGeneration[@(kind)] integerValue] != gen) return;
                self.entries[@(kind)] = wrapped;
                [self updateCounts];
                if (kind == self.kind) {
                    [self.tableView.refreshControl endRefreshing];
                    [self applyFilter];
                }
            });
        });
    });
}

- (void)applyFilter {
    if (!self.tableView) return;
    NSString *query = [self.searchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
    NSMutableArray<TerraModsEntry *> *result = [NSMutableArray array];
    for (TerraModsEntry *e in self.currentEntries) {
        if (self.filter == TerraModsFilterEnabled && e.disabled) continue;
        if (self.filter == TerraModsFilterDisabled && !e.disabled) continue;
        if (query.length) {
            NSString *hay = [NSString stringWithFormat:@"%@\n%@\n%@", e.title, e.fileName, e.author ?: @""].lowercaseString;
            if (![hay containsString:query]) continue;
        }
        [result addObject:e];
    }
    TerraModsSort sort = self.sort;
    [result sortUsingComparator:^NSComparisonResult(TerraModsEntry *a, TerraModsEntry *b) {
        if (sort == TerraModsSortRecent) {
            NSComparisonResult r = [b.addedDate compare:a.addedDate];
            if (r != NSOrderedSame) return r;
        } else if (sort == TerraModsSortSize) {
            if (a.fileSize != b.fileSize) return a.fileSize > b.fileSize ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    self.visible = result;
    [self.tableView reloadData];
    [self updateHeaderAndEmptyState];
}

- (void)updateCounts {
    for (NSInteger k = 0; k < TerraModsKindCount; k++) {
        NSArray *list = self.entries[@(k)];
        self.kindCounts[k].text = list ? [NSString stringWithFormat:@"%lu", (unsigned long)list.count] : @"";
    }
    for (NSInteger f = 0; f < 3; f++) {
        self.filterCounts[f].text = self.entries[@(self.kind)] ? [NSString stringWithFormat:@"%ld", (long)[self countForFilter:f]] : @"";
    }
    [self rebuildMenu];
}

- (void)updateHeaderAndEmptyState {
    BOOL loaded = self.entries[@(self.kind)] != nil;
    NSArray *all = self.currentEntries;
    NSString *plural = TerraModsKindTitle(self.kind).lowercaseString;
    self.titleLabel.text = TerraModsKindTitle(self.kind);
    if (!loaded) {
        self.subtitleLabel.text = @"Scanning…";
    } else {
        NSInteger disabled = [self countForFilter:TerraModsFilterDisabled];
        NSMutableString *s = [NSMutableString stringWithFormat:@"%lu installed", (unsigned long)all.count];
        if (disabled) [s appendFormat:@"  ·  %ld disabled", (long)disabled];
        if (self.kind == TerraModsKindDataPack) [s appendString:@"  ·  stored in the installation's datapacks folder"];
        self.subtitleLabel.text = s;
    }

    if (self.visible.count) {
        self.tableView.backgroundView = nil;
        [self.spinner stopAnimating];
        return;
    }
    self.tableView.backgroundView = self.emptyView;
    BOOL showContent = loaded;
    if (!loaded) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    self.emptyTitle.hidden = !showContent;
    self.emptyMessage.hidden = !showContent;
    self.emptyButton.hidden = !showContent;
    for (UIView *v in self.emptyTitle.superview.subviews) {
        if (v != self.spinner && v != self.emptyTitle && v != self.emptyMessage && v != self.emptyButton) v.hidden = !showContent;
    }
    if (!showContent) return;
    if (all.count == 0) {
        self.emptyTitle.text = [NSString stringWithFormat:@"No %@ yet", plural];
        self.emptyMessage.text = [NSString stringWithFormat:@"Browse Modrinth and CurseForge to add %@ to this installation.", plural];
        self.emptyButton.hidden = NO;
    } else {
        self.emptyTitle.text = @"Nothing matches";
        self.emptyMessage.text = self.searchField.text.length ? @"Try a different search, or clear the filter."
                                                              : @"No items match this filter.";
        self.emptyButton.hidden = YES;
    }
}

- (void)refreshSelectionUI {
    for (UIButton *b in self.kindRows) [TerraStyle setSidebarRow:b selected:b.tag == self.kind];
    for (UIButton *b in self.filterRows) [TerraStyle setSidebarRow:b selected:b.tag == self.filter];
    for (UIButton *b in self.sortRows) [TerraStyle setSidebarRow:b selected:b.tag == self.sort];
    for (NSInteger k = 0; k < TerraModsKindCount; k++) {
        self.kindCounts[k].textColor = (k == self.kind) ? TerraStyle.text : TerraStyle.dimText;
    }
    for (NSInteger f = 0; f < 3; f++) {
        self.filterCounts[f].textColor = (f == self.filter) ? TerraStyle.text : TerraStyle.dimText;
    }
    self.segment.selectedSegmentIndex = self.kind;
    self.searchField.placeholder = [NSString stringWithFormat:@"Search %@", TerraModsKindTitle(self.kind).lowercaseString];
    self.searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.searchField.placeholder
        attributes:@{NSForegroundColorAttributeName: TerraStyle.dimText}];
    [self updateCounts];
}

#pragma mark Sidebar actions

- (void)selectKind:(TerraModsKind)kind {
    if (kind == self.kind) return;
    self.kind = kind;
    self.contentType = TerraModsKindContentType(kind);
    [self refreshSelectionUI];
    [self applyFilter];
    if (self.visible.count) [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:NO];
}

- (void)kindTapped:(UIButton *)sender { [self selectKind:sender.tag]; }
- (void)segmentChanged { [self selectKind:self.segment.selectedSegmentIndex]; }

- (void)filterTapped:(UIButton *)sender {
    self.filter = sender.tag;
    [self refreshSelectionUI];
    [self applyFilter];
}

- (void)sortTapped:(UIButton *)sender {
    self.sort = sender.tag;
    [self refreshSelectionUI];
    [self applyFilter];
}

- (void)pulledToRefresh {
    [self reloadAll];
}

- (void)getMoreTapped {
    UIViewController *vc = nil;
    Class browse = NSClassFromString(@"TerraBrowseViewController");
    if (browse && [browse isSubclassOfClass:UIViewController.class]) {
        vc = [browse new];
        if ([vc respondsToSelector:NSSelectorFromString(@"setProfileName:")]) [vc setValue:self.profileName forKey:@"profileName"];
        if ([vc respondsToSelector:NSSelectorFromString(@"setContentType:")]) [vc setValue:TerraModsKindContentType(self.kind) forKey:@"contentType"];
    } else {
        DownloadViewController *dl = [DownloadViewController new];
        dl.initialTabIndex = self.kind + 1; // 1 mods, 2 shaders, 3 resource packs, 4 data packs
        dl.targetProfileName = self.profileName;
        vc = dl;
    }
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    }
}

- (void)potatoTapped {
    Class cls = NSClassFromString(@"TerraPotatoOptimizer");
    SEL sel = NSSelectorFromString(@"optimizeProfile:presenter:");
    if (![cls respondsToSelector:sel]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [cls performSelector:sel withObject:self.profile withObject:self];
#pragma clang diagnostic pop
}

- (void)competitiveTapped {
    Class cls = [self competitiveClass];
    if (!cls) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [cls performSelector:NSSelectorFromString(@"competitiveProfile:presenter:") withObject:self.profile withObject:self];
#pragma clang diagnostic pop
}

- (void)openFolderTapped {
    NSError *error = nil;
    NSString *folder = TerraModsFolder(self.kind, self.profile, &error);
    if (!folder) {
        [self showMessage:@"Couldn't open folder" detail:error.localizedDescription ?: @"The folder could not be created."];
        return;
    }
    NSString *encoded = [folder stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: folder;
    NSURL *url = [NSURL URLWithString:[@"shareddocuments://" stringByAppendingString:encoded]];
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) [weakSelf showMessage:@"Open in Files" detail:[NSString stringWithFormat:@"Find this folder in the Files app:\n%@", folder]];
    }];
}

- (void)importTapped {
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *jar = [UTType typeWithFilenameExtension:@"jar"];
    if (self.kind == TerraModsKindMod && jar) [types addObject:jar];
    [types addObject:UTTypeZIP];
    [types addObject:UTTypeData];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSError *error = nil;
    NSString *folder = TerraModsFolder(self.kind, self.profile, &error);
    if (!folder) {
        [self showMessage:@"Import failed" detail:error.localizedDescription ?: @"The folder could not be created."];
        return;
    }
    NSString *ext = self.kind == TerraModsKindMod ? @"jar" : @"zip";
    NSMutableArray *failed = [NSMutableArray array];
    NSInteger imported = 0;
    for (NSURL *url in urls) {
        NSString *name = url.lastPathComponent;
        if (![name.pathExtension.lowercaseString isEqualToString:ext]) {
            [failed addObject:[NSString stringWithFormat:@"%@ (not a .%@ file)", name, ext]];
            continue;
        }
        BOOL scoped = [url startAccessingSecurityScopedResource];
        NSString *dest = [folder stringByAppendingPathComponent:name];
        [NSFileManager.defaultManager removeItemAtPath:dest error:nil];
        NSError *copyError = nil;
        if ([NSFileManager.defaultManager copyItemAtPath:url.path toPath:dest error:&copyError]) {
            imported++;
        } else {
            [failed addObject:[NSString stringWithFormat:@"%@ (%@)", name, copyError.localizedDescription]];
        }
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
    [self scanKind:self.kind];
    if (failed.count) {
        [self showMessage:[NSString stringWithFormat:@"Imported %ld, %lu failed", (long)imported, (unsigned long)failed.count]
                   detail:[failed componentsJoinedByString:@"\n"]];
    }
}

#pragma mark Item actions

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [[self topPresenter] presentViewController:a animated:YES completion:nil];
}

/// Toggles via the owning service; returns success. Keeps counts/list in sync.
- (BOOL)toggleEntry:(TerraModsEntry *)entry {
    NSError *error = nil;
    BOOL ok = TerraModsToggle(entry, &error);
    if (!ok) {
        [self showMessage:@"Couldn't change state" detail:error.localizedDescription ?: @"Unknown error."];
        return NO;
    }
    [self updateCounts];
    if (self.filter == TerraModsFilterAll) {
        NSUInteger idx = [self.visible indexOfObject:entry];
        if (idx != NSNotFound) {
            TerraModsCell *cell = (TerraModsCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]];
            if ([cell isKindOfClass:TerraModsCell.class]) {
                [UIView animateWithDuration:0.2 animations:^{ [cell configureWithEntry:entry]; }];
            }
        }
        [self updateHeaderAndEmptyState];
    } else {
        [self applyFilter];
    }
    return YES;
}

- (void)confirmDeleteEntry:(TerraModsEntry *)entry completion:(void (^)(BOOL deleted))completion {
    NSString *title = [NSString stringWithFormat:@"Delete “%@”?", entry.title];
    NSString *msg = [NSString stringWithFormat:@"%@ will be permanently removed from this installation.", entry.fileName];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        if (completion) completion(NO);
    }]];
    __weak typeof(self) weakSelf = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        BOOL ok = [weakSelf deleteEntry:entry];
        if (completion) completion(ok);
    }]];
    [[self topPresenter] presentViewController:a animated:YES completion:nil];
}

/// Top-most controller to present alerts from (works while the detail screen or a picker is up).
- (UIViewController *)topPresenter {
    UIViewController *host = self.navigationController.topViewController ?: self;
    while (host.presentedViewController && !host.presentedViewController.isBeingDismissed) host = host.presentedViewController;
    return host;
}

- (BOOL)deleteEntry:(TerraModsEntry *)entry {
    NSError *error = nil;
    if (!TerraModsDelete(entry, &error)) {
        [self showMessage:@"Couldn't delete" detail:error.localizedDescription ?: @"Unknown error."];
        return NO;
    }
    NSMutableArray *list = [self.entries[@(entry.kind)] mutableCopy];
    [list removeObject:entry];
    self.entries[@(entry.kind)] = list;
    NSUInteger idx = [self.visible indexOfObject:entry];
    [self updateCounts];
    if (entry.kind == self.kind && idx != NSNotFound) {
        NSMutableArray *vis = [self.visible mutableCopy];
        [vis removeObjectAtIndex:idx];
        self.visible = vis;
        [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationFade];
        [self updateHeaderAndEmptyState];
    }
    return YES;
}

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.visible.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraModsCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TerraModsCell" forIndexPath:indexPath];
    TerraModsEntry *entry = self.visible[indexPath.row];
    [cell configureWithEntry:entry];
    __weak typeof(self) weakSelf = self;
    __weak TerraModsCell *weakCell = cell;
    cell.onToggle = ^(BOOL enabled) {
        if (enabled == !entry.disabled) return;
        if (![weakSelf toggleEntry:entry]) [weakCell.toggle setOn:!entry.disabled animated:YES];
    };
    cell.onDelete = ^{ [weakSelf confirmDeleteEntry:entry completion:nil]; };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchField resignFirstResponder];
    TerraModsEntry *entry = self.visible[indexPath.row];
    TerraModsDetailViewController *detail = [TerraModsDetailViewController new];
    detail.entry = entry;
    __weak typeof(self) weakSelf = self;
    detail.onToggle = ^BOOL(TerraModsEntry *e) { return [weakSelf toggleEntry:e]; };
    detail.onDelete = ^(TerraModsEntry *e, void (^deleted)(void)) {
        [weakSelf confirmDeleteEntry:e completion:^(BOOL ok) { if (ok && deleted) deleted(); }];
    };
    if (self.navigationController) {
        [self.navigationController pushViewController:detail animated:YES];
    } else {
        [self presentViewController:[[UINavigationController alloc] initWithRootViewController:detail] animated:YES completion:nil];
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraModsEntry *entry = self.visible[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Delete"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^done)(BOOL)) {
        done(YES);
        [weakSelf confirmDeleteEntry:entry completion:nil];
    }];
    del.backgroundColor = TerraStyle.danger;
    del.image = [UIImage systemImageNamed:@"trash"];
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[del]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraModsEntry *entry = self.visible[indexPath.row];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *toggle = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:entry.disabled ? @"Enable" : @"Disable"
        handler:^(UIContextualAction *action, UIView *sourceView, void (^done)(BOOL)) {
        done([weakSelf toggleEntry:entry]);
    }];
    toggle.backgroundColor = entry.disabled ? TerraStyle.green : [UIColor colorWithWhite:0.35 alpha:1];
    toggle.image = [UIImage systemImageNamed:entry.disabled ? @"checkmark" : @"pause.fill"];
    return [UISwipeActionsConfiguration configurationWithActions:@[toggle]];
}

#pragma mark UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
