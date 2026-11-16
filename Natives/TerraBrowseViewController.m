//
//  TerraBrowseViewController.m
//  ★ [TERRA-BROWSE] see TerraBrowseViewController.h
//

#import "TerraBrowseViewController.h"
#import "TerraBrowseAPI.h"
#import "TerraStyle.h"
#import "TerraVersionInstaller.h"
#import "TerraPotatoOptimizer.h"
#import "ModpackImportService.h"

NSString *const TerraBrowseDidInstallNotification = @"TerraBrowseDidInstallNotification";

static NSArray<NSString *> *TBVTypes(void) { return @[@"mod", @"modpack", @"shader", @"resourcepack", @"datapack"]; }
static NSArray<NSString *> *TBVTypeTitles(void) { return @[@"Mods", @"Modpacks", @"Shaders", @"Resource Packs", @"Data Packs"]; }
static NSArray<NSString *> *TBVTypeSymbols(void) {
    return @[@"puzzlepiece.extension.fill", @"shippingbox.fill", @"sun.max.fill", @"photo.on.rectangle.angled", @"curlybraces"];
}
static NSString *TBVTypeNoun(NSString *type, BOOL plural) {
    NSUInteger i = [TBVTypes() indexOfObject:type ?: @"mod"];
    NSString *t = TBVTypeTitles()[i == NSNotFound ? 0 : i].lowercaseString;
    return plural ? t : [t substringToIndex:t.length - 1];
}
static UIColor *TBVCurseForgeOrange(void) { return [UIColor colorWithRed:0xF1/255.0 green:0x64/255.0 blue:0x36/255.0 alpha:1]; }
static BOOL TBVUsesLoader(NSString *type) { return [type isEqualToString:@"mod"] || [type isEqualToString:@"modpack"]; }

#pragma mark - Icons

static NSCache<NSString *, UIImage *> *TBVIconCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 400; });
    return cache;
}

static void TBVLoadIcon(NSString *url, void (^completion)(UIImage *image)) {
    if (url.length == 0) return;
    UIImage *cached = [TBVIconCache() objectForKey:url];
    if (cached) {
        completion(cached);
        return;
    }
    NSURL *u = [NSURL URLWithString:url];
    if (!u) return;
    [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) return;
        UIImage *thumb = [img imageByPreparingThumbnailOfSize:CGSizeMake(128, 128)] ?: img;
        [TBVIconCache() setObject:thumb forKey:url];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(thumb); });
    }] resume];
}

static UIImage *TBVSymbol(NSString *name, CGFloat size, UIColor *color) {
    UIImage *img = [UIImage systemImageNamed:name withConfiguration:
                    [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]];
    return color ? [img imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal] : img;
}

static NSAttributedString *TBVStats(NSArray<NSArray *> *parts) {
    // parts: @[symbol, text]
    NSMutableAttributedString *s = [NSMutableAttributedString new];
    NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium],
                            NSForegroundColorAttributeName: TerraStyle.dimText};
    for (NSArray *part in parts) {
        if (s.length) [s appendAttributedString:[[NSAttributedString alloc] initWithString:@"     " attributes:attrs]];
        NSTextAttachment *a = [NSTextAttachment new];
        a.image = TBVSymbol(part[0], 11, TerraStyle.dimText);
        [s appendAttributedString:[NSAttributedString attributedStringWithAttachment:a]];
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:part[1]] attributes:attrs]];
    }
    return s;
}

static UIView *TBVIconPlaceholder(UIImageView *iv, NSString *contentType) {
    NSUInteger i = [TBVTypes() indexOfObject:contentType ?: @"mod"];
    iv.image = TBVSymbol(TBVTypeSymbols()[i == NSNotFound ? 0 : i], 22, TerraStyle.dimText);
    iv.contentMode = UIViewContentModeCenter;
    return iv;
}

static UIButton *TBVPillButton(NSString *title, NSString *symbol) {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = TerraStyle.raised;
    c.baseForegroundColor = TerraStyle.text;
    c.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    c.contentInsets = NSDirectionalEdgeInsetsMake(8, 12, 8, 12);
    c.imagePadding = 7;
    if (symbol) c.image = TBVSymbol(symbol, 12, nil);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title ?: @""
                         attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold]}];
    c.titleLineBreakMode = NSLineBreakByTruncatingTail;
    return [UIButton buttonWithConfiguration:c primaryAction:nil];
}

#pragma mark - Result cell

@interface TerraBrowseResultCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, copy) NSString *iconURL;
@end

@implementation TerraBrowseResultCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [TerraStyle cardView];
        _card.layer.cornerRadius = 10;
        _iconView = [UIImageView new];
        _iconView.backgroundColor = TerraStyle.raised;
        _iconView.layer.cornerRadius = 12;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.clipsToBounds = YES;
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _titleLabel.textColor = TerraStyle.text;
        [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        _authorLabel = [UILabel new];
        _authorLabel.font = [UIFont systemFontOfSize:13];
        _authorLabel.textColor = TerraStyle.dimText;
        [_authorLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 10 forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _authorLabel, spacer]];
        titleRow.spacing = 6;
        titleRow.alignment = UIStackViewAlignmentFirstBaseline;
        _summaryLabel = [UILabel new];
        _summaryLabel.font = [UIFont systemFontOfSize:14];
        _summaryLabel.textColor = [UIColor colorWithWhite:0.86 alpha:1];
        _summaryLabel.numberOfLines = 2;
        _chipsStack = [UIStackView new];
        _chipsStack.spacing = 6;
        UIStackView *chipsRow = [[UIStackView alloc] initWithArrangedSubviews:@[_chipsStack, [UIView new]]];
        _statsLabel = [UILabel new];
        _statsLabel.numberOfLines = 1;
        _statsLabel.adjustsFontSizeToFitWidth = YES;
        _statsLabel.minimumScaleFactor = 0.8;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, _summaryLabel, chipsRow, _statsLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 6;
        [text setCustomSpacing:8 afterView:_summaryLabel];
        for (UIView *v in @[_card, _iconView, text]) v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_card];
        [_card addSubview:_iconView];
        [_card addSubview:text];
        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_iconView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14],
            [_iconView.topAnchor constraintEqualToAnchor:_card.topAnchor constant:14],
            [_iconView.widthAnchor constraintEqualToConstant:64],
            [_iconView.heightAnchor constraintEqualToConstant:64],
            [_card.bottomAnchor constraintGreaterThanOrEqualToAnchor:_iconView.bottomAnchor constant:14],
            [text.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:14],
            [text.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
            [text.topAnchor constraintEqualToAnchor:_card.topAnchor constant:12],
            [_card.bottomAnchor constraintGreaterThanOrEqualToAnchor:text.bottomAnchor constant:12],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.card.backgroundColor = highlighted ? TerraStyle.raised : TerraStyle.surface;
}

- (void)resetSkeleton {
    [self.card.layer removeAllAnimations];
    self.card.alpha = 1;
    for (UILabel *l in @[self.titleLabel, self.authorLabel, self.summaryLabel, self.statsLabel]) {
        l.backgroundColor = UIColor.clearColor;
        l.layer.cornerRadius = 0;
    }
}

- (void)configureSkeleton {
    [self resetSkeleton];
    self.iconURL = nil;
    self.iconView.image = nil;
    for (UIView *v in self.chipsStack.arrangedSubviews) [v removeFromSuperview];
    self.titleLabel.text = @"                              ";
    self.authorLabel.text = @"            ";
    self.summaryLabel.text = @"                                                                                    ";
    self.statsLabel.attributedText = nil;
    self.statsLabel.text = @"                                        ";
    for (UILabel *l in @[self.titleLabel, self.authorLabel, self.summaryLabel, self.statsLabel]) {
        l.backgroundColor = TerraStyle.raised;
        l.layer.cornerRadius = 4;
        l.layer.masksToBounds = YES;
    }
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = @1.0;
    pulse.toValue = @0.45;
    pulse.duration = 0.8;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [self.card.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)configureWithProject:(TerraBrowseProject *)p {
    [self resetSkeleton];
    self.titleLabel.text = p.title;
    self.authorLabel.text = p.author.length ? [@"by " stringByAppendingString:p.author] : @"";
    self.summaryLabel.text = p.summary;
    for (UIView *v in self.chipsStack.arrangedSubviews) [v removeFromSuperview];
    NSUInteger n = 0;
    for (NSString *c in p.categories) {
        if (n++ >= 3) break;
        [self.chipsStack addArrangedSubview:[TerraStyle chipWithText:c color:TerraStyle.greenBright]];
    }
    for (NSString *l in [p.loaders subarrayWithRange:NSMakeRange(0, MIN(p.loaders.count, 3))]) {
        [self.chipsStack addArrangedSubview:[TerraStyle chipWithText:l color:TerraStyle.dimText]];
    }
    self.chipsStack.superview.hidden = self.chipsStack.arrangedSubviews.count == 0;
    NSMutableArray *stats = [NSMutableArray arrayWithObject:@[@"arrow.down.circle", [TerraBrowseAPI compactNumber:p.downloads]]];
    [stats addObject:@[p.source == TerraBrowseSourceCurseForge ? @"hand.thumbsup" : @"heart", [TerraBrowseAPI compactNumber:p.follows]]];
    if (p.updated) [stats addObject:@[@"clock.arrow.circlepath", [@"Updated " stringByAppendingString:[TerraBrowseAPI relativeDate:p.updated]]]];
    self.statsLabel.attributedText = TBVStats(stats);
    self.iconURL = p.iconURL;
    TBVIconPlaceholder(self.iconView, p.contentType);
    NSString *url = p.iconURL;
    __weak typeof(self) weakSelf = self;
    TBVLoadIcon(url, ^(UIImage *image) {
        if (![weakSelf.iconURL isEqualToString:url]) return;
        weakSelf.iconView.contentMode = UIViewContentModeScaleAspectFill;
        weakSelf.iconView.image = image;
    });
}

@end

#pragma mark - Version cell

@interface TerraBrowseVersionCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIStackView *chipsStack;
@property (nonatomic, strong) UIButton *installButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) void (^onInstall)(void);
@end

