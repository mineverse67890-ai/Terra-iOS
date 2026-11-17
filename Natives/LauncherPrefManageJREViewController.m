#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPrefManageJREViewController.h"
#import "NSFileManager+NRFileManager.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "TerraStyle.h"
#import "DownloadTaskManager.h"
#import "DownloadTaskItem.h"
#import "PLTaskStages.h"

#include <lzma.h>
#include <objc/runtime.h>

// 0 is reserved for default pickers
// INT_MAX is reserved for invalid runtimes
#define DEFAULT_JRE 0
#define INVALID_JRE INT_MAX

// https://www.gnu.org/software/tar/manual/html_node/Standard.html
typedef struct {
    char name[100];
    char mode[8];
    char unused1[8+8];
    char size[12];
    char unused2[12+8];
    char typeflag;
    char linkname[100];
    char unused3[6+2+32+32+8+8+155+12];
} TarHeader;

// redesign-download-ui Phase 4 Task 4.3：移除 WFWorkflowProgressView（私有框架），
// 运行时导入进度改由 DownloadTaskManager 统一任务驱动（rawTask = totalProgress，支持取消）
static NSString *currentImportTaskId;

#pragma mark - ★ [TERRA-STYLE] cells

/// Card background shared by both cell kinds. Rows of a grouped card overlap their 1pt
/// borders by 1pt so adjacent rows read as a single card with hairline separators.
static UIView *TerraRuntimeCardBackground(void) {
    UIView *bg = [TerraStyle cardView];
    bg.translatesAutoresizingMaskIntoConstraints = NO;
    bg.userInteractionEnabled = NO;
    return bg;
}

static UIStackView *TerraRuntimeHStack(void) {
    UIStackView *s = [UIStackView new];
    s.axis = UILayoutConstraintAxisHorizontal;
    s.alignment = UIStackViewAlignmentCenter;
    s.spacing = 6;
    return s;
}

/// "Default Java" row: tag title on the left, chosen version as a chip + chevron on the right.
@interface TerraRuntimeDefaultCell : UITableViewCell
@property(nonatomic, strong) UIView *cardBackground;
@property(nonatomic, strong) UILabel *titleTextLabel;
@property(nonatomic, strong) UILabel *valueChip;
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *valueText;
@property(nonatomic, strong) NSLayoutConstraint *bgTop;
- (void)setPositionFirst:(BOOL)first last:(BOOL)last;
@end

@implementation TerraRuntimeDefaultCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.clipsToBounds = NO;

    self.cardBackground = TerraRuntimeCardBackground();
    [self.contentView addSubview:self.cardBackground];

    self.titleTextLabel = [UILabel new];
    self.titleTextLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.titleTextLabel.textColor = TerraStyle.text;
    self.titleTextLabel.numberOfLines = 0;

    self.valueChip = [TerraStyle chipWithText:@"" color:TerraStyle.greenBright];
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold]]];
    chevron.tintColor = TerraStyle.dimText;
    [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = TerraRuntimeHStack();
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.spacing = 8;
    [row addArrangedSubview:self.titleTextLabel];
    [row addArrangedSubview:self.valueChip];
    [row addArrangedSubview:chevron];
    [row setCustomSpacing:6 afterView:self.valueChip];
    [self.contentView addSubview:row];

    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    self.bgTop = [self.cardBackground.topAnchor constraintEqualToAnchor:self.contentView.topAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.bgTop,
        [self.cardBackground.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.cardBackground.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [self.cardBackground.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.cardBackground.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.cardBackground.trailingAnchor constant:-14],
        [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
        [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
    ]];
    return self;
}

- (void)setTitleText:(NSString *)titleText {
    _titleText = [titleText copy];
    self.titleTextLabel.text = titleText;
}

- (void)setValueText:(NSString *)valueText {
    _valueText = [valueText copy];
    self.valueChip.text = [NSString stringWithFormat:@"  %@  ", valueText ?: @""];
}

- (void)setPositionFirst:(BOOL)first last:(BOOL)last {
    CACornerMask mask = 0;
    if (first) mask |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (last) mask |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    self.cardBackground.layer.maskedCorners = mask;
    self.cardBackground.layer.cornerRadius = mask ? 6 : 0;
    self.bgTop.constant = first ? 0 : -1;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardBackground.backgroundColor = highlighted ? TerraStyle.raised : TerraStyle.surface;
}

@end

/// One installed runtime: big "Java 21" title, folder name, "version · size", chips, selection mark.
@interface TerraRuntimeCardCell : UITableViewCell
@property(nonatomic, strong) UIView *cardBackground;
@property(nonatomic, strong) UILabel *bigTitleLabel;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *infoLabel;
@property(nonatomic, strong) UIStackView *chipRow;
@property(nonatomic, strong) UIStackView *defaultChips;
@property(nonatomic, strong) UIImageView *checkView;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UIButton *deleteButton;
@property(nonatomic, copy) NSString *runtimeName;
@property(nonatomic) BOOL runtimeSelected;
@end

@implementation TerraRuntimeCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    self.cardBackground = TerraRuntimeCardBackground();
    [self.contentView addSubview:self.cardBackground];

    self.bigTitleLabel = [UILabel new];
    self.bigTitleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    self.bigTitleLabel.textColor = TerraStyle.text;

    self.nameLabel = [UILabel new];
    self.nameLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.nameLabel.textColor = TerraStyle.dimText;
    self.nameLabel.numberOfLines = 0;

    self.infoLabel = [UILabel new];
    self.infoLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.infoLabel.textColor = TerraStyle.dimText;
    self.infoLabel.numberOfLines = 0;

    self.chipRow = TerraRuntimeHStack();
    self.defaultChips = [UIStackView new];
    self.defaultChips.axis = UILayoutConstraintAxisVertical;
    self.defaultChips.alignment = UIStackViewAlignmentLeading;
    self.defaultChips.spacing = 4;

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[self.bigTitleLabel, self.nameLabel, self.infoLabel, self.chipRow, self.defaultChips]];
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    texts.axis = UILayoutConstraintAxisVertical;
    texts.alignment = UIStackViewAlignmentLeading;
    texts.spacing = 3;
    [texts setCustomSpacing:8 afterView:self.infoLabel];
    [texts setCustomSpacing:6 afterView:self.chipRow];
    [self.contentView addSubview:texts];

    self.checkView = [UIImageView new];
    self.checkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkView.contentMode = UIViewContentModeCenter;
    [self.contentView addSubview:self.checkView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = TerraStyle.text;
    self.spinner.hidesWhenStopped = YES;
    [self.contentView addSubview:self.spinner];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.deleteButton setImage:[UIImage systemImageNamed:@"trash"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]]
        forState:UIControlStateNormal];
    self.deleteButton.tintColor = TerraStyle.danger;
    self.deleteButton.backgroundColor = TerraStyle.raised;
    self.deleteButton.layer.cornerRadius = 4;
    self.deleteButton.layer.borderWidth = 1;
    self.deleteButton.layer.borderColor = TerraStyle.border.CGColor;
    self.deleteButton.accessibilityLabel = @"Delete runtime";
    [self.contentView addSubview:self.deleteButton];

    UILayoutGuide *m = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.cardBackground.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
        [self.cardBackground.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
        [self.cardBackground.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [self.cardBackground.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],

        [texts.topAnchor constraintEqualToAnchor:self.cardBackground.topAnchor constant:14],
        [texts.bottomAnchor constraintEqualToAnchor:self.cardBackground.bottomAnchor constant:-14],
        [texts.leadingAnchor constraintEqualToAnchor:self.cardBackground.leadingAnchor constant:16],
        [texts.trailingAnchor constraintLessThanOrEqualToAnchor:self.checkView.leadingAnchor constant:-10],

        [self.checkView.trailingAnchor constraintEqualToAnchor:self.cardBackground.trailingAnchor constant:-14],
        [self.checkView.topAnchor constraintEqualToAnchor:self.cardBackground.topAnchor constant:16],
        [self.checkView.widthAnchor constraintEqualToConstant:30],
        [self.checkView.heightAnchor constraintEqualToConstant:30],
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.checkView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.checkView.centerYAnchor],

        [self.deleteButton.trailingAnchor constraintEqualToAnchor:self.checkView.trailingAnchor],
        [self.deleteButton.bottomAnchor constraintEqualToAnchor:self.cardBackground.bottomAnchor constant:-14],
        [self.deleteButton.widthAnchor constraintEqualToConstant:30],
        [self.deleteButton.heightAnchor constraintEqualToConstant:30],
        [self.deleteButton.topAnchor constraintGreaterThanOrEqualToAnchor:self.checkView.bottomAnchor constant:8],
    ]];
    return self;
}

