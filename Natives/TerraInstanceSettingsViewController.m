//
//  TerraInstanceSettingsViewController.m
//  ★ [TERRA-INSTANCE] see TerraInstanceSettingsViewController.h
//
//  Persistence mirrors ProfileSettingsViewController exactly (same keys, same "remove key ⇒ fall
//  back to global" semantics), but every change is written immediately for the one key it touches:
//    name            rename = move the profile key, update selectedProfile when it was selected
//    lastVersionId   game version
//    javaVersion     "0" = Auto, otherwise the major version string ("8", "17", "21", …)
//    allocatedMemory NSNumber MB (absent ⇒ launcher default)
//    javaArgs        string; empty ⇒ key removed (global java.java_args applies)
//    renderer        renderer key; "(default)" ⇒ key removed (global video.renderer applies)
//    graphicsApi     default / prefer_vulkan / prefer_opengl (MC 1.21.8+ / 26.x only)
//    versionIsolation via ameVISetExplicitStateForProfile (Auto ⇒ removed, "1" / "0")
//    gameDir         "." or a relative/absolute path
//    serverIp        via -[PLProfiles setServerIp:forProfile:]
//  After each write "TerraInstancesChanged" is posted so the launcher refreshes.
//

#import "TerraInstanceSettingsViewController.h"
#import "TerraStyle.h"
#import "PLProfiles.h"
#import "LauncherPreferences.h"
#import "LauncherNavigationController.h"   // localVersionList / remoteVersionList
#import "ModpackExportService.h"           // parseVersionId:
#import "ModsManagerViewController.h"
#import "ShadersManagerViewController.h"
#import "ResourcePacksManagerViewController.h"
#import "DataPacksManagerViewController.h"
#import "WorldsManagerViewController.h"
#import "ProfileSettingsViewController.h"
#import "VersionAutoMigrateViewController.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, TerraInstanceSection) {
    TerraInstanceSectionGeneral = 0,
    TerraInstanceSectionJava,
    TerraInstanceSectionGraphics,
    TerraInstanceSectionContent,
    TerraInstanceSectionFolder,
    TerraInstanceSectionServer,
    TerraInstanceSectionCount
};

static NSString *const TerraInstancesChangedNotification = @"TerraInstancesChanged";

static UILabel *TILabel(NSString *text, UIFont *font, UIColor *color, NSInteger lines) {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = lines;
    return l;
}

static UIStackView *TIStack(UILayoutConstraintAxis axis, CGFloat spacing, NSArray<UIView *> *views) {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = axis;
    s.spacing = spacing;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    return s;
}

static void TIPin(UIView *child, UIView *parent, UIEdgeInsets insets) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:child];
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:insets.top],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:insets.left],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-insets.right],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-insets.bottom],
    ]];
}

#pragma mark - Tappable row

@interface TerraInstanceRowControl : UIControl
@end

@implementation TerraInstanceRowControl
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? TerraStyle.raised : TerraStyle.surface;
}
@end

#pragma mark - Version picker

/// Simple dark list of versions (Installed / Releases / Snapshots), same sources as the legacy picker.
@interface TerraInstanceVersionPickerViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *currentVersion;
@property (nonatomic, copy) void (^onPick)(NSString *versionId);
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSArray<NSString *> *items;
@end

@implementation TerraInstanceVersionPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Game Version";
    [TerraStyle applyToViewController:self];
    self.tableView.backgroundColor = TerraStyle.background;
    self.tableView.separatorColor = TerraStyle.border;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"v"];

    self.typeControl = [[UISegmentedControl alloc] initWithItems:@[@"Installed", @"Releases", @"Snapshots"]];
    self.typeControl.selectedSegmentIndex = 0;
    self.typeControl.selectedSegmentTintColor = TerraStyle.green;
    [self.typeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateSelected];
    [self.typeControl addTarget:self action:@selector(reloadItems) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.typeControl;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = @"Search versions";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    // Start on the list that contains the current version (like the legacy picker).
    if (self.currentVersion.length && ![self ids:localVersionList type:nil containing:self.currentVersion]) {
        if ([self ids:remoteVersionList type:@"snapshot" containing:self.currentVersion]) {
            self.typeControl.selectedSegmentIndex = 2;
        } else if ([self ids:remoteVersionList type:@"release" containing:self.currentVersion]) {
            self.typeControl.selectedSegmentIndex = 1;
        }
    }
    [self reloadItems];
}

- (NSString *)idOf:(id)obj {
    if ([obj isKindOfClass:NSString.class]) return obj;
    id v = [obj isKindOfClass:NSDictionary.class] ? obj[@"id"] : nil;
    return [v isKindOfClass:NSString.class] ? v : nil;
}

- (NSArray<NSString *> *)idsIn:(NSArray *)list type:(NSString *)type {
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in list ?: @[]) {
        if (type && !([obj isKindOfClass:NSDictionary.class] && [obj[@"type"] isEqual:type])) continue;
        NSString *i = [self idOf:obj];
        if (i.length) [out addObject:i];
    }
    return out;
}

- (BOOL)ids:(NSArray *)list type:(NSString *)type containing:(NSString *)vid {
    return [[self idsIn:list type:type] containsObject:vid];
}

- (void)reloadItems {
    NSArray<NSString *> *all;
    switch (self.typeControl.selectedSegmentIndex) {
        case 1:  all = [self idsIn:remoteVersionList type:@"release"]; break;
        case 2:  all = [self idsIn:remoteVersionList type:@"snapshot"]; break;
        default: all = [self idsIn:localVersionList type:nil]; break;
    }
    NSString *q = [self.search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (q.length) {
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] %@", q]];
    }
    self.items = all;
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reloadItems];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.items.count, (NSUInteger)1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"v" forIndexPath:indexPath];
    cell.backgroundColor = TerraStyle.surface;
    cell.textLabel.font = TerraStyle.bodyFont;
    if (self.items.count == 0) {
        cell.textLabel.text = self.typeControl.selectedSegmentIndex == 0 ? @"No installed versions" : @"Version list not loaded yet";
        cell.textLabel.textColor = TerraStyle.dimText;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSString *vid = self.items[indexPath.row];
    cell.textLabel.text = vid;
    cell.textLabel.textColor = TerraStyle.text;
    cell.tintColor = TerraStyle.greenBright;
    cell.accessoryType = [vid isEqualToString:self.currentVersion] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.items.count) return;
    if (self.onPick) self.onPick(self.items[indexPath.row]);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Settings screen