@implementation TerraBrowseVersionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _card = [TerraStyle cardView];
        _card.layer.cornerRadius = 8;
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _nameLabel.textColor = TerraStyle.text;
        _nameLabel.numberOfLines = 2;
        _chipsStack = [UIStackView new];
        _chipsStack.spacing = 6;
        UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[_chipsStack, _nameLabel]];
        nameRow.spacing = 8;
        nameRow.alignment = UIStackViewAlignmentCenter;
        _metaLabel = [UILabel new];
        _metaLabel.font = TerraStyle.captionFont;
        _metaLabel.textColor = TerraStyle.dimText;
        _metaLabel.numberOfLines = 2;
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.progressTintColor = TerraStyle.greenBright;
        _progressView.trackTintColor = TerraStyle.raised;
        _statusLabel = [UILabel new];
        _statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _statusLabel.textColor = TerraStyle.greenBright;
        _statusLabel.numberOfLines = 2;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, _metaLabel, _progressView, _statusLabel]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 4;
        _installButton = [TerraStyle blockButtonWithTitle:@"Install" symbol:@"arrow.down" primary:YES];
        [_installButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_installButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_installButton addTarget:self action:@selector(installTapped) forControlEvents:UIControlEventTouchUpInside];
        for (UIView *v in @[_card, text, _installButton]) v.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_card];
        [_card addSubview:text];
        [_card addSubview:_installButton];
        [NSLayoutConstraint activateConstraints:@[
            [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [text.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:14],
            [text.topAnchor constraintEqualToAnchor:_card.topAnchor constant:11],
            [text.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-11],
            [text.trailingAnchor constraintEqualToAnchor:_installButton.leadingAnchor constant:-12],
            [_installButton.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-12],
            [_installButton.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        ]];
    }
    return self;
}

- (void)installTapped {
    if (self.onInstall) self.onInstall();
}

- (void)configureWithFile:(TerraBrowseFile *)f state:(NSDictionary *)state installedOnDisk:(BOOL)onDisk {
    self.nameLabel.text = f.name.length ? f.name : f.versionNumber;
    for (UIView *v in self.chipsStack.arrangedSubviews) [v removeFromSuperview];
    UIColor *typeColor = [f.releaseType isEqualToString:@"release"] ? TerraStyle.greenBright
        : ([f.releaseType isEqualToString:@"beta"] ? TerraStyle.warning : TerraStyle.danger);
    [self.chipsStack addArrangedSubview:[TerraStyle chipWithText:f.releaseType.capitalizedString color:typeColor]];
    NSMutableArray *meta = [NSMutableArray array];
    if (f.versionNumber.length && ![f.versionNumber isEqualToString:f.name]) [meta addObject:f.versionNumber];
    if (f.gameVersions.count) {
        NSArray *gv = f.gameVersions.count > 4
            ? [[f.gameVersions subarrayWithRange:NSMakeRange(f.gameVersions.count - 3, 3)] arrayByAddingObject:@"…"]
            : f.gameVersions;
        [meta addObject:[gv componentsJoinedByString:@", "]];
    }
    NSMutableArray *loaders = [NSMutableArray array];
    for (NSString *l in f.loaders) {
        if (![l isEqualToString:@"minecraft"]) [loaders addObject:[TerraBrowseAPI displayNameForLoader:l]];
    }
    if (loaders.count) [meta addObject:[loaders componentsJoinedByString:@", "]];
    if (f.published) [meta addObject:[TerraBrowseAPI relativeDate:f.published]];
    if (f.size > 0) [meta addObject:[NSByteCountFormatter stringFromByteCount:f.size countStyle:NSByteCountFormatterCountStyleFile]];
    self.metaLabel.text = [meta componentsJoinedByString:@"  ·  "];

    NSInteger phase = [state[@"phase"] integerValue];   // 0 idle, 1 working, 2 done, 3 failed
    self.progressView.hidden = phase != 1;
    self.progressView.progress = [state[@"progress"] floatValue];
    NSString *status = state[@"status"];
    self.statusLabel.hidden = status.length == 0 && !onDisk;
    self.statusLabel.textColor = phase == 3 ? TerraStyle.danger : (phase == 1 ? TerraStyle.dimText : TerraStyle.greenBright);
    self.statusLabel.text = status.length ? status : (onDisk ? @"Installed" : nil);
    self.installButton.enabled = phase != 1;
    NSString *title = phase == 1 ? @"Installing" : ((phase == 2 || onDisk) ? @"Reinstall" : (phase == 3 ? @"Retry" : @"Install"));
    [self.installButton setTitle:title forState:UIControlStateNormal];
}

@end

#pragma mark - Filter sheet (narrow widths)

@interface TerraBrowseFilterSheet : UIViewController
@property (nonatomic, strong) UIView *hostedView;
@property (nonatomic, copy) void (^onClose)(void);
@end

@implementation TerraBrowseFilterSheet
- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];
    self.title = @"Filters";
    __weak typeof(self) weakSelf = self;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }]];
    self.hostedView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hostedView];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.hostedView.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.hostedView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.hostedView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [self.hostedView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
    ]];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.onClose) self.onClose();
    self.onClose = nil;
}
@end

#pragma mark - Project page

@interface TerraBrowseProjectViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TerraBrowseProject *project;
@property (nonatomic, strong, nullable) TerraBrowseTarget *target;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic, strong) UILabel *versionsTitle;
@property (nonatomic, strong) UIButton *allVersionsButton;
@property (nonatomic, strong) NSArray<TerraBrowseFile *> *files;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *states;
@property (nonatomic, assign) BOOL showAll;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) CGFloat lastHeaderWidth;
@end

@implementation TerraBrowseProjectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];
    self.title = self.project.title;
    self.states = [NSMutableDictionary dictionary];
    __weak typeof(self) weakSelf = self;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }]];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 86;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 24, 0);
    [self.tableView registerClass:TerraBrowseVersionCell.class forCellReuseIdentifier:@"v"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];
    [self buildHeader];
    [self loadDescription];
    [self loadVersions];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width > 0 && width != self.lastHeaderWidth) {
        self.lastHeaderWidth = width;
        [self sizeHeader];
    }
}