- (void)setRuntimeSelected:(BOOL)runtimeSelected {
    _runtimeSelected = runtimeSelected;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightBold];
    self.checkView.image = [UIImage systemImageNamed:runtimeSelected ? @"checkmark.square.fill" : @"square" withConfiguration:cfg];
    self.checkView.tintColor = runtimeSelected ? TerraStyle.greenBright : [UIColor colorWithWhite:1 alpha:0.25];
    self.cardBackground.layer.borderColor = (runtimeSelected ? TerraStyle.green : TerraStyle.border).CGColor;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    self.cardBackground.backgroundColor = highlighted ? TerraStyle.raised : TerraStyle.surface;
}

- (void)setChips:(NSArray<UILabel *> *)chips defaultChips:(NSArray<UILabel *> *)defaults {
    for (UIView *v in self.chipRow.arrangedSubviews) [v removeFromSuperview];
    for (UIView *v in self.defaultChips.arrangedSubviews) [v removeFromSuperview];
    for (UILabel *c in chips) [self.chipRow addArrangedSubview:c];
    for (UILabel *c in defaults) [self.defaultChips addArrangedSubview:c];
    self.chipRow.hidden = chips.count == 0;
    self.defaultChips.hidden = defaults.count == 0;
}

@end

#pragma mark -

@interface LauncherPrefManageJREViewController ()<UIContextMenuInteractionDelegate, UIDocumentPickerDelegate>
@property(nonatomic) NSMutableDictionary<NSNumber *, NSMutableArray *> *javaRuntimes;
@property(nonatomic) NSMutableArray<NSNumber *> *sortedJavaVersions;
@property(nonatomic) NSArray<NSString *> *selectedRTTags;
@property(nonatomic) NSMutableDictionary<NSString *, NSString *> *selectedRuntimes;
@property(nonatomic) UIMenu* currentMenu;
@property(nonatomic, weak) NSIndexPath* installingIndexPath;
@end

@implementation LauncherPrefManageJREViewController