@interface TerraInstanceSettingsViewController () <UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) NSMutableDictionary *profile;
@property (nonatomic, assign) TerraInstanceSection section;
@property (nonatomic, assign) NSInteger maxMemory;

// Header
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIStackView *chipStack;
@property (nonatomic, strong) UILabel *pathLabel;

// Navigation between sections
@property (nonatomic, strong) UIView *sidebar;
@property (nonatomic, strong) NSArray<UIButton *> *sidebarRows;
@property (nonatomic, strong) UIButton *sectionMenuButton;

// Detail pane
@property (nonatomic, strong) UIScrollView *detailScroll;
@property (nonatomic, strong) UIStackView *detailStack;

@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *regularConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *compactConstraints;
@property (nonatomic, assign) NSInteger layoutMode;   // 0 = not yet, 1 = regular, 2 = compact

// Live controls
@property (nonatomic, strong) UILabel *memoryValueLabel;
@property (nonatomic, strong) UITextView *jvmTextView;
@property (nonatomic, strong) UITextField *serverField;
@end

@implementation TerraInstanceSettingsViewController

#pragma mark Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    [TerraStyle applyToViewController:self];

    long long totalMB = (long long)(NSProcessInfo.processInfo.physicalMemory / (1024 * 1024));
    self.maxMemory = MAX((NSInteger)(totalMB * 0.8), 1024);   // same ceiling as the legacy screen

    [self reloadProfile];
    [self buildHeader];
    [self buildNavigation];
    [self buildDetailPane];
    [self buildConstraints];
    [self showSection:TerraInstanceSectionGeneral];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TerraStyle applyToViewController:self];
    // Returning from the legacy screen / managers: pick up whatever they changed.
    if (self.layoutMode != 0) {
        [self reloadProfile];
        [self refreshHeader];
        [self showSection:self.section];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    // Commit fields still being edited (Done dismisses without resigning first responder).
    [self.view endEditing:YES];
    [super viewWillDisappear:animated];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    NSInteger mode = self.view.bounds.size.width < 640 ? 2 : 1;
    if (mode == self.layoutMode) return;
    self.layoutMode = mode;
    BOOL compact = mode == 2;
    [NSLayoutConstraint deactivateConstraints:compact ? self.regularConstraints : self.compactConstraints];
    [NSLayoutConstraint activateConstraints:compact ? self.compactConstraints : self.regularConstraints];
    self.sidebar.hidden = compact;
    self.sectionMenuButton.hidden = !compact;
}

#pragma mark Data

- (void)reloadProfile {
    if (self.profileName.length == 0) {
        self.profileName = PLProfiles.current.selectedProfileName ?: @"";
    }
    NSMutableDictionary *p = [PLProfiles.current.profiles[self.profileName] mutableCopy];
    if (!p) {
        p = [NSMutableDictionary dictionary];
        p[@"name"] = self.profileName;
    }
    self.profile = p;
}

/// Read-modify-write of this profile's entry (same pattern as legacy -saveSettings).
- (void)commit:(void (^)(NSMutableDictionary *p))mutate {
    NSString *key = self.profileName;
    if (key.length == 0) return;
    NSMutableDictionary *existing = [PLProfiles.current.profiles[key] mutableCopy];
    if (!existing) {
        existing = [NSMutableDictionary dictionary];
        existing[@"name"] = key;
    }
    mutate(existing);
    PLProfiles.current.profiles[key] = existing;
    [PLProfiles.current save];
    self.profile = [existing mutableCopy];
    [self refreshHeader];
    [self postChanged];
}

- (void)postChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:TerraInstancesChangedNotification object:nil];
}

- (NSString *)stringValue:(NSString *)key {
    id v = self.profile[key];
    return [v isKindOfClass:NSString.class] ? v : nil;
}

- (NSString *)displayName {
    NSString *n = [self stringValue:@"name"];
    return n.length ? n : (self.profileName ?: @"");
}

- (NSString *)versionId {
    return [self stringValue:@"lastVersionId"] ?: @"";
}

- (NSDictionary *)parsedVersion {
    NSString *vid = self.versionId;
    return vid.length ? ([ModpackExportService parseVersionId:vid] ?: @{}) : @{};
}

- (NSString *)minecraftVersion {
    NSString *mc = self.parsedVersion[@"minecraft"];
    return mc.length ? mc : self.versionId;
}

- (NSString *)loaderName {
    NSString *loader = [self.parsedVersion[@"loader"] lowercaseString] ?: @"";
    NSString *lower = self.versionId.lowercaseString;
    if (loader.length == 0) {
        if ([lower containsString:@"neoforge"]) loader = @"neoforge";
        else if ([lower containsString:@"forge"]) loader = @"forge";
        else if ([lower containsString:@"fabric"]) loader = @"fabric";
        else if ([lower containsString:@"quilt"]) loader = @"quilt";
        else if ([lower containsString:@"optifine"]) loader = @"optifine";
    }
    NSDictionary *names = @{@"fabric": @"Fabric", @"forge": @"Forge", @"neoforge": @"NeoForge",
                            @"quilt": @"Quilt", @"optifine": @"OptiFine"};
    return names[loader] ?: @"Vanilla";
}

- (UIColor *)loaderColor:(NSString *)loader {
    if ([loader isEqualToString:@"Fabric"])   return [UIColor colorWithRed:0.86 green:0.75 blue:0.55 alpha:1];
    if ([loader isEqualToString:@"Forge"])    return [UIColor colorWithRed:0.93 green:0.55 blue:0.30 alpha:1];
    if ([loader isEqualToString:@"NeoForge"]) return [UIColor colorWithRed:0.95 green:0.65 blue:0.35 alpha:1];
    if ([loader isEqualToString:@"Quilt"])    return [UIColor colorWithRed:0.70 green:0.55 blue:0.95 alpha:1];
    if ([loader isEqualToString:@"OptiFine"]) return [UIColor colorWithRed:0.45 green:0.70 blue:0.95 alpha:1];
    return TerraStyle.greenBright;
}