- (void)sizeHeader {
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;
    CGSize size = [self.headerView systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                                 withHorizontalFittingPriority:UILayoutPriorityRequired
                                       verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.headerView.frame = CGRectMake(0, 0, width, size.height);
    self.tableView.tableHeaderView = self.headerView;
}

- (BOOL)usesInstallationFilter {
    return ![self.project.contentType isEqualToString:@"modpack"] && self.target != nil;
}

- (NSString *)filterDescription {
    if (!self.target) return @"";
    if ([self.project.contentType isEqualToString:@"mod"] && self.target.hasModLoader) {
        return [NSString stringWithFormat:@"%@ %@", self.target.loaderDisplayName, self.target.gameVersion];
    }
    return [@"Minecraft " stringByAppendingString:self.target.gameVersion];
}

- (void)buildHeader {
    TerraBrowseProject *p = self.project;
    UIView *header = [UIView new];
    UIImageView *icon = [UIImageView new];
    icon.backgroundColor = TerraStyle.raised;
    icon.layer.cornerRadius = 18;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    TBVIconPlaceholder(icon, p.contentType);
    TBVLoadIcon(p.iconURL, ^(UIImage *image) {
        icon.contentMode = UIViewContentModeScaleAspectFill;
        icon.image = image;
    });
    UILabel *title = [UILabel new];
    title.text = p.title;
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    title.textColor = TerraStyle.text;
    title.numberOfLines = 2;
    UILabel *author = [UILabel new];
    author.text = p.author.length ? [@"by " stringByAppendingString:p.author] : @"";
    author.font = [UIFont systemFontOfSize:15];
    author.textColor = TerraStyle.dimText;
    UILabel *stats = [UILabel new];
    NSMutableArray *parts = [NSMutableArray arrayWithObject:@[@"arrow.down.circle", [[TerraBrowseAPI compactNumber:p.downloads] stringByAppendingString:@" downloads"]]];
    [parts addObject:@[p.source == TerraBrowseSourceCurseForge ? @"hand.thumbsup" : @"heart",
                       [[TerraBrowseAPI compactNumber:p.follows] stringByAppendingString:p.source == TerraBrowseSourceCurseForge ? @" likes" : @" followers"]]];
    if (p.updated) [parts addObject:@[@"clock.arrow.circlepath", [@"Updated " stringByAppendingString:[TerraBrowseAPI relativeDate:p.updated]]]];
    stats.attributedText = TBVStats(parts);
    stats.numberOfLines = 0;
    UIStackView *titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[title, author, stats]];
    titleStack.axis = UILayoutConstraintAxisVertical;
    titleStack.spacing = 4;
    [titleStack setCustomSpacing:8 afterView:author];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[icon, titleStack]];
    top.spacing = 16;
    top.alignment = UIStackViewAlignmentCenter;
    [icon.widthAnchor constraintEqualToConstant:88].active = YES;
    [icon.heightAnchor constraintEqualToConstant:88].active = YES;

    UIStackView *chips = [UIStackView new];
    chips.spacing = 6;
    for (NSString *c in [p.categories subarrayWithRange:NSMakeRange(0, MIN(p.categories.count, 4))]) {
        [chips addArrangedSubview:[TerraStyle chipWithText:c color:TerraStyle.greenBright]];
    }
    for (NSString *l in [p.loaders subarrayWithRange:NSMakeRange(0, MIN(p.loaders.count, 4))]) {
        [chips addArrangedSubview:[TerraStyle chipWithText:l color:TerraStyle.dimText]];
    }
    UIStackView *chipsRow = [[UIStackView alloc] initWithArrangedSubviews:@[chips, [UIView new]]];
    chipsRow.hidden = chips.arrangedSubviews.count == 0;

    UILabel *summary = [UILabel new];
    summary.text = p.summary;
    summary.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    summary.textColor = TerraStyle.text;
    summary.numberOfLines = 0;

    self.descriptionLabel = [UILabel new];
    self.descriptionLabel.font = TerraStyle.bodyFont;
    self.descriptionLabel.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    self.descriptionLabel.numberOfLines = 6;
    self.descriptionLabel.text = @"Loading description…";
    self.moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.moreButton setTitle:@"Read more" forState:UIControlStateNormal];
    self.moreButton.tintColor = TerraStyle.greenBright;
    self.moreButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.moreButton.hidden = YES;
    [self.moreButton addTarget:self action:@selector(toggleMore) forControlEvents:UIControlEventTouchUpInside];
    UIView *descCard = [TerraStyle cardView];
    UIStackView *descStack = [[UIStackView alloc] initWithArrangedSubviews:@[[TerraStyle sectionLabel:@"About"], self.descriptionLabel, self.moreButton]];
    descStack.axis = UILayoutConstraintAxisVertical;
    descStack.spacing = 8;
    descStack.alignment = UIStackViewAlignmentLeading;
    descStack.translatesAutoresizingMaskIntoConstraints = NO;
    [descCard addSubview:descStack];
    [NSLayoutConstraint activateConstraints:@[
        [descStack.topAnchor constraintEqualToAnchor:descCard.topAnchor constant:14],
        [descStack.bottomAnchor constraintEqualToAnchor:descCard.bottomAnchor constant:-12],
        [descStack.leadingAnchor constraintEqualToAnchor:descCard.leadingAnchor constant:14],
        [descStack.trailingAnchor constraintEqualToAnchor:descCard.trailingAnchor constant:-14],
        [self.descriptionLabel.trailingAnchor constraintEqualToAnchor:descStack.trailingAnchor],
    ]];

    NSString *site = p.source == TerraBrowseSourceCurseForge ? @"CurseForge" : @"Modrinth";
    UIButton *web = TBVPillButton([@"View on " stringByAppendingString:site], @"safari");
    __weak typeof(self) weakSelf = self;
    [web addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        NSURL *url = [NSURL URLWithString:weakSelf.project.websiteURL ?: @""];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    web.hidden = p.websiteURL.length == 0;
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[web, [UIView new]]];

    self.versionsTitle = [UILabel new];
    self.versionsTitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.versionsTitle.textColor = TerraStyle.text;
    self.versionsTitle.numberOfLines = 0;
    self.allVersionsButton = TBVPillButton(@"Show all versions", @"line.3.horizontal.decrease.circle");
    [self.allVersionsButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        weakSelf.showAll = !weakSelf.showAll;
        [weakSelf loadVersions];
    }] forControlEvents:UIControlEventTouchUpInside];
    [self.allVersionsButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *versionsRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.versionsTitle, self.allVersionsButton]];
    versionsRow.spacing = 10;
    versionsRow.alignment = UIStackViewAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, chipsRow, summary, actions, descCard, versionsRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    [stack setCustomSpacing:22 afterView:descCard];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-10],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
    ]];
    self.headerView = header;
    [self updateVersionsTitle];
}

- (void)updateVersionsTitle {
    BOOL filtered = [self usesInstallationFilter] && !self.showAll;
    self.versionsTitle.text = filtered
        ? [NSString stringWithFormat:@"Versions for %@\n%@", self.target.name, [self filterDescription]]
        : @"All versions";
    self.allVersionsButton.hidden = ![self usesInstallationFilter];
    UIButtonConfiguration *c = self.allVersionsButton.configuration;
    c.attributedTitle = [[NSAttributedString alloc] initWithString:self.showAll ? @"Only compatible" : @"Show all versions"
                         attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold]}];
    self.allVersionsButton.configuration = c;
    [self sizeHeader];
}

- (void)toggleMore {
    BOOL expanded = self.descriptionLabel.numberOfLines == 0;
    self.descriptionLabel.numberOfLines = expanded ? 6 : 0;
    [self.moreButton setTitle:expanded ? @"Read more" : @"Show less" forState:UIControlStateNormal];
    [self sizeHeader];
}

- (void)loadDescription {
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared descriptionForProject:self.project completion:^(NSString *text) {
        if (!weakSelf) return;
        NSString *t = text.length ? text : @"No description provided.";
        if (t.length > 6000) t = [[t substringToIndex:6000] stringByAppendingString:@"…"];
        weakSelf.descriptionLabel.text = t;
        weakSelf.moreButton.hidden = t.length < 360;
        [weakSelf sizeHeader];
    }];
}

- (void)loadVersions {
    self.loading = YES;
    self.error = nil;
    self.files = @[];
    [self updateVersionsTitle];
    [self.tableView reloadData];
    BOOL filtered = [self usesInstallationFilter] && !self.showAll;
    NSString *loader = nil, *gv = nil;
    if (filtered) {
        gv = self.target.gameVersion;
        if ([self.project.contentType isEqualToString:@"mod"] && self.target.hasModLoader) loader = self.target.loader;
    }
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared versionsForProject:self.project loader:loader gameVersion:gv
                                   completion:^(NSArray<TerraBrowseFile *> *files, NSError *error) {
        if (!weakSelf) return;
        weakSelf.loading = NO;
        weakSelf.files = files ?: @[];
        weakSelf.error = error;
        [weakSelf.tableView reloadData];
    }];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    BOOL empty = self.files.count == 0;
    tableView.backgroundView = nil;
    if (empty) {
        UIView *footer = [self footerStateView];
        CGSize size = [footer systemLayoutSizeFittingSize:CGSizeMake(tableView.bounds.size.width, 0)
                            withHorizontalFittingPriority:UILayoutPriorityRequired
                                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        footer.frame = CGRectMake(0, 0, tableView.bounds.size.width, MAX(size.height, 120));
        tableView.tableFooterView = footer;
    } else {
        tableView.tableFooterView = [UIView new];
    }
    return self.files.count;
}

- (UIView *)footerStateView {
    UIView *v = [UIView new];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10;
    if (self.loading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = TerraStyle.greenBright;
        [spinner startAnimating];
        [stack addArrangedSubview:spinner];
    } else {
        UILabel *l = [UILabel new];
        l.textColor = TerraStyle.dimText;
        l.font = TerraStyle.bodyFont;
        l.numberOfLines = 0;
        l.textAlignment = NSTextAlignmentCenter;
        BOOL filtered = [self usesInstallationFilter] && !self.showAll;
        if (self.error) l.text = self.error.localizedDescription;
        else if (filtered) l.text = [NSString stringWithFormat:@"No versions for %@.", [self filterDescription]];
        else l.text = @"This project has no downloadable versions.";
        [stack addArrangedSubview:l];
        if (filtered && !self.error) {
            UIButton *all = TBVPillButton(@"Show all versions", nil);
            __weak typeof(self) weakSelf = self;
            [all addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
                weakSelf.showAll = YES;
                [weakSelf loadVersions];
            }] forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:all];
        }
    }
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:v.topAnchor constant:28],
        [stack.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-28],
        [stack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-24],
    ]];
    return v;
}