+ (LauncherPrefManageJREViewController *)currentInstance {
    // 修复 #41: currentVC() 不一定是 UISplitViewController（在设置子页面里它会返回
    // 当前可见 VC 本身），直接强转并访问 viewControllers 会触发
    // "unrecognized selector viewControllers" 崩溃。这里做严格类型校验。
    UIViewController *current = currentVC();
    if (!current) return nil;

    // 常见路径：当前 VC 是 LauncherPrefManageJREViewController 自身（在导航栈顶）
    if ([current isKindOfClass:LauncherPrefManageJREViewController.class]) {
        return (LauncherPrefManageJREViewController *)current;
    }

    // 走 splitVC 路径：先尝试从 current 往上找 splitVC
    UISplitViewController *splitVC = nil;
    if ([current isKindOfClass:UISplitViewController.class]) {
        splitVC = (UISplitViewController *)current;
    } else if ([current.navigationController isKindOfClass:LauncherNavigationController.class]) {
        // current 的 navigationController 是 LauncherNavigationController
        // LauncherNavigationController 的 presenting/splitViewController 才是 splitVC
        splitVC = current.navigationController.splitViewController;
    } else {
        splitVC = current.splitViewController;
    }
    if (![splitVC isKindOfClass:UISplitViewController.class] || splitVC.viewControllers.count < 2) {
        return nil;
    }
    UIViewController *secondary = splitVC.viewControllers[1];
    LauncherNavigationController *nav = nil;
    if ([secondary isKindOfClass:LauncherNavigationController.class]) {
        nav = (LauncherNavigationController *)secondary;
    } else if ([secondary isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)secondary).topViewController;
        if ([top isKindOfClass:LauncherPrefManageJREViewController.class]) {
            return (LauncherPrefManageJREViewController *)top;
        }
    }
    if (!nav || ![nav.topViewController isKindOfClass:LauncherPrefManageJREViewController.class]) {
        return nil;
    }
    return (LauncherPrefManageJREViewController *)nav.topViewController;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setTitle:localize(@"preference.title.manage_runtime", nil)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"plus"] style:UIBarButtonItemStylePlain target:self action:@selector(actionImportRuntime)];

    // ★ [TERRA-STYLE] solid charcoal page, custom card cells, no system separators.
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.sectionHeaderTopPadding = 0;
    self.tableView.estimatedRowHeight = 96;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 36;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionFooterHeight = 24;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [TerraStyle applyToViewController:self];
    self.tableView.backgroundColor = TerraStyle.background;
    self.tableView.tableHeaderView = [self terraHeaderView];

    self.javaRuntimes = @{
        @(DEFAULT_JRE): @[@"preference.manage_runtime.default.1165", @"preference.manage_runtime.default.117", @"launcher.menu.execute_jar"]
    }.mutableCopy;
    self.sortedJavaVersions = @[@(DEFAULT_JRE)].mutableCopy;

    self.selectedRTTags = @[@"1_16_5_older", @"1_17_newer", @"execute_jar"];
    self.selectedRuntimes = getPrefObject(@"java.java_homes");

    NSString *internalPath = [NSString stringWithFormat:@"%@/java_runtimes", NSBundle.mainBundle.bundlePath];
    NSString *externalPath = [NSString stringWithFormat:@"%s/java_runtimes", getenv("POJAV_HOME")];
    [self listJREInPath:internalPath markInternal:YES];
    [self listJREInPath:externalPath markInternal:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [TerraStyle applyToViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Size the auto-layout table header to the current width.
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;
    CGFloat width = self.tableView.bounds.size.width;
    CGSize size = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                        withHorizontalFittingPriority:UILayoutPriorityRequired
                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(header.frame.size.height - size.height) > 0.5 || fabs(header.frame.size.width - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, size.height);
        self.tableView.tableHeaderView = header;
    }
}

/// Header card: "Java runtimes", one-line explanation, "Import runtime…" block button.
- (UIView *)terraHeaderView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 375, 160)];
    container.preservesSuperviewLayoutMargins = YES;

    UIView *card = [TerraStyle cardView];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:card];

    UIView *block = [TerraStyle grassBlockOfSize:32];
    [card addSubview:block];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Java runtimes";
    title.font = TerraStyle.titleFont;
    title.textColor = TerraStyle.text;
    [card addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Minecraft runs on Java. Pick defaults per game version, or import your own.";
    subtitle.font = TerraStyle.bodyFont;
    subtitle.textColor = TerraStyle.dimText;
    subtitle.numberOfLines = 0;
    [card addSubview:subtitle];

    UIButton *import = [TerraStyle blockButtonWithTitle:@"Import runtime\u2026" symbol:@"square.and.arrow.down" primary:YES];
    import.translatesAutoresizingMaskIntoConstraints = NO;
    [import addTarget:self action:@selector(actionImportRuntime) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:import];

    UILabel *hint = [UILabel new];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = @".tar.xz runtimes built for iOS (aarch64)";
    hint.font = TerraStyle.captionFont;
    hint.textColor = TerraStyle.dimText;
    hint.numberOfLines = 0;
    [card addSubview:hint];

    UILayoutGuide *m = container.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
        [card.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],

        [block.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [block.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:block.trailingAnchor constant:12],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
        [title.centerYAnchor constraintEqualToAnchor:block.centerYAnchor],

        [subtitle.topAnchor constraintEqualToAnchor:block.bottomAnchor constant:10],
        [subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [import.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:14],
        [import.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [import.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],

        [hint.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [hint.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [hint.topAnchor constraintEqualToAnchor:import.bottomAnchor constant:8],
        [hint.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return container;
}

+ (void)actionCancelImportRuntime {
    // redesign-download-ui Phase 4 Task 4.3：取消统一任务管理器中的运行时导入任务，
    // rawTask 即 totalProgress（NSProgress），取消后 extractTarXZ 循环按 cancelled 路径清理
    if (currentImportTaskId) {
        [[DownloadTaskManager sharedManager] cancelTaskWithId:currentImportTaskId];
    }
}

- (void)actionImportRuntime {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[[UTType typeWithMIMEType:@"application/x-xz"]]];
    documentPicker.delegate = self;
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    LauncherNavigationController *nav = (id)self.navigationController;
    [nav setInteractionEnabled:NO forDownloading:NO];

    [url startAccessingSecurityScopedResource];
    NSUInteger xzSize = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil].fileSize;

    NSProgress *totalProgress = [NSProgress progressWithTotalUnitCount:xzSize];
    NSProgress *fileProgress = [NSProgress progressWithTotalUnitCount:0];

    // redesign-download-ui Phase 4 Task 4.3：运行时导入注册为统一下载任务，
    // 单阶段 + autoPresentDetail 自动弹出统一进度页；rawTask = totalProgress 支持取消
    NSString *pathOrUrl = url.path;
    // ★ [DEMINE] 原为 substringToIndex:url.path.length-7：路径短于 7 字符时无符号下溢
    //   ⇒ 越界 NSRangeException 崩 App。短则退化为用整条路径取末段。
    NSString *runtimeName = (pathOrUrl.length >= 7 ? [pathOrUrl substringToIndex:pathOrUrl.length - 7] : pathOrUrl).lastPathComponent;
    NSString *source = getPrefObject(@"general.download_source") ?: @"official";
    DownloadTaskItem *taskItem = [[DownloadTaskManager sharedManager]
        registerTaskWithResourceType:DownloadTaskResourceTypeJavaRuntime
                        resourceName:runtimeName
                         displayName:[NSString stringWithFormat:localize(@"i18n_str_364", nil), runtimeName]
                      downloadSource:source
                             rawTask:totalProgress
                      supportsResume:NO
                             iconURL:nil];
    if (taskItem) {
        taskItem.downloadURL = url.absoluteString;
        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId stages:PLTaskStagesSingleFile()];
        taskItem.autoPresentDetail = YES;
        [[DownloadTaskManager sharedManager] setTaskWithId:taskItem.taskId state:DownloadTaskStateDownloading];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId stageAtIndex:0 status:PLTaskStageStatusRunning];
        [[DownloadTaskManager sharedManager] updateTaskWithId:taskItem.taskId stageAtIndex:0 progress:-1 message:localize(@"i18n_str_365", nil)];
        currentImportTaskId = taskItem.taskId;
    }
    NSString *taskId = taskItem.taskId;
    DownloadTaskManager *manager = [DownloadTaskManager sharedManager];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSString *outPath = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("POJAV_HOME"), runtimeName];
        NSString *error = [LauncherPrefManageJREViewController extractTarXZ:url.path
        to:outPath progress:totalProgress fileProgress:fileProgress
        fileCallback:^(NSString* name) {
            // fileCallback 在 extractTarXZ 内部（后台线程）调用，
            // manager 上报线程安全；进度文案带当前文件名
            double fraction = totalProgress.fractionCompleted;
            NSString *displayText = [NSString stringWithFormat:localize(@"i18n_str_366", nil), name];
            [manager updateTaskWithId:taskId
                              progress:fraction
                          totalBytes:(int64_t)xzSize
                       downloadedBytes:(int64_t)(xzSize * fraction)];
            [manager updateTaskWithId:taskId stageAtIndex:0 progress:fraction message:displayText];
        }];
        [url stopAccessingSecurityScopedResource];

        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showDialog(localize(@"Error", nil), error);
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            LauncherPrefManageJREViewController *vc = LauncherPrefManageJREViewController.currentInstance;

            // 任务收尾：成功/失败/取消上报到统一任务管理器
            if (taskId) {
                if (error) {
                    [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusFailed];
                    [manager updateTaskWithId:taskId error:[NSError errorWithDomain:@"RuntimeImport" code:-1 userInfo:@{NSLocalizedDescriptionKey: error}]];
                    [manager setTaskWithId:taskId state:DownloadTaskStateFailed];
                } else if (totalProgress.cancelled) {
                    [manager setTaskWithId:taskId state:DownloadTaskStateCancelled];
                } else {
                    [manager updateTaskWithId:taskId stageAtIndex:0 status:PLTaskStageStatusCompleted];
                    [manager setTaskWithId:taskId state:DownloadTaskStateCompleted];
                }
                currentImportTaskId = nil;
            }

            if ((error || totalProgress.cancelled) && vc.installingIndexPath) {
                [vc removeRuntimeAtIndexPath:vc.installingIndexPath];
            } else {
                NSNumber *version = self.sortedJavaVersions[vc.installingIndexPath.section];
                NSString *name = self.javaRuntimes[version][vc.installingIndexPath.row];
                objc_setAssociatedObject(name, @"installing", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            vc.installingIndexPath = nil;
            [vc.tableView reloadData];

            [nav setInteractionEnabled:YES forDownloading:NO];
        });
    });
}