- (BOOL)isSelected {
    return [PLProfiles.current.selectedProfileName isEqualToString:self.profileName];
}

- (NSString *)gameDirAbsolute {
    NSString *dir = amePCLVersionGameDirAbsolute(self.profile, nil);
    if (dir.length == 0) {
        const char *env = getenv("POJAV_GAME_DIR");
        dir = env ? @(env) : NSHomeDirectory();
    }
    return dir;
}

- (NSString *)shortPath:(NSString *)path {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length && [path hasPrefix:docs]) {
        return [@"Documents" stringByAppendingString:[path substringFromIndex:docs.length]];
    }
    return path;
}

/// Same rule as the legacy -isCurrentProfileModernVersion (Graphics API exists on 1.21.8+ / 26.x).
- (BOOL)supportsGraphicsApi {
    NSString *mc = self.minecraftVersion;
    if ([mc hasPrefix:@"26."] || [mc hasPrefix:@"26w"]) return YES;
    if ([mc hasPrefix:@"1.21."]) return [[mc substringFromIndex:5] integerValue] >= 8;
    return NO;
}

/// Legacy -loadSettings: NSDictionary {majorVersion} or string; default "0" (Auto).
- (NSString *)javaVersionValue {
    id raw = self.profile[@"javaVersion"];
    if ([raw isKindOfClass:NSDictionary.class]) {
        id major = raw[@"majorVersion"];
        return major ? [major description] : @"0";
    }
    return ([raw isKindOfClass:NSString.class] && [raw length]) ? raw : @"0";
}

- (NSInteger)memoryOverride {
    id raw = self.profile[@"allocatedMemory"];
    return [raw respondsToSelector:@selector(integerValue)] ? [raw integerValue] : 0;
}

- (NSInteger)memoryValue {
    NSInteger mem = self.memoryOverride;
    if (mem <= 0) mem = MIN(self.maxMemory / 2, 2048);
    return MIN(mem, self.maxMemory);
}

- (NSString *)rendererName:(NSString *)key {
    NSArray *keys = getRendererKeys(NO);
    NSArray *names = getRendererNames(NO);
    NSUInteger idx = [keys indexOfObject:key ?: @""];
    return (idx != NSNotFound && idx < names.count) ? names[idx] : (key ?: @"Auto");
}

- (NSString *)graphicsApiValue {
    NSString *v = [self stringValue:@"graphicsApi"];
    return v.length ? v : @"default";
}

#pragma mark Header

- (void)buildHeader {
    UIView *card = [TerraStyle cardView];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    self.header = card;
    [self.view addSubview:card];

    UIView *iconWell = [UIView new];
    iconWell.backgroundColor = TerraStyle.raised;
    iconWell.layer.cornerRadius = 6;
    iconWell.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *grass = [TerraStyle grassBlockOfSize:36];
    [iconWell addSubview:grass];
    [NSLayoutConstraint activateConstraints:@[
        [iconWell.widthAnchor constraintEqualToConstant:56],
        [iconWell.heightAnchor constraintEqualToConstant:56],
        [grass.centerXAnchor constraintEqualToAnchor:iconWell.centerXAnchor],
        [grass.centerYAnchor constraintEqualToAnchor:iconWell.centerYAnchor],
    ]];

    self.nameLabel = TILabel(@"", TerraStyle.titleFont, TerraStyle.text, 1);
    self.versionLabel = TILabel(@"", TerraStyle.bodyFont, TerraStyle.dimText, 1);
    self.chipStack = TIStack(UILayoutConstraintAxisHorizontal, 6, @[]);
    UIStackView *meta = TIStack(UILayoutConstraintAxisHorizontal, 8, @[self.versionLabel, self.chipStack, [UIView new]]);
    meta.alignment = UIStackViewAlignmentCenter;
    self.pathLabel = TILabel(@"", [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular], TerraStyle.dimText, 1);
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    UIStackView *texts = TIStack(UILayoutConstraintAxisVertical, 4, @[self.nameLabel, meta, self.pathLabel]);
    UIStackView *row = TIStack(UILayoutConstraintAxisHorizontal, 14, @[iconWell, texts]);
    row.alignment = UIStackViewAlignmentCenter;
    TIPin(row, card, UIEdgeInsetsMake(12, 12, 12, 16));
    [self refreshHeader];
}

- (void)refreshHeader {
    if (!self.header) return;
    NSString *name = self.displayName;
    self.title = name;
    self.nameLabel.text = name;
    NSString *mc = self.minecraftVersion;
    self.versionLabel.text = mc.length ? [NSString stringWithFormat:@"Minecraft %@", mc] : @"No version set";

    for (UIView *v in self.chipStack.arrangedSubviews) [v removeFromSuperview];
    NSString *loader = self.loaderName;
    [self.chipStack addArrangedSubview:[TerraStyle chipWithText:loader color:[self loaderColor:loader]]];
    if (self.isSelected) {
        [self.chipStack addArrangedSubview:[TerraStyle chipWithText:@"Selected" color:TerraStyle.greenBright]];
    }
    self.pathLabel.text = [self shortPath:self.gameDirAbsolute];
}

#pragma mark Section navigation

- (NSArray<NSString *> *)sectionTitles {
    return @[@"General", @"Java & Memory", @"Graphics", @"Content", @"Game Folder", @"Server"];
}

- (NSArray<NSString *> *)sectionSymbols {
    return @[@"slider.horizontal.3", @"cup.and.saucer", @"display", @"shippingbox", @"folder", @"network"];
}