- (BOOL)fileOnDisk:(TerraBrowseFile *)f {
    if (!self.target || [self.project.contentType isEqualToString:@"modpack"]) return NO;
    NSString *folder = [self.target folderForContentType:self.project.contentType];
    return [NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:f.fileName]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraBrowseVersionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"v" forIndexPath:indexPath];
    TerraBrowseFile *f = self.files[indexPath.row];
    [cell configureWithFile:f state:self.states[f.versionId] installedOnDisk:[self fileOnDisk:f]];
    __weak typeof(self) weakSelf = self;
    cell.onInstall = ^{ [weakSelf requestInstall:f]; };
    return cell;
}

- (void)refreshFile:(TerraBrowseFile *)f {
    NSUInteger row = [self.files indexOfObject:f];
    if (row == NSNotFound) return;
    TerraBrowseVersionCell *cell = (TerraBrowseVersionCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
    if (![cell isKindOfClass:TerraBrowseVersionCell.class]) return;
    BOOL statusVisibilityChanged = cell.statusLabel.hidden != ([self.states[f.versionId][@"status"] length] == 0 && ![self fileOnDisk:f]);
    [cell configureWithFile:f state:self.states[f.versionId] installedOnDisk:[self fileOnDisk:f]];
    if (statusVisibilityChanged) {
        [UIView performWithoutAnimation:^{
            [self.tableView beginUpdates];
            [self.tableView endUpdates];
        }];
    }
}

- (void)setPhase:(NSInteger)phase progress:(double)progress status:(NSString *)status forFile:(TerraBrowseFile *)f {
    NSMutableDictionary *s = self.states[f.versionId] ?: [NSMutableDictionary dictionary];
    s[@"phase"] = @(phase);
    s[@"progress"] = @(progress);
    s[@"status"] = status ?: @"";
    self.states[f.versionId] = s;
    [self refreshFile:f];
}

#pragma mark Install

- (void)alert:(NSString *)title message:(NSString *)message actions:(NSArray<UIAlertAction *> *)actions {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    for (UIAlertAction *action in actions) [a addAction:action];
    if (actions.count == 0) [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)requestInstall:(TerraBrowseFile *)f {
    NSString *type = self.project.contentType;
    if ([type isEqualToString:@"modpack"]) {
        [self installModpack:f];
        return;
    }
    TerraBrowseTarget *t = self.target;
    if (!t) {
        [self alert:@"No installation" message:@"Create an installation in Download Center → Minecraft Versions first." actions:@[]];
        return;
    }
    __weak typeof(self) weakSelf = self;
    if ([type isEqualToString:@"mod"]) {
        if (!t.hasModLoader) {
            [self alert:@"This installation has no mod loader"
                message:[NSString stringWithFormat:@"\"%@\" is plain Minecraft %@. Mods need Fabric, Forge, NeoForge or Quilt — install one for %@ first.",
                         t.name, t.gameVersion, t.gameVersion]
                actions:@[[UIAlertAction actionWithTitle:@"Install a mod loader…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                              [TerraVersionInstaller presentInstallForVersion:t.gameVersion from:weakSelf];
                          }],
                          [UIAlertAction actionWithTitle:@"Install anyway" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                              [weakSelf performInstall:f];
                          }],
                          [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]];
            return;
        }
        BOOL compatible = f.loaders.count == 0 || [f.loaders containsObject:t.loader] ||
            ([t.loader isEqualToString:@"quilt"] && [f.loaders containsObject:@"fabric"]);
        if (!compatible) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSString *l in f.loaders) [names addObject:[TerraBrowseAPI displayNameForLoader:l]];
            [self alert:@"Different mod loader"
                message:[NSString stringWithFormat:@"This file is for %@, but \"%@\" uses %@. It probably won't load.",
                         [names componentsJoinedByString:@"/"], t.name, t.loaderDisplayName]
                actions:@[[UIAlertAction actionWithTitle:@"Install anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                              [weakSelf performInstall:f];
                          }],
                          [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]];
            return;
        }
    }
    [self performInstall:f];
}

- (void)performInstall:(TerraBrowseFile *)f {
    TerraBrowseTarget *t = self.target;
    NSString *type = self.project.contentType;
    [self setPhase:1 progress:0 status:@"Starting…" forFile:f];
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared installFile:f contentType:type target:t progress:^(double fraction, NSString *status) {
        [weakSelf setPhase:1 progress:fraction status:status forFile:f];
    } completion:^(NSArray<NSString *> *dependencies, NSError *error) {
        if (error) {
            [weakSelf setPhase:3 progress:0 status:error.localizedDescription forFile:f];
            return;
        }
        NSString *status = dependencies.count
            ? [NSString stringWithFormat:@"Installed to %@ + %@", t.name, [dependencies componentsJoinedByString:@", "]]
            : [NSString stringWithFormat:@"Installed to %@", t.name];
        [weakSelf setPhase:2 progress:1 status:status forFile:f];
        [NSNotificationCenter.defaultCenter postNotificationName:TerraBrowseDidInstallNotification object:nil
                                                        userInfo:@{@"profileName": t.name ?: @"", @"contentType": type ?: @""}];
    }];
}

- (void)installModpack:(TerraBrowseFile *)f {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"terra-modpack-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    [self setPhase:1 progress:0 status:@"Downloading modpack…" forFile:f];
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared downloadFile:f toFolder:tmp progress:^(double fraction) {
        [weakSelf setPhase:1 progress:fraction * 0.3 status:@"Downloading modpack…" forFile:f];
    } completion:^(NSString *path, NSError *error) {
        if (!path) {
            [weakSelf setPhase:3 progress:0 status:error.localizedDescription ?: @"Download failed" forFile:f];
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            return;
        }
        [weakSelf setPhase:1 progress:0.3 status:@"Installing modpack…" forFile:f];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            ModpackImportService *service = [ModpackImportService new];
            NSError *importError = nil;
            NSDictionary *info = [service parseModpackAtURL:[NSURL fileURLWithPath:path] error:&importError];
            BOOL ok = info && [service importModpack:info progress:^(double p, NSString *stage) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf setPhase:1 progress:0.3 + 0.7 * p status:stage forFile:f];
                });
            } error:&importError];
            NSUInteger failedFiles = service.failedFiles.count;
            [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok) {
                    [weakSelf setPhase:3 progress:0 status:importError.localizedDescription ?: @"Import failed" forFile:f];
                    return;
                }
                NSString *name = [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : f.name;
                NSString *status = failedFiles
                    ? [NSString stringWithFormat:@"Installed \"%@\" (%lu files couldn't be downloaded)", name, (unsigned long)failedFiles]
                    : [NSString stringWithFormat:@"Installed \"%@\" — it's in your installations", name];
                [weakSelf setPhase:2 progress:1 status:status forFile:f];
                NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
                [nc postNotificationName:@"ReloadProfileList" object:nil];
                [nc postNotificationName:@"TerraInstancesChanged" object:nil];
                [nc postNotificationName:TerraBrowseDidInstallNotification object:nil userInfo:@{@"contentType": @"modpack"}];
            });
        });
    }];
}

@end

#pragma mark - Browser

@interface TerraBrowseViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) TerraBrowseQuery *query;
@property (nonatomic, strong) NSMutableArray<TerraBrowseProject *> *results;
@property (nonatomic, assign) NSInteger totalHits;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL reachedEnd;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong, nullable) TerraBrowseTarget *target;
@property (nonatomic, copy) NSArray<TerraBrowseTarget *> *targets;
@property (nonatomic, copy) NSArray<NSDictionary *> *categoryOptions;
@property (nonatomic, assign) BOOL categoriesLoading;
@property (nonatomic, copy) NSArray<NSString *> *gameVersions;

@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) NSMutableArray<UIView *> *tabUnderlines;
@property (nonatomic, strong) UIButton *targetButton;
@property (nonatomic, strong) UIButton *modrinthButton;
@property (nonatomic, strong) UIButton *curseForgeButton;
@property (nonatomic, strong) UIButton *potatoButton;
@property (nonatomic, strong) UIButton *competitiveButton;
@property (nonatomic, strong) UIButton *filtersButton;
@property (nonatomic, strong) UISearchTextField *searchField;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIScrollView *sidebarScroll;
@property (nonatomic, strong) UIStackView *filterStack;
@property (nonatomic, strong) UIView *mainColumn;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *sidebarConstraints;
@property (nonatomic, strong) NSLayoutConstraint *mainLeadingToView;
@property (nonatomic, assign) BOOL wideLayout;
@property (nonatomic, assign) BOOL layoutDecided;
@property (nonatomic, assign) BOOL sidebarInSheet;
@property (nonatomic, strong) NSTimer *searchDebounce;
@end