#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sortedJavaVersions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (self.sortedJavaVersions[section].intValue) {
        case DEFAULT_JRE: return localize(@"preference.manage_runtime.header.default", nil);
        case INVALID_JRE: return localize(@"preference.manage_runtime.header.invalid", nil);
        default: return [NSString stringWithFormat:@"Java %@", self.sortedJavaVersions[section]];
    }
}

/// ★ [TERRA-STYLE] uppercase launcher-style section headers.
/// Section 0 = "DEFAULT JAVA"; the first runtime section = "INSTALLED RUNTIMES"; invalid = "INVALID RUNTIMES".
- (NSString *)terraHeaderTextForSection:(NSInteger)section {
    int version = self.sortedJavaVersions[section].intValue;
    if (version == DEFAULT_JRE) return @"Default Java";
    if (version == INVALID_JRE) return localize(@"preference.manage_runtime.header.invalid", nil);
    if (section == 1) return @"Installed runtimes";
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *text = [self terraHeaderTextForSection:section];
    UIView *v = [UIView new];
    v.preservesSuperviewLayoutMargins = YES;
    if (!text) {
        [v.heightAnchor constraintEqualToConstant:0].active = YES;
        return v;
    }
    UILabel *label = [TerraStyle sectionLabel:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    if (self.sortedJavaVersions[section].intValue == INVALID_JRE) label.textColor = TerraStyle.danger;
    [v addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:v.readableContentGuide.leadingAnchor constant:2],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:v.readableContentGuide.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:v.topAnchor constant:18],
        [label.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-8],
    ]];
    return v;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (self.sortedJavaVersions[section].intValue) {
        case DEFAULT_JRE: return @"Used unless an installation picks its own Java.";
        case INVALID_JRE: return @"Missing or broken files. Delete and import again.";
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    UIView *v = [UIView new];
    v.preservesSuperviewLayoutMargins = YES;
    if (!text) {
        [v.heightAnchor constraintEqualToConstant:0].active = YES;
        return v;
    }
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = TerraStyle.captionFont;
    label.textColor = TerraStyle.dimText;
    label.numberOfLines = 0;
    [v addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:v.readableContentGuide.leadingAnchor constant:2],
        [label.trailingAnchor constraintEqualToAnchor:v.readableContentGuide.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:v.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-4],
    ]];
    return v;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.javaRuntimes[self.sortedJavaVersions[section]].count;
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return [self tableView:tableView cellForDefaultRowAtIndexPath:indexPath];
        default: return [self tableView:tableView cellForRuntimeRowAtIndexPath:indexPath];
    }
}