- (void)buildNavigation {
    // Sidebar (regular widths)
    UIView *sidebar = [TerraStyle cardView];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:sidebar];
    self.sidebar = sidebar;

    NSMutableArray *rows = [NSMutableArray array];
    __weak typeof(self) ws = self;
    for (NSInteger i = 0; i < TerraInstanceSectionCount; i++) {
        UIButton *row = [TerraStyle sidebarRowWithTitle:self.sectionTitles[i] symbol:self.sectionSymbols[i]];
        [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            [ws showSection:(TerraInstanceSection)i];
        }] forControlEvents:UIControlEventTouchUpInside];
        [rows addObject:row];
    }
    self.sidebarRows = rows;
    UIStackView *list = TIStack(UILayoutConstraintAxisVertical, 2, rows);
    [sidebar addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:8],
        [list.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:6],
        [list.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-6],
        [list.bottomAnchor constraintLessThanOrEqualToAnchor:sidebar.bottomAnchor constant:-8],
    ]];

    // Pull-down section menu (narrow widths)
    self.sectionMenuButton = [self menuButtonWithTitle:@"" menu:nil];
    self.sectionMenuButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionMenuButton.hidden = YES;
    [self.view addSubview:self.sectionMenuButton];
}

- (void)updateSectionMenu {
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) ws = self;
    for (NSInteger i = 0; i < TerraInstanceSectionCount; i++) {
        UIAction *a = [UIAction actionWithTitle:self.sectionTitles[i]
                                          image:[UIImage systemImageNamed:self.sectionSymbols[i]]
                                     identifier:nil
                                        handler:^(__kindof UIAction *x) { [ws showSection:(TerraInstanceSection)i]; }];
        a.state = i == self.section ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    self.sectionMenuButton.menu = [UIMenu menuWithChildren:actions];
    UIButtonConfiguration *c = self.sectionMenuButton.configuration;
    c.title = self.sectionTitles[self.section];
    self.sectionMenuButton.configuration = c;
}

- (void)buildDetailPane {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:scroll];
    self.detailScroll = scroll;

    UIStackView *stack = TIStack(UILayoutConstraintAxisVertical, 12, @[]);
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    self.detailStack = stack;
}

- (void)buildConstraints {
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [self.header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [self.header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.detailScroll.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor],
        [self.detailScroll.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
    ]];
    self.regularConstraints = @[
        [self.sidebar.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:16],
        [self.sidebar.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor],
        [self.sidebar.widthAnchor constraintEqualToConstant:220],
        [self.sidebar.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-16],
        [self.detailScroll.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:16],
        [self.detailScroll.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:16],
    ];
    self.compactConstraints = @[
        [self.sectionMenuButton.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:12],
        [self.sectionMenuButton.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor],
        [self.sectionMenuButton.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor],
        [self.detailScroll.topAnchor constraintEqualToAnchor:self.sectionMenuButton.bottomAnchor constant:12],
        [self.detailScroll.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor],
    ];
}

- (void)showSection:(TerraInstanceSection)section {
    [self.view endEditing:YES];   // commit pending text before tearing the pane down
    self.section = section;
    for (NSInteger i = 0; i < (NSInteger)self.sidebarRows.count; i++) {
        [TerraStyle setSidebarRow:self.sidebarRows[i] selected:i == section];
    }
    [self updateSectionMenu];

    for (UIView *v in self.detailStack.arrangedSubviews) [v removeFromSuperview];
    self.memoryValueLabel = nil;
    self.jvmTextView = nil;
    self.serverField = nil;

    switch (section) {
        case TerraInstanceSectionGeneral:  [self buildGeneral]; break;
        case TerraInstanceSectionJava:     [self buildJava]; break;
        case TerraInstanceSectionGraphics: [self buildGraphics]; break;
        case TerraInstanceSectionContent:  [self buildContent]; break;
        case TerraInstanceSectionFolder:   [self buildFolder]; break;
        case TerraInstanceSectionServer:   [self buildServer]; break;
        default: break;
    }
    [self.detailScroll setContentOffset:CGPointZero animated:NO];
}

#pragma mark Building blocks

- (void)addSectionTitle:(NSString *)text {
    UILabel *l = [TerraStyle sectionLabel:text];
    UIStackView *wrap = TIStack(UILayoutConstraintAxisVertical, 0, @[l]);
    wrap.layoutMarginsRelativeArrangement = YES;
    wrap.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(4, 2, 0, 0);
    [self.detailStack addArrangedSubview:wrap];
}

/// Card: title + one short secondary line, optional trailing accessory, optional full-width body.
- (UIView *)cardTitle:(NSString *)title detail:(NSString *)detail accessory:(UIView *)accessory body:(UIView *)body {
    UIView *card = [TerraStyle cardView];
    UILabel *t = TILabel(title, TerraStyle.headlineFont, TerraStyle.text, 1);
    NSMutableArray *textViews = [NSMutableArray arrayWithObject:t];
    if (detail.length) [textViews addObject:TILabel(detail, TerraStyle.captionFont, TerraStyle.dimText, 0)];
    UIStackView *texts = TIStack(UILayoutConstraintAxisVertical, 3, textViews);
    [texts setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *top = TIStack(UILayoutConstraintAxisHorizontal, 12, @[texts]);
    top.alignment = UIStackViewAlignmentCenter;
    if (accessory) {
        [accessory setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [accessory setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [top addArrangedSubview:accessory];
    }
    UIStackView *v = TIStack(UILayoutConstraintAxisVertical, 12, @[top]);
    if (body) [v addArrangedSubview:body];
    TIPin(v, card, UIEdgeInsetsMake(14, 16, 14, 16));
    return card;
}

/// Tappable card row: symbol, title, short detail, trailing value + chevron.
- (UIView *)rowWithSymbol:(NSString *)symbol title:(NSString *)title detail:(NSString *)detail
                    value:(NSString *)value handler:(void (^)(void))handler {
    TerraInstanceRowControl *row = [TerraInstanceRowControl new];
    row.backgroundColor = TerraStyle.surface;
    row.layer.cornerRadius = 6;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    row.layer.borderWidth = 1;
    row.layer.borderColor = TerraStyle.border.CGColor;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = TerraStyle.greenBright;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.widthAnchor constraintEqualToConstant:24].active = YES;

    UILabel *t = TILabel(title, TerraStyle.headlineFont, TerraStyle.text, 1);
    NSMutableArray *textViews = [NSMutableArray arrayWithObject:t];
    if (detail.length) [textViews addObject:TILabel(detail, TerraStyle.captionFont, TerraStyle.dimText, 1)];
    UIStackView *texts = TIStack(UILayoutConstraintAxisVertical, 2, textViews);

    UILabel *val = TILabel(value ?: @"", TerraStyle.bodyFont, TerraStyle.dimText, 1);
    [val setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [val setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]]];
    chev.tintColor = TerraStyle.dimText;
    [chev setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *h = TIStack(UILayoutConstraintAxisHorizontal, 12, @[icon, texts, val, chev]);
    h.alignment = UIStackViewAlignmentCenter;
    h.userInteractionEnabled = NO;
    TIPin(h, row, UIEdgeInsetsMake(14, 16, 14, 16));
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
    [row addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (handler) handler(); }]
  forControlEvents:UIControlEventTouchUpInside];
    return row;
}