@implementation TerraBrowseViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        _showsOptimizeButtons = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];
    if (self.navigationController && !self.title) self.title = @"Browse";
    self.results = [NSMutableArray array];
    self.query = [TerraBrowseQuery new];
    self.query.contentType = [TBVTypes() containsObject:self.contentType ?: @""] ? self.contentType : @"mod";
    self.query.source = TerraBrowseSourceModrinth;
    self.categoryOptions = @[];
    self.gameVersions = @[];
    [self reloadTargets];
    [self buildHeader];
    [self buildBody];
    [self applyDefaultFilters];
    [self updateTabs];
    [self updateSourceButtons];
    [self updateTargetButton];
    [self loadCategories];
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared releaseGameVersions:^(NSArray<NSString *> *versions) {
        weakSelf.gameVersions = versions;
        [weakSelf rebuildFilters];
    }];
    [self loadFirstPage];
    for (NSString *name in @[@"TerraInstancesChanged", @"ReloadProfileList", @"TerraVersionInstallerDidFinishNotification"]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(installationsChanged) name:name object:nil];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self.searchDebounce invalidate];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self installationsChanged];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL wide = self.view.bounds.size.width >= 760;
    if (!self.layoutDecided || wide != self.wideLayout) {
        self.layoutDecided = YES;
        self.wideLayout = wide;
        [self applyWidthLayout];
    }
}

#pragma mark Targets

- (void)reloadTargets {
    self.targets = [TerraBrowseTarget allTargets];
    NSString *want = self.target.name ?: self.profileName;
    TerraBrowseTarget *found = nil;
    for (TerraBrowseTarget *t in self.targets) if ([t.name isEqualToString:want]) found = t;
    if (!found) {
        NSString *selected = [TerraBrowseTarget defaultTarget].name;
        for (TerraBrowseTarget *t in self.targets) if ([t.name isEqualToString:selected]) found = t;
    }
    self.target = found ?: self.targets.firstObject;
}

- (void)installationsChanged {
    if (!self.isViewLoaded) return;
    NSString *before = [NSString stringWithFormat:@"%@|%@|%@", self.target.name, self.target.loader, self.target.gameVersion];
    [self reloadTargets];
    [self updateTargetButton];
    NSString *after = [NSString stringWithFormat:@"%@|%@|%@", self.target.name, self.target.loader, self.target.gameVersion];
    if (![before isEqualToString:after]) {
        [self applyDefaultFilters];
        [self loadFirstPage];
    }
}

- (void)setProfileName:(NSString *)profileName {
    _profileName = [profileName copy];
    if (self.isViewLoaded) {
        for (TerraBrowseTarget *t in self.targets) if ([t.name isEqualToString:profileName]) [self selectTarget:t];
    }
}

- (void)setContentType:(NSString *)contentType {
    _contentType = [contentType copy];
    if (self.isViewLoaded && [TBVTypes() containsObject:contentType ?: @""]) [self selectType:contentType];
}

- (void)selectTarget:(TerraBrowseTarget *)t {
    self.target = t;
    _profileName = [t.name copy];
    [self updateTargetButton];
    [self applyDefaultFilters];
    [self loadFirstPage];
}

/// Filters follow the installation: its loader for mods, its Minecraft version for everything
/// except modpacks (which create their own installation).
- (void)applyDefaultFilters {
    NSString *type = self.query.contentType;
    TerraBrowseTarget *t = self.target;
    self.query.categories = @[];
    self.query.loader = ([type isEqualToString:@"mod"] && t.hasModLoader) ? t.loader : nil;
    self.query.gameVersion = ([type isEqualToString:@"modpack"] || t.gameVersion.length == 0) ? nil : t.gameVersion;
    [self rebuildFilters];
}

#pragma mark Header

- (void)buildHeader {
    // Content tabs
    UIStackView *tabs = [UIStackView new];
    tabs.spacing = 4;
    self.tabButtons = [NSMutableArray array];
    self.tabUnderlines = [NSMutableArray array];
    for (NSUInteger i = 0; i < TBVTypes().count; i++) {
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.image = TBVSymbol(TBVTypeSymbols()[i], 13, nil);
        c.imagePadding = 7;
        c.contentInsets = NSDirectionalEdgeInsetsMake(10, 12, 12, 12);
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
        NSString *type = TBVTypes()[i];
        __weak typeof(self) weakSelf = self;
        [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf selectType:type]; }]
    forControlEvents:UIControlEventTouchUpInside];
        UIView *underline = [UIView new];
        underline.backgroundColor = TerraStyle.greenBright;
        underline.layer.cornerRadius = 1.5;
        underline.translatesAutoresizingMaskIntoConstraints = NO;
        [b addSubview:underline];
        [NSLayoutConstraint activateConstraints:@[
            [underline.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:10],
            [underline.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-10],
            [underline.bottomAnchor constraintEqualToAnchor:b.bottomAnchor],
            [underline.heightAnchor constraintEqualToConstant:3],
        ]];
        [tabs addArrangedSubview:b];
        [self.tabButtons addObject:b];
        [self.tabUnderlines addObject:underline];
    }
    UIScrollView *tabScroll = [UIScrollView new];
    tabScroll.showsHorizontalScrollIndicator = NO;
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [tabScroll addSubview:tabs];
    [NSLayoutConstraint activateConstraints:@[
        [tabs.topAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.topAnchor],
        [tabs.bottomAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.bottomAnchor],
        [tabs.leadingAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.leadingAnchor],
        [tabs.trailingAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.trailingAnchor],
        [tabs.heightAnchor constraintEqualToAnchor:tabScroll.frameLayoutGuide.heightAnchor],
        [tabScroll.heightAnchor constraintEqualToConstant:46],
    ]];
    UIView *hairline = [UIView new];
    hairline.backgroundColor = TerraStyle.border;
    [hairline.heightAnchor constraintEqualToConstant:1].active = YES;

    // Target, source, one-tap sets
    self.targetButton = TBVPillButton(@"Install to", @"square.and.arrow.down.on.square");
    self.targetButton.showsMenuAsPrimaryAction = YES;
    [self.targetButton setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.modrinthButton = TBVPillButton(@"Modrinth", nil);
    self.curseForgeButton = TBVPillButton(@"CurseForge", nil);
    __weak typeof(self) weakSelf = self;
    [self.modrinthButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        [weakSelf selectSource:TerraBrowseSourceModrinth];
    }] forControlEvents:UIControlEventTouchUpInside];
    [self.curseForgeButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        [weakSelf selectSource:TerraBrowseSourceCurseForge];
    }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *source = [[UIStackView alloc] initWithArrangedSubviews:@[self.modrinthButton, self.curseForgeButton]];
    source.spacing = 4;
    [source setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.potatoButton = [TerraStyle blockButtonWithTitle:@"Potato Optimize" symbol:@"bolt.fill" primary:YES];
    [self.potatoButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        [TerraPotatoOptimizer optimizeProfile:weakSelf.target.name presenter:weakSelf];
    }] forControlEvents:UIControlEventTouchUpInside];
    self.competitiveButton = [TerraStyle blockButtonWithTitle:@"Competitive Download" symbol:@"trophy.fill" primary:NO];
    [self.competitiveButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        [TerraPotatoOptimizer competitiveProfile:weakSelf.target.name presenter:weakSelf];
    }] forControlEvents:UIControlEventTouchUpInside];
    for (UIButton *b in @[self.potatoButton, self.competitiveButton]) {
        b.hidden = !self.showsOptimizeButtons;
        [b setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    UIView *flex = [UIView new];
    [flex setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *rowB = [[UIStackView alloc] initWithArrangedSubviews:@[self.targetButton, flex, source, self.competitiveButton, self.potatoButton]];
    rowB.spacing = 10;
    rowB.alignment = UIStackViewAlignmentCenter;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[tabScroll, hairline, rowB]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 0;
    [header setCustomSpacing:12 afterView:hairline];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.tag = 4401;
    [self.view addSubview:header];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:g.topAnchor constant:6],
        [header.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
    ]];
}

- (void)updateTabs {
    for (NSUInteger i = 0; i < self.tabButtons.count; i++) {
        BOOL selected = [TBVTypes()[i] isEqualToString:self.query.contentType];
        UIButton *b = self.tabButtons[i];
        UIButtonConfiguration *c = b.configuration;
        UIColor *color = selected ? TerraStyle.text : TerraStyle.dimText;
        c.baseForegroundColor = color;
        c.attributedTitle = [[NSAttributedString alloc] initWithString:TBVTypeTitles()[i]
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15 weight:selected ? UIFontWeightBold : UIFontWeightMedium]}];
        b.configuration = c;
        self.tabUnderlines[i].hidden = !selected;
    }
    self.searchField.placeholder = [NSString stringWithFormat:@"Search %@…", TBVTypeNoun(self.query.contentType, YES)];
}