/// Display titles for the three default-Java rows (same order as selectedRTTags).
- (NSString *)terraDefaultRowTitle:(NSInteger)row {
    if (row == 2) return @"Running .jar files";
    return localize(self.javaRuntimes[@DEFAULT_JRE][row], nil);
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForDefaultRowAtIndexPath:(NSIndexPath *)indexPath
{
    TerraRuntimeDefaultCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DefaultCell"];
    if (cell == nil) {
        cell = [[TerraRuntimeDefaultCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DefaultCell"];
    }
    cell.titleText = [self terraDefaultRowTitle:indexPath.row];
    cell.valueText = [NSString stringWithFormat:@"Java %@",
        ((NSDictionary *)self.selectedRuntimes[@"0"])[self.selectedRTTags[indexPath.row]]];
    NSInteger count = [self tableView:tableView numberOfRowsInSection:indexPath.section];
    [cell setPositionFirst:indexPath.row == 0 last:indexPath.row == count - 1];
    return cell;
}

/// Same rule the old checkmark used.
- (BOOL)terraIsSelectedRuntime:(NSString *)name version:(NSNumber *)version internal:(BOOL)isInternal {
    return [self.selectedRuntimes[version.stringValue] isEqualToString:name] ||
        (isInternal && [self.selectedRuntimes[version.stringValue] isEqualToString:@"internal"]);
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRuntimeRowAtIndexPath:(NSIndexPath *)indexPath {
    TerraRuntimeCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RTCell"];
    if (cell == nil) {
        cell = [[TerraRuntimeCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"RTCell"];
        [cell.deleteButton addTarget:self action:@selector(terraDeleteTapped:) forControlEvents:UIControlEventTouchUpInside];
    }
    NSNumber *version = self.sortedJavaVersions[indexPath.section];
    NSString *name = self.javaRuntimes[version][indexPath.row];
    BOOL isInternal = [objc_getAssociatedObject(name, @"internalJRE") boolValue];
    BOOL isInstalling = [objc_getAssociatedObject(name, @"installing") boolValue];
    BOOL isInvalid = version.intValue == INVALID_JRE;
    cell.runtimeName = name;

    cell.bigTitleLabel.text = isInvalid ? @"Invalid runtime" : [NSString stringWithFormat:@"Java %@", version];
    cell.bigTitleLabel.textColor = isInvalid ? TerraStyle.danger : TerraStyle.text;
    cell.nameLabel.text = name;
    cell.infoLabel.text = @" ";

    NSMutableArray<UILabel *> *chips = [NSMutableArray new];
    [chips addObject:isInternal
        ? [TerraStyle chipWithText:@"Built-in" color:TerraStyle.dimText]
        : [TerraStyle chipWithText:@"Imported" color:[UIColor colorWithRed:0.45 green:0.70 blue:1.0 alpha:1]]];

    if (isInstalling) {
        self.installingIndexPath = indexPath;
        // redesign-download-ui Phase 4 Task 4.3：进度展示移至统一进度页，cell 内仅显示菊花指示器
        [chips addObject:[TerraStyle chipWithText:@"Installing…" color:TerraStyle.warning]];
        [cell.spinner startAnimating];
        cell.checkView.hidden = YES;
    } else {
        [cell.spinner stopAnimating];
        cell.checkView.hidden = isInvalid;
    }

    BOOL selected = [self terraIsSelectedRuntime:name version:version internal:isInternal];
    cell.runtimeSelected = selected;

    // "Default for …" chips: on the runtime currently used for this major version.
    NSMutableArray<UILabel *> *defaults = [NSMutableArray new];
    if (selected && !isInvalid) {
        NSDictionary *defaultMap = (NSDictionary *)self.selectedRuntimes[@"0"];
        NSArray<NSString *> *defaultTitles = @[@"Default for 1.16.5 and older", @"Default for 1.17+", @"Default for .jar files"];
        for (NSInteger i = 0; i < self.selectedRTTags.count && i < defaultTitles.count; i++) {
            id value = defaultMap[self.selectedRTTags[i]];
            if (value && [[value description] isEqualToString:version.stringValue]) {
                [defaults addObject:[TerraStyle chipWithText:defaultTitles[i] color:TerraStyle.greenBright]];
            }
        }
    }
    [cell setChips:chips defaultChips:defaults];

    // Delete: same rule as editingStyleForRowAtIndexPath (not internal, not installing)
    cell.deleteButton.hidden = isInternal || isInstalling;

    // Display size
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long folderSize = 0;
        NSString *directory = [NSString stringWithFormat:@"%@/java_runtimes/%@",
            isInternal ? NSBundle.mainBundle.bundlePath : @(getenv("POJAV_HOME")),
            name];
        [NSFileManager.defaultManager nr_getAllocatedSize:&folderSize ofDirectoryAtURL:[NSURL fileURLWithPath:directory] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![cell.runtimeName isEqualToString:name]) return; // cell was reused
            cell.infoLabel.text = [NSString stringWithFormat:@"%@  ·  %@",
                [self javaVersionForPath:directory],
                [NSByteCountFormatter stringFromByteCount:folderSize countStyle:NSByteCountFormatterCountStyleMemory]];
        });
    });

    return cell;
}

/// Trash button on a runtime card → same confirmation/delete path as swipe-to-delete.
- (void)terraDeleteTapped:(UIButton *)sender {
    UIView *v = sender;
    while (v && ![v isKindOfClass:UITableViewCell.class]) v = v.superview;
    NSIndexPath *indexPath = v ? [self.tableView indexPathForCell:(UITableViewCell *)v] : nil;
    if (!indexPath || indexPath.section == 0) return;
    if ([self tableView:self.tableView editingStyleForRowAtIndexPath:indexPath] != UITableViewCellEditingStyleDelete) return;
    [self tableView:self.tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (indexPath.section == 0) {
        [self tableView:tableView openPickerAtIndexPath:indexPath
            minVersion:(indexPath.row==1 ? 17 : 8)];
        return;
    } else if (self.sortedJavaVersions[indexPath.section].intValue == INVALID_JRE) {
        // TODO: do something, like alert explaining that the runtime has missing files
        return;
    }

    // Update preference
    NSNumber *version = self.sortedJavaVersions[indexPath.section];
    NSString *name = self.javaRuntimes[version][indexPath.row];
    BOOL isInternal = [objc_getAssociatedObject(name, @"internalJRE") boolValue];
    if (isInternal) {
        self.selectedRuntimes[version.stringValue] = @"internal";
    } else {
        self.selectedRuntimes[version.stringValue] = name;
    }
    setPrefObject(@"java.java_homes", self.selectedRuntimes);

    // Update selection mark (and "Default for" chips) for this section
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationNone];
}

/// Default picker changed → refresh "Default for …" chips on the runtime cards.
- (void)terraReloadRuntimeSections {
    if (self.sortedJavaVersions.count < 2) return;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, self.sortedJavaVersions.count - 1)]
                  withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark Context Menu configuration