- (UIButton *)menuButtonWithTitle:(NSString *)title menu:(UIMenu *)menu {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.baseBackgroundColor = TerraStyle.raised;
    c.baseForegroundColor = TerraStyle.text;
    c.title = title;
    c.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    c.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold];
    c.imagePlacement = NSDirectionalRectEdgeTrailing;
    c.imagePadding = 8;
    c.cornerStyle = UIButtonConfigurationCornerStyleSmall;
    c.contentInsets = NSDirectionalEdgeInsetsMake(9, 12, 9, 12);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *in) {
        NSMutableDictionary *m = [in mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.menu = menu;
    b.showsMenuAsPrimaryAction = YES;
    return b;
}

- (UIButton *)smallButton:(NSString *)title primary:(BOOL)primary handler:(void (^)(void))handler {
    UIButton *b = [TerraStyle blockButtonWithTitle:title symbol:nil primary:primary];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (handler) handler(); }]
forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UISegmentedControl *)segmentedWithItems:(NSArray<NSString *> *)items selected:(NSInteger)selected {
    UISegmentedControl *s = [[UISegmentedControl alloc] initWithItems:items];
    s.selectedSegmentIndex = selected;
    s.backgroundColor = TerraStyle.raised;
    s.selectedSegmentTintColor = TerraStyle.green;
    [s setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor,
                                NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]}
                     forState:UIControlStateSelected];
    [s setTitleTextAttributes:@{NSForegroundColorAttributeName: TerraStyle.dimText,
                                NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}
                     forState:UIControlStateNormal];
    [s.heightAnchor constraintGreaterThanOrEqualToConstant:34].active = YES;
    return s;
}

- (void)styleInput:(UIView *)v {
    v.backgroundColor = TerraStyle.raised;
    v.layer.cornerRadius = 6;
    v.layer.borderWidth = 1;
    v.layer.borderColor = TerraStyle.border.CGColor;
    v.tintColor = TerraStyle.greenBright;
}

- (void)promptWithTitle:(NSString *)title text:(NSString *)text placeholder:(NSString *)placeholder
               onCommit:(void (^)(NSString *value))onCommit {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = text;
        f.placeholder = placeholder;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (onCommit) onCommit(v ?: @"");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)alertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pushOrPresent:(UIViewController *)vc {
    if (self.navigationController) {
        [self.navigationController pushViewController:vc animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nav animated:YES completion:nil];
    }
}

#pragma mark 1. General

- (void)buildGeneral {
    __weak typeof(self) ws = self;
    [self addSectionTitle:@"Installation"];
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Name" detail:self.displayName
              accessory:[self smallButton:@"Rename" primary:NO handler:^{ [ws editName]; }] body:nil]];

    NSString *vid = self.versionId;
    NSString *versionDetail = vid.length ? vid : @"Not set";
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Game version" detail:versionDetail
              accessory:[self smallButton:@"Change…" primary:NO handler:^{ [ws changeVersion]; }] body:nil]];

    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Mod loader" detail:@"Detected from the version." accessory:
            [TerraStyle chipWithText:self.loaderName color:[self loaderColor:self.loaderName]] body:nil]];
}

/// Mirrors legacy -actionDone rename semantics: conflict check, move the key, keep selection.
- (void)editName {
    __weak typeof(self) ws = self;
    [self promptWithTitle:@"Rename installation" text:self.displayName placeholder:@"Installation name"
                 onCommit:^(NSString *value) { [ws renameTo:value]; }];
}

- (void)renameTo:(NSString *)newName {
    NSString *oldKey = self.profileName;
    if (newName.length == 0 || oldKey.length == 0) return;
    if ([newName isEqualToString:oldKey]) {
        [self commit:^(NSMutableDictionary *p) { p[@"name"] = newName; }];
        [self showSection:self.section];
        return;
    }
    PLProfiles *profiles = PLProfiles.current;
    if (profiles.profiles[newName]) {
        [self alertTitle:@"Name already used" message:[NSString stringWithFormat:@"An installation named “%@” already exists.", newName]];
        return;
    }
    NSMutableDictionary *existing = [profiles.profiles[oldKey] mutableCopy] ?: [self.profile mutableCopy];
    existing[@"name"] = newName;
    [profiles.profiles removeObjectForKey:oldKey];
    profiles.profiles[newName] = existing;
    if ([profiles.selectedProfileName isEqualToString:oldKey]) {
        profiles.selectedProfileName = newName;   // saves + posts SelectedProfileChanged
    }
    [profiles save];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SelectedProfileChanged" object:newName];

    self.profileName = newName;
    self.profile = [existing mutableCopy];
    [self refreshHeader];
    [self postChanged];
    [self showSection:self.section];
}

- (void)changeVersion {
    TerraInstanceVersionPickerViewController *picker = [[TerraInstanceVersionPickerViewController alloc] initWithStyle:UITableViewStylePlain];
    picker.currentVersion = self.versionId;
    __weak typeof(self) ws = self;
    picker.onPick = ^(NSString *versionId) {
        [ws commit:^(NSMutableDictionary *p) { p[@"lastVersionId"] = versionId; }];
    };
    [self pushOrPresent:picker];
}