- (void)updateSourceButtons {
    BOOL mr = self.query.source == TerraBrowseSourceModrinth;
    for (UIButton *b in @[self.modrinthButton, self.curseForgeButton]) {
        BOOL selected = (b == self.modrinthButton) == mr;
        UIButtonConfiguration *c = b.configuration;
        UIColor *accent = b == self.modrinthButton ? TerraStyle.green : TBVCurseForgeOrange();
        c.baseBackgroundColor = selected ? accent : TerraStyle.raised;
        c.baseForegroundColor = selected ? UIColor.whiteColor : TerraStyle.dimText;
        b.configuration = c;
    }
}

- (void)updateTargetButton {
    UIButtonConfiguration *c = self.targetButton.configuration;
    NSString *title = self.target ? self.target.name : @"No installation";
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold]}];
    c.attributedSubtitle = self.target
        ? [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Install to · %@ %@", self.target.loaderDisplayName, self.target.gameVersion]
                                          attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: TerraStyle.dimText}]
        : nil;
    c.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    c.indicator = UIButtonConfigurationIndicatorPopup;
    self.targetButton.configuration = c;
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (TerraBrowseTarget *t in self.targets) {
        UIAction *a = [UIAction actionWithTitle:t.name image:nil identifier:nil handler:^(__kindof UIAction *action) {
            [weakSelf selectTarget:t];
        }];
        a.subtitle = [NSString stringWithFormat:@"%@ %@", t.loaderDisplayName, t.gameVersion];
        a.state = [t.name isEqualToString:self.target.name] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    if (actions.count == 0) {
        [actions addObject:[UIAction actionWithTitle:@"No installations yet" image:nil identifier:nil handler:^(__kindof UIAction *a) {}]];
    }
    self.targetButton.menu = [UIMenu menuWithTitle:@"Install to" children:actions];
}

#pragma mark Body

- (void)buildBody {
    UIView *header = [self.view viewWithTag:4401];
    self.filterStack = [UIStackView new];
    self.filterStack.axis = UILayoutConstraintAxisVertical;
    self.filterStack.spacing = 2;
    self.filterStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarScroll = [UIScrollView new];
    self.sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarScroll.showsVerticalScrollIndicator = NO;
    [self.sidebarScroll addSubview:self.filterStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.filterStack.topAnchor constraintEqualToAnchor:self.sidebarScroll.contentLayoutGuide.topAnchor],
        [self.filterStack.bottomAnchor constraintEqualToAnchor:self.sidebarScroll.contentLayoutGuide.bottomAnchor constant:-20],
        [self.filterStack.leadingAnchor constraintEqualToAnchor:self.sidebarScroll.frameLayoutGuide.leadingAnchor],
        [self.filterStack.trailingAnchor constraintEqualToAnchor:self.sidebarScroll.frameLayoutGuide.trailingAnchor],
    ]];

    self.mainColumn = [UIView new];
    self.mainColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mainColumn];

    self.filtersButton = TBVPillButton(@"Filters", @"line.3.horizontal.decrease");
    __weak typeof(self) weakSelf = self;
    [self.filtersButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf presentFilterSheet]; }]
                 forControlEvents:UIControlEventTouchUpInside];
    [self.filtersButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    self.searchField = [TerraStyle searchFieldWithPlaceholder:@"Search mods…"];
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.delegate = self;
    self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    self.countLabel = [UILabel new];
    self.countLabel.font = TerraStyle.captionFont;
    self.countLabel.textColor = TerraStyle.dimText;
    [self.countLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *searchRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.filtersButton, self.searchField, self.countLabel]];
    searchRow.spacing = 10;
    searchRow.alignment = UIStackViewAlignmentCenter;
    searchRow.translatesAutoresizingMaskIntoConstraints = NO;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 128;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 20, 0);
    [self.tableView registerClass:TerraBrowseResultCell.class forCellReuseIdentifier:@"r"];

    [self.mainColumn addSubview:searchRow];
    [self.mainColumn addSubview:self.tableView];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    self.mainLeadingToView = [self.mainColumn.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16];
    [NSLayoutConstraint activateConstraints:@[
        [self.mainColumn.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [self.mainColumn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [self.mainColumn.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [searchRow.topAnchor constraintEqualToAnchor:self.mainColumn.topAnchor],
        [searchRow.leadingAnchor constraintEqualToAnchor:self.mainColumn.leadingAnchor],
        [searchRow.trailingAnchor constraintEqualToAnchor:self.mainColumn.trailingAnchor],
        [self.tableView.topAnchor constraintEqualToAnchor:searchRow.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.mainColumn.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.mainColumn.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.mainColumn.bottomAnchor],
    ]];
    self.mainLeadingToView.active = YES;
}

- (void)attachSidebar {
    if (self.sidebarScroll.superview != self.view) {
        [self.sidebarScroll removeFromSuperview];
        [self.view addSubview:self.sidebarScroll];
    }
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint deactivateConstraints:self.sidebarConstraints ?: @[]];
    self.sidebarConstraints = @[
        [self.sidebarScroll.topAnchor constraintEqualToAnchor:self.mainColumn.topAnchor constant:2],
        [self.sidebarScroll.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.sidebarScroll.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
        [self.sidebarScroll.widthAnchor constraintEqualToConstant:228],
        [self.mainColumn.leadingAnchor constraintEqualToAnchor:self.sidebarScroll.trailingAnchor constant:18],
    ];
}

- (void)applyWidthLayout {
    BOOL wide = self.wideLayout;
    if (wide && !self.sidebarInSheet) {
        [self attachSidebar];
        self.mainLeadingToView.active = NO;
        [NSLayoutConstraint activateConstraints:self.sidebarConstraints];
        self.sidebarScroll.hidden = NO;
    } else {
        [NSLayoutConstraint deactivateConstraints:self.sidebarConstraints ?: @[]];
        if (self.sidebarScroll.superview == self.view) self.sidebarScroll.hidden = YES;
        self.mainLeadingToView.active = YES;
    }
    self.filtersButton.hidden = wide;
    self.countLabel.hidden = !wide || self.totalHits <= 0;
    // Icon-only optimize buttons when space is tight
    BOOL compact = self.view.bounds.size.width < 1000;
    [self.potatoButton setTitle:compact ? nil : @"Potato Optimize" forState:UIControlStateNormal];
    [self.competitiveButton setTitle:compact ? nil : @"Competitive Download" forState:UIControlStateNormal];
    self.potatoButton.accessibilityLabel = @"Potato Optimize";
    self.competitiveButton.accessibilityLabel = @"Competitive Download";
}

- (void)presentFilterSheet {
    TerraBrowseFilterSheet *sheet = [TerraBrowseFilterSheet new];
    [NSLayoutConstraint deactivateConstraints:self.sidebarConstraints ?: @[]];
    [self.sidebarScroll removeFromSuperview];
    self.sidebarScroll.hidden = NO;
    sheet.hostedView = self.sidebarScroll;
    self.sidebarInSheet = YES;
    __weak typeof(self) weakSelf = self;
    sheet.onClose = ^{
        weakSelf.sidebarInSheet = NO;
        [weakSelf.sidebarScroll removeFromSuperview];
        [weakSelf.view addSubview:weakSelf.sidebarScroll];
        weakSelf.sidebarScroll.hidden = YES;
        [weakSelf applyWidthLayout];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                UISheetPresentationControllerDetent.largeDetent];
    nav.sheetPresentationController.prefersGrabberVisible = YES;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Filters

- (UIButton *)optionRow:(NSString *)title selected:(BOOL)selected checkbox:(BOOL)checkbox handler:(void (^)(void))handler {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    NSString *symbol = checkbox ? (selected ? @"checkmark.square.fill" : @"square")
                                : (selected ? @"largecircle.fill.circle" : @"circle");
    c.image = TBVSymbol(symbol, 15, selected ? TerraStyle.greenBright : TerraStyle.dimText);
    c.imagePadding = 10;
    c.contentInsets = NSDirectionalEdgeInsetsMake(7, 2, 7, 2);
    c.attributedTitle = [[NSAttributedString alloc] initWithString:title
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14.5 weight:selected ? UIFontWeightSemibold : UIFontWeightRegular],
                     NSForegroundColorAttributeName: selected ? TerraStyle.text : [UIColor colorWithWhite:0.80 alpha:1]}];
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { handler(); }]];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    return b;
}