- (void)tableView:(UITableView *)tableView openPickerAtIndexPath:(NSIndexPath *)indexPath minVersion:(NSInteger)minVer {
    TerraRuntimeDefaultCell *cell = (TerraRuntimeDefaultCell *)[tableView cellForRowAtIndexPath:indexPath];
    if (![cell isKindOfClass:TerraRuntimeDefaultCell.class]) return;

    // 收集可选的 Java 版本
    NSMutableArray<NSString *> *versionTitles = [NSMutableArray new];
    NSMutableArray<NSNumber *> *versionNumbers = [NSMutableArray new];
    for (int i = 1; i < self.sortedJavaVersions.count; i++) {
        if (self.sortedJavaVersions[i].intValue < minVer ||
            self.sortedJavaVersions[i].intValue == INVALID_JRE) {
            continue;
        }
        NSString *version = [self tableView:tableView titleForHeaderInSection:i];
        [versionTitles addObject:version];
        [versionNumbers addObject:self.sortedJavaVersions[i]];
    }

    // iPhone 上改用 UIAlertController actionSheet，避免紧凑菜单被压缩不可调整
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:cell.titleText
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        if (versionTitles.count == 0) {
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"launcher.pref.jre.none", nil)  // ★ [AUDIT-DECIDE] A-11：English 字面量当 key → 新增键 launcher.pref.jre.none
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil]];
        } else {
            for (int i = 0; i < versionTitles.count; i++) {
                NSString *version = versionTitles[i];
                NSNumber *verNum = versionNumbers[i];
                // 当前选中项前加 ✓ 标记
                NSString *title = version;
                if ([cell.valueText isEqualToString:version]) {
                    title = [NSString stringWithFormat:@"✓ %@", version];
                }
                [alert addAction:[UIAlertAction actionWithTitle:title
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *a) {
                    cell.valueText = version;
                    ((NSMutableDictionary *)self.selectedRuntimes[@"0"])[self.selectedRTTags[indexPath.row]] = verNum.stringValue;
                    setPrefObject(@"java.java_homes", self.selectedRuntimes);
                    [self terraReloadRuntimeSections];
                }]];
            }
        }
        [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
        alert.popoverPresentationController.sourceView = cell;
        alert.popoverPresentationController.sourceRect = cell.bounds;
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    // iPad：保留 UIContextMenuInteraction 紧凑菜单
    NSMutableArray *menuItems = [NSMutableArray new];
    for (int i = 0; i < versionTitles.count; i++) {
        NSString *version = versionTitles[i];
        NSNumber *verNum = versionNumbers[i];
        [menuItems addObject:[UIAction
            actionWithTitle:version
            image:nil
            identifier:nil
            handler:^(UIAction *action) {
                cell.valueText = version;
                ((NSMutableDictionary *)self.selectedRuntimes[@"0"])[self.selectedRTTags[indexPath.row]] = verNum.stringValue;
                setPrefObject(@"java.java_homes", self.selectedRuntimes);
                [self terraReloadRuntimeSections];
            }]];
    }

    cell.valueChip.interactions = [NSArray new];

    if (menuItems.count == 0) {
        [menuItems addObject:[UIAction
            actionWithTitle:localize(@"launcher.pref.jre.none", nil)  // ★ [AUDIT-DECIDE] A-11：English 字面量当 key → 新增键 launcher.pref.jre.none
            image:nil
            identifier:nil
            handler:^(UIAction *action){}]];
    }

    self.currentMenu = [UIMenu menuWithTitle:cell.titleText children:menuItems];
    UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    [cell addInteraction:interaction];
    CGRect detailFrame = [cell.valueChip convertRect:cell.valueChip.bounds toView:cell];
    CGPoint location = CGPointMake(CGRectGetMidX(detailFrame), CGRectGetMidY(detailFrame));
    [interaction _presentMenuAtLocation:location];
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return self.currentMenu;
    }];
}

- (_UIContextMenuStyle *)_contextMenuInteraction:(UIContextMenuInteraction *)interaction
styleForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration
{
    _UIContextMenuStyle *style = [_UIContextMenuStyle defaultStyle];
    style.preferredLayout = 3; // _UIContextMenuLayoutCompactMenu
    return style;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    // Runtime folder name (what the old cell.textLabel showed for non-internal runtimes)
    NSString *runtimeName = self.javaRuntimes[self.sortedJavaVersions[indexPath.section]][indexPath.row];
    NSString *title = localize(@"preference.title.confirm", nil);
    NSString *message = [NSString stringWithFormat:localize(@"preference.title.confirm.delete_runtime", nil), runtimeName];
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    confirmAlert.popoverPresentationController.sourceView = cell;
    confirmAlert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSError *error;
        NSString *directory = [NSString stringWithFormat:@"%s/java_runtimes/%@", getenv("POJAV_HOME"), runtimeName];
        [NSFileManager.defaultManager removeItemAtPath:directory error:&error];
        if(!error) {
            [self removeRuntimeAtIndexPath:indexPath];
            [self.tableView reloadData];
        } else {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmAlert addAction:cancel];
    [confirmAlert addAction:ok];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSNumber *version = self.sortedJavaVersions[indexPath.section];
    NSString *name = self.javaRuntimes[version][indexPath.row];
    BOOL isInternal = [objc_getAssociatedObject(name, @"internalJRE") boolValue];
    BOOL isInstalling = [objc_getAssociatedObject(name, @"installing") boolValue];
    if (isInternal || isInstalling) {
        return UITableViewCellEditingStyleNone;
    } else {
        return UITableViewCellEditingStyleDelete;
    }
}