#pragma mark 2. Java & Memory

- (void)buildJava {
    __weak typeof(self) ws = self;
    [self addSectionTitle:@"Java"];

    // Java version: Auto ("0") + every installed runtime, numeric order (legacy -showJavaVersionSelector)
    NSMutableArray<NSString *> *versions = [[ameJavaHomesIncludingBundled() allKeys] mutableCopy] ?: [NSMutableArray array];
    [versions removeObject:@"0"];
    [versions sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [@(a.integerValue) compare:@(b.integerValue)];
    }];
    [versions insertObject:@"0" atIndex:0];
    NSString *current = self.javaVersionValue;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSString *ver in versions) {
        NSString *name = [ver isEqualToString:@"0"] ? @"Auto" : [NSString stringWithFormat:@"Java %@", ver];
        UIAction *a = [UIAction actionWithTitle:name image:nil identifier:nil handler:^(__kindof UIAction *x) {
            [ws commit:^(NSMutableDictionary *p) { p[@"javaVersion"] = ver; }];
            [ws showSection:TerraInstanceSectionJava];
        }];
        a.state = [ver isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    NSString *currentName = [current isEqualToString:@"0"] ? @"Auto" : [NSString stringWithFormat:@"Java %@", current];
    UIButton *javaButton = [self menuButtonWithTitle:currentName menu:[UIMenu menuWithChildren:actions]];
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Java version" detail:@"Auto picks the right runtime for this Minecraft version."
              accessory:javaButton body:nil]];

    // Memory (profile key allocatedMemory, MB)
    [self addSectionTitle:@"Memory"];
    long long deviceMB = (long long)(NSProcessInfo.processInfo.physicalMemory / (1024 * 1024));
    UILabel *value = TILabel([NSString stringWithFormat:@"%ld MB", (long)self.memoryValue],
                             [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightBold], TerraStyle.text, 1);
    self.memoryValueLabel = value;

    UISlider *slider = [UISlider new];
    slider.minimumValue = 512;
    slider.maximumValue = MAX(self.maxMemory, 1024);
    slider.value = self.memoryValue;
    slider.minimumTrackTintColor = TerraStyle.green;
    slider.maximumTrackTintColor = TerraStyle.raised;
    __weak UISlider *wslider = slider;
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        ws.memoryValueLabel.text = [NSString stringWithFormat:@"%ld MB", (long)[ws snappedMemory:wslider.value]];
    }] forControlEvents:UIControlEventValueChanged];
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        NSInteger mb = [ws snappedMemory:wslider.value];
        wslider.value = mb;
        if (mb == ws.memoryOverride) return;
        [ws commit:^(NSMutableDictionary *p) { p[@"allocatedMemory"] = @(mb); }];
        dispatch_async(dispatch_get_main_queue(), ^{ [ws showSection:TerraInstanceSectionJava]; });
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    UIView *memBody = slider;
    if (self.memoryOverride > 0) {
        UIButton *reset = [self smallButton:@"Use default" primary:NO handler:^{
            [ws commit:^(NSMutableDictionary *p) { [p removeObjectForKey:@"allocatedMemory"]; }];
            [ws showSection:TerraInstanceSectionJava];
        }];
        UIStackView *s = TIStack(UILayoutConstraintAxisHorizontal, 12, @[slider, reset]);
        s.alignment = UIStackViewAlignmentCenter;
        memBody = s;
    }
    NSString *memDetail = [NSString stringWithFormat:@"Device RAM %.1f GB · up to %ld MB%@",
                           deviceMB / 1024.0, (long)self.maxMemory,
                           self.memoryOverride > 0 ? @"" : @" · launcher default"];
    [self.detailStack addArrangedSubview:[self cardTitle:@"Memory allocation" detail:memDetail accessory:value body:memBody]];

    // JVM arguments (profile key javaArgs; empty ⇒ removed ⇒ global java.java_args)
    [self addSectionTitle:@"JVM arguments"];
    UITextView *tv = [UITextView new];
    tv.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    tv.textColor = TerraStyle.text;
    tv.autocorrectionType = UITextAutocorrectionTypeNo;
    tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tv.smartQuotesType = UITextSmartQuotesTypeNo;
    tv.smartDashesType = UITextSmartDashesTypeNo;
    tv.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    tv.text = [self stringValue:@"javaArgs"] ?: @"";
    tv.delegate = self;
    [self styleInput:tv];
    [tv.heightAnchor constraintEqualToConstant:96].active = YES;
    self.jvmTextView = tv;

    UIButton *save = [self smallButton:@"Save" primary:YES handler:^{
        [ws saveJavaArgs:ws.jvmTextView.text];
        dispatch_async(dispatch_get_main_queue(), ^{ [ws showSection:TerraInstanceSectionJava]; });
    }];
    UIButton *clear = [TerraStyle dangerButtonWithTitle:@"Clear" symbol:nil];
    clear.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [clear addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [ws confirmClearJavaArgs]; }]
    forControlEvents:UIControlEventTouchUpInside];
    clear.enabled = [self stringValue:@"javaArgs"].length > 0;
    UIStackView *buttons = TIStack(UILayoutConstraintAxisHorizontal, 10, @[[UIView new], clear, save]);
    UIStackView *body = TIStack(UILayoutConstraintAxisVertical, 10, @[tv, buttons]);
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Arguments" detail:@"Leave empty to use the launcher-wide arguments." accessory:nil body:body]];
}

- (NSInteger)snappedMemory:(float)raw {
    NSInteger mb = (NSInteger)(lroundf(raw / 256.0f) * 256);
    return MIN(MAX(mb, 512), self.maxMemory);
}

- (void)saveJavaArgs:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if ([trimmed isEqualToString:@"(default)"]) trimmed = @"";
    NSString *old = [self stringValue:@"javaArgs"] ?: @"";
    if ([trimmed isEqualToString:old]) return;
    [self commit:^(NSMutableDictionary *p) {
        if (trimmed.length > 0) p[@"javaArgs"] = trimmed;
        else [p removeObjectForKey:@"javaArgs"];
    }];
}