- (void)addSection:(NSString *)title {
    UILabel *l = [TerraStyle sectionLabel:title];
    UIView *wrap = [UIView new];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:self.filterStack.arrangedSubviews.count ? 18 : 4],
        [l.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-4],
        [l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:2],
        [l.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
    ]];
    [self.filterStack addArrangedSubview:wrap];
}

- (void)rebuildFilters {
    if (!self.filterStack) return;
    for (UIView *v in self.filterStack.arrangedSubviews) [v removeFromSuperview];
    __weak typeof(self) weakSelf = self;
    TerraBrowseQuery *q = self.query;

    [self addSection:@"Sort by"];
    NSArray *sorts = @[@"Relevance", @"Downloads", @"Follows", @"Newest", @"Recently updated"];
    for (NSUInteger i = 0; i < sorts.count; i++) {
        [self.filterStack addArrangedSubview:[self optionRow:sorts[i] selected:q.sort == (TerraBrowseSort)i checkbox:NO handler:^{
            weakSelf.query.sort = (TerraBrowseSort)i;
            [weakSelf filtersChanged];
        }]];
    }

    if (TBVUsesLoader(q.contentType)) {
        [self addSection:@"Loader"];
        NSArray *loaders = @[@"", @"fabric", @"forge", @"neoforge", @"quilt"];
        for (NSString *l in loaders) {
            NSString *title = l.length ? [TerraBrowseAPI displayNameForLoader:l] : @"Any loader";
            BOOL selected = l.length ? [q.loader isEqualToString:l] : q.loader.length == 0;
            [self.filterStack addArrangedSubview:[self optionRow:title selected:selected checkbox:NO handler:^{
                weakSelf.query.loader = l.length ? l : nil;
                [weakSelf filtersChanged];
            }]];
        }
    }

    [self addSection:@"Game version"];
    UIButton *versionButton = TBVPillButton(q.gameVersion.length ? q.gameVersion : @"Any version", @"cube");
    UIButtonConfiguration *vc = versionButton.configuration;
    vc.indicator = UIButtonConfigurationIndicatorPopup;
    versionButton.configuration = vc;
    versionButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    versionButton.showsMenuAsPrimaryAction = YES;
    NSMutableArray *top = [NSMutableArray array];
    [top addObject:[UIAction actionWithTitle:@"Any version" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        weakSelf.query.gameVersion = nil;
        [weakSelf filtersChanged];
    }]];
    if (self.target.gameVersion.length) {
        NSString *gv = self.target.gameVersion;
        UIAction *mine = [UIAction actionWithTitle:gv image:TBVSymbol(@"star.fill", 12, nil) identifier:nil handler:^(__kindof UIAction *a) {
            weakSelf.query.gameVersion = gv;
            [weakSelf filtersChanged];
        }];
        mine.subtitle = [@"Version of " stringByAppendingString:self.target.name];
        [top addObject:mine];
    }
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *v in [self.gameVersions subarrayWithRange:NSMakeRange(0, MIN(self.gameVersions.count, 120))]) {
        UIAction *a = [UIAction actionWithTitle:v image:nil identifier:nil handler:^(__kindof UIAction *action) {
            weakSelf.query.gameVersion = v;
            [weakSelf filtersChanged];
        }];
        a.state = [v isEqualToString:q.gameVersion] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [all addObject:a];
    }
    versionButton.menu = [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:top],
        [UIMenu menuWithTitle:@"All releases" image:nil identifier:nil options:0 children:all.count ? all : @[
            [UIAction actionWithTitle:@"Loading…" image:nil identifier:nil handler:^(__kindof UIAction *a) {}]]]]];
    [self.filterStack addArrangedSubview:versionButton];

    [self addSection:@"Categories"];
    if (self.categoriesLoading && self.categoryOptions.count == 0) {
        UILabel *l = [UILabel new];
        l.text = @"Loading…";
        l.font = TerraStyle.captionFont;
        l.textColor = TerraStyle.dimText;
        [self.filterStack addArrangedSubview:l];
    } else if (self.categoryOptions.count == 0) {
        UILabel *l = [UILabel new];
        l.text = self.query.source == TerraBrowseSourceCurseForge && ![TerraBrowseAPI curseForgeKeyConfigured]
            ? @"Available once a CurseForge API key is added." : @"No categories.";
        l.numberOfLines = 0;
        l.font = TerraStyle.captionFont;
        l.textColor = TerraStyle.dimText;
        [self.filterStack addArrangedSubview:l];
    }
    for (NSDictionary *c in self.categoryOptions) {
        NSString *cid = c[@"id"];
        BOOL selected = [q.categories containsObject:cid];
        [self.filterStack addArrangedSubview:[self optionRow:c[@"name"] selected:selected checkbox:YES handler:^{
            NSMutableArray *cats = [weakSelf.query.categories mutableCopy];
            if ([cats containsObject:cid]) [cats removeObject:cid]; else [cats addObject:cid];
            weakSelf.query.categories = cats;
            [weakSelf filtersChanged];
        }]];
    }

    UIButton *reset = TBVPillButton(@"Reset filters", @"arrow.counterclockwise");
    [reset addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        weakSelf.query.sort = TerraBrowseSortRelevance;
        [weakSelf applyDefaultFilters];
        [weakSelf loadFirstPage];
    }] forControlEvents:UIControlEventTouchUpInside];
    UIView *gap = [UIView new];
    [gap.heightAnchor constraintEqualToConstant:14].active = YES;
    [self.filterStack addArrangedSubview:gap];
    [self.filterStack addArrangedSubview:reset];
}

- (void)filtersChanged {
    [self rebuildFilters];
    [self loadFirstPage];
}

- (void)loadCategories {
    self.categoriesLoading = YES;
    self.categoryOptions = @[];
    [self rebuildFilters];
    TerraBrowseSource source = self.query.source;
    NSString *type = self.query.contentType;
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared categoriesForSource:source contentType:type completion:^(NSArray *categories) {
        if (weakSelf.query.source != source || ![weakSelf.query.contentType isEqualToString:type]) return;
        weakSelf.categoriesLoading = NO;
        weakSelf.categoryOptions = categories ?: @[];
        [weakSelf rebuildFilters];
    }];
}

#pragma mark Actions

- (void)selectType:(NSString *)type {
    if ([type isEqualToString:self.query.contentType]) return;
    _contentType = [type copy];
    self.query.contentType = type;
    self.query.sort = TerraBrowseSortRelevance;
    [self applyDefaultFilters];
    [self updateTabs];
    [self loadCategories];
    [self loadFirstPage];
}

- (void)selectSource:(TerraBrowseSource)source {
    if (source == self.query.source) return;
    self.query.source = source;
    self.query.categories = @[];
    [self updateSourceButtons];
    [self loadCategories];
    [self loadFirstPage];
}

- (void)searchChanged {
    [self.searchDebounce invalidate];
    __weak typeof(self) weakSelf = self;
    self.searchDebounce = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer *t) {
        [weakSelf loadFirstPage];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.searchDebounce invalidate];
    [textField resignFirstResponder];
    [self loadFirstPage];
    return YES;
}

#pragma mark Loading

- (void)loadFirstPage {
    if (!self.tableView) return;
    self.generation++;
    NSUInteger gen = self.generation;
    self.query.text = [self.searchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    self.query.offset = 0;
    self.query.limit = 20;
    [self.results removeAllObjects];
    self.totalHits = 0;
    self.loading = YES;
    self.loadingMore = NO;
    self.reachedEnd = NO;
    self.error = nil;
    self.countLabel.hidden = YES;
    self.tableView.tableFooterView = [UIView new];
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointMake(0, -self.tableView.adjustedContentInset.top) animated:NO];
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared search:[self.query copy] completion:^(NSArray<TerraBrowseProject *> *results, NSInteger total, NSError *error) {
        if (!weakSelf || gen != weakSelf.generation) return;
        weakSelf.loading = NO;
        weakSelf.error = error;
        [weakSelf.results addObjectsFromArray:results ?: @[]];
        weakSelf.totalHits = total;
        weakSelf.reachedEnd = results.count < (NSUInteger)weakSelf.query.limit || (NSInteger)weakSelf.results.count >= total;
        [weakSelf updateCountLabel];
        [weakSelf updateFooter];
        [weakSelf.tableView reloadData];
    }];
}