#pragma mark Version parser

- (NSString *)javaVersionForPath:(NSString *)path {
    path = [path stringByAppendingPathComponent:@"release"];
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        return [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
    }

    // ★ [DEMINE] 原为 componentsSeparatedByString:@"JAVA_VERSION=\""][1] 直接下标：
    //   release 文件缺 JAVA_VERSION=" 行时数组只有 1 个元素 ⇒ 越界 NSRangeException 崩 App。
    NSArray *jvParts = [content componentsSeparatedByString:@"JAVA_VERSION=\""];
    if (jvParts.count < 2) {
        NSLog(@"[DEMINE] javaVersionForPath: no JAVA_VERSION in release file: %@", path);
        return @"Error: JAVA_VERSION not found";
    }
    content = jvParts[1];
    content = [content componentsSeparatedByString:@"\""][0];
    return content;
}

- (NSNumber *)majorVersionForFullVersion:(NSString *)version {
    if ([version hasPrefix:@"1.8.0"]) {
        return @8;
    } else if ([version hasPrefix:@"Error: "]){
        return @(INVALID_JRE);
    } else {
        return @([version componentsSeparatedByString:@"."][0].intValue);
    }
}
- (NSNumber *)majorVersionForPath:(NSString *)path {
    return [self majorVersionForFullVersion:[self javaVersionForPath:path]];
}