- (void)confirmClearJavaArgs {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Clear JVM arguments?"
                                                               message:@"This installation will use the launcher-wide arguments."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        ws.jvmTextView.delegate = nil;
        [ws saveJavaArgs:@""];
        [ws showSection:TerraInstanceSectionJava];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (textView == self.jvmTextView) [self saveJavaArgs:textView.text];
}

#pragma mark 3. Graphics

- (void)buildGraphics {
    __weak typeof(self) ws = self;
    [self addSectionTitle:@"Rendering"];

    // Renderer: "(default)" ⇒ remove the profile key ⇒ PLProfiles falls back to video.renderer
    NSArray<NSString *> *keys = getRendererKeys(YES);
    NSArray<NSString *> *names = getRendererNames(YES);
    NSString *override = [self stringValue:@"renderer"];
    NSString *globalKey = getPrefObject(@"video.renderer");
    NSString *globalName = [self rendererName:[globalKey isKindOfClass:NSString.class] ? globalKey : @"auto"];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        BOOL isDefault = [key isEqualToString:@"(default)"];
        NSString *title = isDefault ? [NSString stringWithFormat:@"Global default (%@)", globalName]
                                    : (i < names.count ? names[i] : key);
        UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction *x) {
            [ws commit:^(NSMutableDictionary *p) {
                if (isDefault) [p removeObjectForKey:@"renderer"];
                else p[@"renderer"] = key;
            }];
            [ws showSection:TerraInstanceSectionGraphics];
        }];
        BOOL on = isDefault ? override.length == 0 : [key isEqualToString:override];
        a.state = on ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:a];
    }
    NSString *currentTitle = override.length ? [self rendererName:override] : @"Global default";
    UIButton *rendererButton = [self menuButtonWithTitle:currentTitle menu:[UIMenu menuWithChildren:actions]];
    NSString *detail = override.length ? @"Overrides the launcher-wide renderer for this installation."
                                       : [NSString stringWithFormat:@"Using the launcher-wide renderer: %@.", globalName];
    [self.detailStack addArrangedSubview:[self cardTitle:@"Renderer" detail:detail accessory:rendererButton body:nil]];

    // Graphics API (MC 1.21.8+ / 26.x only, same gate as the legacy screen)
    if (self.supportsGraphicsApi) {
        NSArray<NSString *> *apiKeys = @[@"default", @"prefer_vulkan", @"prefer_opengl"];
        NSUInteger idx = [apiKeys indexOfObject:self.graphicsApiValue];
        UISegmentedControl *seg = [self segmentedWithItems:@[@"Default", @"Vulkan", @"OpenGL"]
                                                  selected:idx == NSNotFound ? 0 : (NSInteger)idx];
        __weak UISegmentedControl *wseg = seg;
        [seg addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
            NSString *k = apiKeys[(NSUInteger)MAX(wseg.selectedSegmentIndex, 0)];
            [ws commit:^(NSMutableDictionary *p) { p[@"graphicsApi"] = k; }];
        }] forControlEvents:UIControlEventValueChanged];
        [self.detailStack addArrangedSubview:
            [self cardTitle:@"Graphics API" detail:@"Preferred in-game backend (Minecraft 1.21.8 and newer)." accessory:nil body:seg]];
    }
}

#pragma mark 4. Content

- (NSInteger)countIn:(NSString *)subdir directoriesOnly:(BOOL)dirsOnly suffixes:(NSArray<NSString *> *)suffixes {
    NSString *dir = [self.gameDirAbsolute stringByAppendingPathComponent:subdir];
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSInteger n = 0;
    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        if (suffixes) {
            BOOL match = NO;
            for (NSString *s in suffixes) if ([name.lowercaseString hasSuffix:s]) { match = YES; break; }
            if (!match) continue;
        }
        if (dirsOnly) {
            BOOL isDir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:name] isDirectory:&isDir];
            if (!isDir) continue;
        }
        n++;
    }
    return n;
}

- (NSString *)countText:(NSInteger)n {
    return n > 0 ? [NSString stringWithFormat:@"%ld", (long)n] : @"";
}

- (void)buildContent {
    __weak typeof(self) ws = self;
    NSString *name = self.profileName;
    [self addSectionTitle:@"Content"];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"puzzlepiece.extension" title:@"Mods" detail:@"Browse, enable and update mods"
                      value:[self countText:[self countIn:@"mods" directoriesOnly:NO suffixes:@[@".jar", @".disabled"]]]
                    handler:^{
        UIViewController *vc = nil;
        Class cls = NSClassFromString(@"TerraModsManagerViewController");
        if (cls && [cls isSubclassOfClass:UIViewController.class]) {
            vc = [cls new];
            if ([vc respondsToSelector:NSSelectorFromString(@"setProfileName:")]) [vc setValue:name forKey:@"profileName"];
        } else {
            ModsManagerViewController *m = [ModsManagerViewController new];
            m.profileName = name;
            vc = m;
        }
        [ws pushOrPresent:vc];
    }]];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"sparkles" title:@"Shader Packs" detail:@"Requires Iris or OptiFine"
                      value:[self countText:[self countIn:@"shaderpacks" directoriesOnly:NO suffixes:nil]]
                    handler:^{
        ShadersManagerViewController *vc = [ShadersManagerViewController new];
        vc.profileName = name;
        vc.initialMode = ShadersManagerModeLocal;
        [ws pushOrPresent:vc];
    }]];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"paintpalette" title:@"Resource Packs" detail:@"Textures, sounds and fonts"
                      value:[self countText:[self countIn:@"resourcepacks" directoriesOnly:NO suffixes:nil]]
                    handler:^{
        ResourcePacksManagerViewController *vc = [ResourcePacksManagerViewController new];
        vc.profileName = name;
        vc.initialMode = ResourcePacksManagerModeLocal;
        [ws pushOrPresent:vc];
    }]];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"doc.badge.gearshape" title:@"Data Packs" detail:@"Installed per world"
                      value:nil
                    handler:^{
        DataPacksManagerViewController *vc = [DataPacksManagerViewController new];
        vc.profileName = name;
        [ws pushOrPresent:vc];
    }]];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"globe.americas" title:@"Worlds" detail:@"Saves for this installation"
                      value:[self countText:[self countIn:@"saves" directoriesOnly:YES suffixes:nil]]
                    handler:^{
        WorldsManagerViewController *vc = [WorldsManagerViewController new];
        vc.profileName = name;
        [ws pushOrPresent:vc];
    }]];
}