- (void)loadNextPage {
    if (self.loading || self.loadingMore || self.reachedEnd || self.error) return;
    self.loadingMore = YES;
    [self updateFooter];
    NSUInteger gen = self.generation;
    TerraBrowseQuery *q = [self.query copy];
    q.offset = self.results.count;
    __weak typeof(self) weakSelf = self;
    [TerraBrowseAPI.shared search:q completion:^(NSArray<TerraBrowseProject *> *results, NSInteger total, NSError *error) {
        if (!weakSelf || gen != weakSelf.generation) return;
        weakSelf.loadingMore = NO;
        if (error) {
            weakSelf.reachedEnd = YES;   // stop hammering; pull a new search to retry
            [weakSelf updateFooter];
            return;
        }
        NSUInteger start = weakSelf.results.count;
        [weakSelf.results addObjectsFromArray:results ?: @[]];
        weakSelf.reachedEnd = results.count < (NSUInteger)q.limit || (NSInteger)weakSelf.results.count >= total;
        NSMutableArray *paths = [NSMutableArray array];
        for (NSUInteger i = start; i < weakSelf.results.count; i++) [paths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
        [UIView performWithoutAnimation:^{
            [weakSelf.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
        }];
        [weakSelf updateFooter];
    }];
}

- (void)updateCountLabel {
    if (self.totalHits <= 0) {
        self.countLabel.hidden = YES;
        return;
    }
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    self.countLabel.text = [NSString stringWithFormat:@"%@ %@", [f stringFromNumber:@(self.totalHits)], TBVTypeNoun(self.query.contentType, self.totalHits != 1)];
    self.countLabel.hidden = !self.wideLayout;
}

- (void)updateFooter {
    if (self.results.count == 0) {
        self.tableView.tableFooterView = [UIView new];
        return;
    }
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 64)];
    if (self.loadingMore) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = TerraStyle.greenBright;
        spinner.center = CGPointMake(footer.bounds.size.width / 2, 32);
        spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [spinner startAnimating];
        [footer addSubview:spinner];
    } else if (self.reachedEnd) {
        UILabel *l = [[UILabel alloc] initWithFrame:footer.bounds];
        l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        l.text = @"You've reached the end";
        l.textAlignment = NSTextAlignmentCenter;
        l.font = TerraStyle.captionFont;
        l.textColor = TerraStyle.dimText;
        [footer addSubview:l];
    }
    self.tableView.tableFooterView = footer;
}

#pragma mark State views

- (UIView *)stateViewWithSymbol:(NSString *)symbol tint:(UIColor *)tint title:(NSString *)title message:(NSString *)message
                        buttons:(NSArray<UIButton *> *)buttons card:(BOOL)card {
    UIView *container = [UIView new];
    UIImageView *icon = [[UIImageView alloc] initWithImage:TBVSymbol(symbol, 34, tint)];
    icon.contentMode = UIViewContentModeCenter;
    UILabel *t = [UILabel new];
    t.text = title;
    t.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    t.textColor = TerraStyle.text;
    t.textAlignment = NSTextAlignmentCenter;
    t.numberOfLines = 0;
    UILabel *m = [UILabel new];
    m.text = message;
    m.font = TerraStyle.bodyFont;
    m.textColor = TerraStyle.dimText;
    m.textAlignment = NSTextAlignmentCenter;
    m.numberOfLines = 0;
    UIStackView *buttonRow = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    buttonRow.spacing = 10;
    buttonRow.alignment = UIStackViewAlignmentCenter;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, t, m]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    if (buttons.count) {
        [stack setCustomSpacing:18 afterView:m];
        [stack addArrangedSubview:buttonRow];
    }
    UIView *box = card ? [TerraStyle cardView] : [UIView new];
    if (card) box.layer.cornerRadius = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:stack];
    [container addSubview:box];
    CGFloat pad = card ? 26 : 0;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:box.topAnchor constant:pad],
        [stack.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-pad],
        [stack.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-pad],
        [box.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [box.topAnchor constraintEqualToAnchor:container.topAnchor constant:40],
        [box.widthAnchor constraintLessThanOrEqualToConstant:480],
        [box.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:8],
        [box.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-8],
    ]];
    return container;
}

- (UIView *)currentStateView {
    __weak typeof(self) weakSelf = self;
    if (self.error.code == TerraBrowseErrorCurseForgeNeedsKey || self.error.code == TerraBrowseErrorCurseForgeKeyRejected) {
        BOOL rejected = self.error.code == TerraBrowseErrorCurseForgeKeyRejected;
        UIButton *add = [TerraStyle blockButtonWithTitle:rejected ? @"Update API key" : @"Add API key" symbol:@"key.fill" primary:YES];
        [add addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf openCurseForgeKeySettings]; }]
      forControlEvents:UIControlEventTouchUpInside];
        UIButton *get = [TerraStyle blockButtonWithTitle:@"Get a free key" symbol:@"safari" primary:NO];
        [get addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://console.curseforge.com/"] options:@{} completionHandler:nil];
        }] forControlEvents:UIControlEventTouchUpInside];
        UIView *v = [self stateViewWithSymbol:@"key.horizontal.fill" tint:TBVCurseForgeOrange()
                                        title:rejected ? @"CurseForge didn't accept your API key" : @"CurseForge needs an API key"
                                      message:rejected
            ? @"The key saved in Settings was rejected. Create a new one in the CurseForge console and paste it here. Modrinth keeps working without a key."
            : @"CurseForge only lets apps search with a personal API key. It's free — create one in the CurseForge console and paste it here. Modrinth works without a key."
                                      buttons:@[get, add] card:YES];
        UIButton *useModrinth = [UIButton buttonWithType:UIButtonTypeSystem];
        [useModrinth setTitle:@"Browse Modrinth instead" forState:UIControlStateNormal];
        useModrinth.tintColor = TerraStyle.greenBright;
        useModrinth.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [useModrinth addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf selectSource:TerraBrowseSourceModrinth]; }]
              forControlEvents:UIControlEventTouchUpInside];
        useModrinth.translatesAutoresizingMaskIntoConstraints = NO;
        [v addSubview:useModrinth];
        UIView *box = v.subviews.firstObject;
        [NSLayoutConstraint activateConstraints:@[
            [useModrinth.topAnchor constraintEqualToAnchor:box.bottomAnchor constant:14],
            [useModrinth.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],
        ]];
        return v;
    }
    if (self.error) {
        UIButton *retry = [TerraStyle blockButtonWithTitle:@"Try again" symbol:@"arrow.clockwise" primary:YES];
        [retry addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf loadFirstPage]; }]
        forControlEvents:UIControlEventTouchUpInside];
        return [self stateViewWithSymbol:@"wifi.exclamationmark" tint:TerraStyle.dimText title:@"Couldn't load results"
                                 message:self.error.localizedDescription buttons:@[retry] card:NO];
    }
    UIButton *clear = [TerraStyle blockButtonWithTitle:@"Clear search & filters" symbol:@"xmark" primary:NO];
    [clear addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        weakSelf.searchField.text = @"";
        weakSelf.query.sort = TerraBrowseSortRelevance;
        [weakSelf applyDefaultFilters];
        weakSelf.query.gameVersion = nil;
        weakSelf.query.loader = nil;
        [weakSelf rebuildFilters];
        [weakSelf loadFirstPage];
    }] forControlEvents:UIControlEventTouchUpInside];
    NSString *message = self.query.gameVersion.length
        ? [NSString stringWithFormat:@"Nothing matches for Minecraft %@%@. Try a different search or fewer filters.",
           self.query.gameVersion, self.query.loader.length ? [@" + " stringByAppendingString:[TerraBrowseAPI displayNameForLoader:self.query.loader]] : @""]
        : @"Try a different search or fewer filters.";
    return [self stateViewWithSymbol:@"magnifyingglass" tint:TerraStyle.dimText
                               title:[NSString stringWithFormat:@"No %@ found", TBVTypeNoun(self.query.contentType, YES)]
                             message:message buttons:@[clear] card:NO];
}

- (void)openCurseForgeKeySettings {
    Class cls = NSClassFromString(@"CurseForgeAPIKeyViewController");
    if (![cls isSubclassOfClass:UIViewController.class]) return;
    UIViewController *vc = [cls new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    __weak typeof(self) weakSelf = self;
    __weak UINavigationController *weakNav = nav;
    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        primaryAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            [weakNav dismissViewControllerAnimated:YES completion:^{
                [weakSelf loadCategories];
                [weakSelf loadFirstPage];
            }];
        }]];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.loading) {
        tableView.backgroundView = nil;
        return 6;
    }
    tableView.backgroundView = self.results.count == 0 ? [self currentStateView] : nil;
    return self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraBrowseResultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"r" forIndexPath:indexPath];
    if (self.loading || indexPath.row >= (NSInteger)self.results.count) {
        [cell configureSkeleton];
    } else {
        [cell configureWithProject:self.results[indexPath.row]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.loading && indexPath.row >= (NSInteger)self.results.count - 4) [self loadNextPage];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.loading || indexPath.row >= (NSInteger)self.results.count) return;
    [self.searchField resignFirstResponder];
    TerraBrowseProjectViewController *page = [TerraBrowseProjectViewController new];
    page.project = self.results[indexPath.row];
    page.target = self.target;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
    nav.sheetPresentationController.prefersGrabberVisible = YES;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.navigationBar.tintColor = TerraStyle.greenBright;
    [self presentViewController:nav animated:YES completion:nil];
}

@end