- (void)addRuntimePath:(NSString *)path markInternal:(BOOL)markInternal {
    NSNumber *majorVer = [self majorVersionForPath:path];
    if (!self.javaRuntimes[majorVer]) {
        self.javaRuntimes[majorVer] = [NSMutableArray new];
        [self.sortedJavaVersions addObject:majorVer];
        [self.sortedJavaVersions sortUsingSelector:@selector(compare:)];
    }

    NSString *file = path.lastPathComponent;
    objc_setAssociatedObject(file, @"internalJRE", @(markInternal), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!markInternal) {
        NSString *installingDir = [path stringByAppendingPathComponent:@".installing"];
        BOOL markInstalling = [NSFileManager.defaultManager fileExistsAtPath:installingDir isDirectory:nil];
        objc_setAssociatedObject(file, @"installing", @(markInstalling), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [self.javaRuntimes[majorVer] addObject:file];
}

- (void)removeRuntimeAtIndexPath:(NSIndexPath *)indexPath {
    TerraRuntimeCardCell *cell = (TerraRuntimeCardCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    NSNumber *version = self.sortedJavaVersions[indexPath.section];
    NSString *name = self.javaRuntimes[version][indexPath.row];

    [self.javaRuntimes[version] removeObject:name];
    if (self.javaRuntimes[version].count == 0) {
        [self.javaRuntimes removeObjectForKey:version];
        [self.selectedRuntimes removeObjectForKey:version.stringValue];
        [self.sortedJavaVersions removeObject:version];
    } else if ([cell isKindOfClass:TerraRuntimeCardCell.class] && cell.runtimeSelected) {
        self.selectedRuntimes[version.stringValue] = self.javaRuntimes[version][0];
    }

    setPrefObject(@"java.java_homes", self.selectedRuntimes);
}

- (void)listJREInPath:(NSString *)path markInternal:(BOOL)markInternal {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *files = [fm contentsOfDirectoryAtPath:path error:nil];
    BOOL isDir;
    for (NSString *file in files) {
        NSString *rtPath = [path stringByAppendingPathComponent:file];
        [fm fileExistsAtPath:rtPath isDirectory:&isDir];
        if (isDir) {
            [self addRuntimePath:rtPath markInternal:markInternal];
        }
    }
}

#pragma mark Extract tar.xz

+ (NSDictionary *)parseRuntimeInfo:(NSString *)path {
    NSError *error;

    NSString *releaseFile = [path stringByAppendingPathComponent:@"release"];
    NSString *content = [NSString stringWithContentsOfFile:releaseFile encoding:NSUTF8StringEncoding error:&error];
    if (error) {
        return @{@"Error": error.localizedDescription};
    }

    NSMutableDictionary *dict = [NSMutableDictionary new];
    for (NSString *line in [content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length > 0) {
            NSArray *keyValue = [[line substringToIndex:line.length-1] componentsSeparatedByString:@"=\""];
            // ★ [DEMINE] 原为 keyValue[1] 直接下标：release 文件里任一行不含 =" 时
            //   (空行/注释/等号变体)数组只有 1 个元素 ⇒ 越界 NSRangeException 崩 App。缺值跳过该行。
            if (keyValue.count < 2) {
                NSLog(@"[DEMINE] skip malformed release line: %@", line);
                continue;
            }
            dict[keyValue[0]] = keyValue[1];
        }
    }
    return dict;
}

+ (NSString *)validateRuntimeInfo:(NSString *)path {
    NSDictionary *dict = [self parseRuntimeInfo:path];

    if (dict[@"Error"]) {
        return dict[@"Error"];
    } else if (![dict[@"OS_ARCH"] isEqualToString:@"aarch64"]) {
        return [NSString stringWithFormat:@"Wrong runtime architecture: %@ (need aarch64)", dict[@"OS_ARCH"]];
    } else if (![dict[@"OS_NAME"] isEqualToString:@"Darwin"]) {
        return [NSString stringWithFormat:@"Wrong runtime platform: %@ (need Darwin)", dict[@"OS_NAME"]];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.currentInstance addRuntimePath:path markInternal:NO];
        [self.currentInstance.tableView reloadData];
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.currentInstance.tableView scrollToRowAtIndexPath:self.currentInstance.installingIndexPath
            atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    });
    return nil;
}

+ (NSString *)lzmaErrorDescriptionForCode:(int)code {
    switch (code) {
        case LZMA_MEM_ERROR:
            return @"Memory allocation failed";
        case LZMA_FORMAT_ERROR:
            return @"The input is not in the .xz format";
        case LZMA_OPTIONS_ERROR:
            return @"Unsupported compression options";
        case LZMA_DATA_ERROR:
            return @"Compressed file is corrupt";
        case LZMA_BUF_ERROR:
            return @"Compressed file is truncated or otherwise corrupt";
        default:
            return @"Unknown error, possibly a bug";
    }
}

// Reference: https://github.com/xz-mirror/xz/blob/master/doc/examples/02_decompress.c
+ (NSString *)extractTarXZ:(NSString *)inPath to:(NSString *)outPath progress:(NSProgress *)progress fileProgress:(NSProgress *)fileProgress fileCallback:(void(^)(NSString* name))fileCallback {
    NSString *installingDir = [outPath stringByAppendingPathComponent:@".installing"];
    [NSFileManager.defaultManager createDirectoryAtPath:installingDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSInputStream *inFile = [NSInputStream inputStreamWithFileAtPath:inPath];
    [inFile open];

    NSString *msg = nil;
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_action action = LZMA_RUN;
    uint8_t inbuf[BUFSIZ], outbuf[512];

    lzma_ret ret = lzma_stream_decoder(&strm, UINT64_MAX, LZMA_CONCATENATED);
    if (ret != LZMA_OK) {
        return [self lzmaErrorDescriptionForCode:ret];
    }

    strm.next_in = NULL;
    strm.avail_in = 0;
    strm.next_out = outbuf;
    strm.avail_out = sizeof(outbuf);

    TarHeader currFileHeader;
    NSString *currFileName;
    NSOutputStream *currFileOut;
    NSUInteger currFileOff, currFileSize;

    while (!progress.cancelled) {
        if (strm.avail_in == 0 && inFile.hasBytesAvailable) {
            strm.next_in = inbuf;
            strm.avail_in = [inFile read:inbuf maxLength:sizeof(inbuf)];

            if (strm.avail_in == -1) {
                msg = inFile.streamError.localizedDescription;
                break;
            }

            if (!inFile.hasBytesAvailable) {
                action = LZMA_FINISH;
            }
        }

        ret = lzma_code(&strm, action);
        if (strm.avail_out == 0 || ret == LZMA_STREAM_END) {
            if (currFileOut) {
                size_t remaining = currFileSize - currFileOff;
                size_t write_size = MIN(sizeof(outbuf), remaining);
                currFileOff += write_size;
                // Avoid overloading the main queue
                if (currFileOff % 102400 == 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        fileProgress.completedUnitCount = currFileOff;
                        fileCallback(currFileName);
                    });
                }
                if ([currFileOut write:outbuf maxLength:write_size] != write_size) {
                    msg = [NSString stringWithFormat:@"%s: %@", currFileHeader.name, currFileOut.streamError];
                    break;
                } else if (currFileOff >= currFileSize) {
                    [currFileOut close];
                    currFileOut = nil;
                    if ([currFileName isEqualToString:@"./release"]) {
                        msg = [LauncherPrefManageJREViewController validateRuntimeInfo:outPath];
                        if (msg) goto cleanup;
                    }
                }
            } else {
                memcpy(&currFileHeader, outbuf, sizeof(outbuf));
                if (currFileHeader.name[0] == '\0') {
                    // EOF
                    break;
                }
                NSString *absPath = [NSString stringWithFormat:@"%@/%s", outPath, currFileHeader.name];
                NSError *error = nil;
                switch (currFileHeader.typeflag) {
                    case '0':
                    case '\0': { // File
                        currFileName = @(currFileHeader.name);
                        currFileOff = 0;
                        currFileSize = strtol(currFileHeader.size, NULL, 8);
                        // NSProgress 非线程安全，在主线程修改其计数
                        dispatch_async(dispatch_get_main_queue(), ^{
                            fileProgress.completedUnitCount = 0;
                            fileProgress.totalUnitCount = currFileSize;
                        });
                        NSLog(@"[RuntimeUnpack] Extracting %@", currFileName);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            fileCallback(currFileName);
                        });

                        currFileOut = [NSOutputStream outputStreamToFileAtPath:absPath append:NO];
                        [currFileOut open];
                    } break;
                    case '2': { // Symlink
                        symlink(currFileHeader.linkname, currFileHeader.name);
                        //NSLog(@"%s -> %s", currFileHeader.name, currFileHeader.linkname);
                    } break;
                    case '5': { // Folder
                        [NSFileManager.defaultManager createDirectoryAtPath:absPath withIntermediateDirectories:YES attributes:nil error:&error];
                        if (error) {
                            msg = [NSString stringWithFormat:@"%s: %@", currFileHeader.name, error];
                            goto cleanup;
                        }
                    } break;
                    default: // Ignore everything else
                        if (currFileHeader.typeflag < '0' && currFileHeader.typeflag > '7'
                        && (currFileHeader.typeflag != 'x' && currFileHeader.typeflag != 'g')) {
                            msg = [NSString stringWithFormat:@"Invalid typeflag %c", currFileHeader.typeflag];
                            goto cleanup;
                        }
                        NSLog(@"[RuntimeUnpack] Skipped %s (typeflag %c)", currFileHeader.name, currFileHeader.typeflag);
                        break;
                }
            }

            strm.next_out = outbuf;
            strm.avail_out = sizeof(outbuf);

            // NSProgress 非线程安全，在主线程修改其计数
            NSUInteger totalIn = (NSUInteger)strm.total_in;
            dispatch_async(dispatch_get_main_queue(), ^{
                progress.completedUnitCount = totalIn;
            });
        }

        if (ret == LZMA_STREAM_END) {
            break;
        } else if (ret != LZMA_OK) {
            msg = [self lzmaErrorDescriptionForCode:ret];
            break;
        }
    }

cleanup:
    if (msg || progress.cancelled) {
        [NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
    } else {
        [NSFileManager.defaultManager removeItemAtPath:installingDir error:nil];
    }
    lzma_end(&strm);
    [inFile close];
    [currFileOut close];
    return msg;
}

@end