#pragma mark 5. Game Folder

- (BOOL)resolvedIsolation {
    id raw = self.profile[@"versionIsolation"];
    if (raw) return [raw boolValue];
    NSString *vid = self.versionId;
    return amePCLVersionIsolationForProfile(self.profile, vid.length ? vid : nil);
}

- (void)buildFolder {
    __weak typeof(self) ws = self;
    [self addSectionTitle:@"Version isolation"];

    AmeVIExplicitState state = ameVIExplicitStateForProfile(self.profile);
    NSInteger idx = state == AmeVIExplicitStateIsolated ? 1 : (state == AmeVIExplicitStateShared ? 2 : 0);
    UISegmentedControl *seg = [self segmentedWithItems:@[@"Auto", @"Isolated", @"Shared"] selected:idx];
    __weak UISegmentedControl *wseg = seg;
    [seg addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        AmeVIExplicitState st = AmeVIExplicitStateAuto;
        if (wseg.selectedSegmentIndex == 1) st = AmeVIExplicitStateIsolated;
        else if (wseg.selectedSegmentIndex == 2) st = AmeVIExplicitStateShared;
        [ws setIsolationState:st];
    }] forControlEvents:UIControlEventValueChanged];

    BOOL isolated = self.resolvedIsolation;
    NSString *effect = isolated ? @"Mods, worlds and config live in this version's own folder."
                                : @"Mods, worlds and config are shared with other versions.";
    if (state == AmeVIExplicitStateAuto) effect = [@"Auto: " stringByAppendingString:effect];
    [self.detailStack addArrangedSubview:[self cardTitle:@"Isolation" detail:effect accessory:nil body:seg]];

    [self addSectionTitle:@"Location"];
    NSString *gameDir = [self stringValue:@"gameDir"] ?: @".";
    UILabel *path = TILabel([self shortPath:self.gameDirAbsolute],
                            [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular], TerraStyle.text, 0);
    path.lineBreakMode = NSLineBreakByCharWrapping;
    NSString *dirDetail = [gameDir isEqualToString:@"."] ? @"Default location" : [NSString stringWithFormat:@"Custom: %@", gameDir];
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Game directory" detail:dirDetail
              accessory:[self smallButton:@"Edit" primary:NO handler:^{ [ws editGameDir]; }] body:path]];

    [self.detailStack addArrangedSubview:
        [self rowWithSymbol:@"wrench.and.screwdriver" title:@"Advanced folder options…"
                     detail:@"Migration tools and isolation wizard" value:nil handler:^{
        ProfileSettingsViewController *legacy = [ProfileSettingsViewController new];
        legacy.profileName = ws.profileName;
        [ws pushOrPresent:legacy];
    }]];
}

- (void)setIsolationState:(AmeVIExplicitState)state {
    AmeVIExplicitState prev = ameVIExplicitStateForProfile(self.profile);
    [self commit:^(NSMutableDictionary *p) { ameVISetExplicitStateForProfile(p, state); }];
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [ws showSection:TerraInstanceSectionFolder];
        // Same follow-up as the legacy screen: offer migration only on a non-isolated → isolated switch.
        if (state == AmeVIExplicitStateIsolated && prev != AmeVIExplicitStateIsolated) {
            [ws promptMigration];
        }
    });
}

- (void)promptMigration {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Move existing files?"
                                                               message:@"Move mods and worlds into this version's folder."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Migrate…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        dispatch_async(dispatch_get_main_queue(), ^{
            VersionAutoMigrateViewController *vc = [VersionAutoMigrateViewController new];
            vc.profile = ws.profile;
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            [ws presentViewController:nav animated:YES completion:nil];
        });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

/// Legacy -editGameDir: "." = default; relative paths resolve against the instance root.
- (void)editGameDir {
    NSString *current = [self stringValue:@"gameDir"] ?: @".";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Game directory"
                                                               message:@"“.” uses the default location."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = current;
        f.placeholder = @".";
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) ws = self;
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [ws commit:^(NSMutableDictionary *p) { p[@"gameDir"] = @"."; }];
        [ws showSection:TerraInstanceSectionFolder];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (v.length == 0) v = @".";
        [ws commit:^(NSMutableDictionary *p) { p[@"gameDir"] = v; }];
        [ws showSection:TerraInstanceSectionFolder];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark 6. Server

- (void)buildServer {
    [self addSectionTitle:@"Multiplayer"];
    UITextField *f = [UITextField new];
    f.text = [PLProfiles.current serverIpForProfile:self.profileName];
    f.textColor = TerraStyle.text;
    f.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"play.example.net:25565"
        attributes:@{NSForegroundColorAttributeName: TerraStyle.dimText}];
    f.keyboardType = UIKeyboardTypeURL;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.returnKeyType = UIReturnKeyDone;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.delegate = self;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    f.leftViewMode = UITextFieldViewModeAlways;
    [self styleInput:f];
    [f.heightAnchor constraintEqualToConstant:42].active = YES;
    [f addTarget:self action:@selector(serverFieldDidEnd:) forControlEvents:UIControlEventEditingDidEnd];
    self.serverField = f;
    [self.detailStack addArrangedSubview:
        [self cardTitle:@"Auto-join server" detail:@"host or host:port — joins right after launch. Empty = off."
              accessory:nil body:f]];
}

- (void)serverFieldDidEnd:(UITextField *)field {
    NSString *v = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (self.profileName.length == 0) return;
    if ([v isEqualToString:[PLProfiles.current serverIpForProfile:self.profileName]]) return;
    [PLProfiles.current setServerIp:v forProfile:self.profileName];
    [self reloadProfile];
    [self postChanged];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
