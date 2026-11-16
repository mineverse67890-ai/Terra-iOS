//
//  TerraTroubleshootViewController.m
//  ★ [TERRA-DIAG] Dark, card-based diagnosis screen (Terra launcher palette).
//

#import "TerraTroubleshootViewController.h"
#import "TerraCrashAnalyzer.h"

// Terra palette (matches TerraTheme.swift)
#define TT_BG      [UIColor colorWithRed:0x1E/255.0 green:0x1E/255.0 blue:0x1E/255.0 alpha:1]
#define TT_CARD    [UIColor colorWithRed:0x26/255.0 green:0x26/255.0 blue:0x26/255.0 alpha:1]
#define TT_RAISED  [UIColor colorWithRed:0x31/255.0 green:0x31/255.0 blue:0x31/255.0 alpha:1]
#define TT_GREEN   [UIColor colorWithRed:0x52/255.0 green:0xA5/255.0 blue:0x35/255.0 alpha:1]
#define TT_AMBER   [UIColor colorWithRed:0.95 green:0.75 blue:0.20 alpha:1]
#define TT_RED     [UIColor colorWithRed:0xE5/255.0 green:0x53/255.0 blue:0x53/255.0 alpha:1]
#define TT_DIM     [UIColor colorWithWhite:0.70 alpha:1]

#pragma mark - Full log viewer

@interface TerraLogViewerViewController : UIViewController
@end

@implementation TerraLogViewerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Game Log";
    self.view.backgroundColor = TT_BG;
    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.backgroundColor = TT_BG;
    tv.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    tv.textContainerInset = UIEdgeInsetsMake(12, 12, 24, 12);
    NSString *log = [TerraCrashAnalyzer latestLogTail:400 * 1024];
    tv.text = log.length ? log : @"The log is empty — the game hasn't written anything yet.";
    [self.view addSubview:tv];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (tv.text.length) [tv scrollRangeToVisible:NSMakeRange(tv.text.length - 1, 1)];
    });
}

@end

#pragma mark - Troubleshoot screen

@interface TerraTroubleshootViewController ()
@property(nonatomic, assign) NSInteger exitCode;
@property(nonatomic, copy, nullable) NSString *_Nullable (^stageProvider)(void);
@property(nonatomic, strong) TerraDiagnosis *diagnosis;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIStackView *stack;
@end

@implementation TerraTroubleshootViewController

+ (void)presentFrom:(UIViewController *)presenter exitCode:(NSInteger)exitCode
      stageProvider:(NSString *_Nullable (^)(void))stageProvider {
    TerraTroubleshootViewController *vc = [TerraTroubleshootViewController new];
    vc.exitCode = exitCode;
    vc.stageProvider = stageProvider;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    // Full screen OVER the presenter: a page sheet would shrink/transform the game's drawing surface.
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = TT_BG;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    nav.navigationBar.standardAppearance = ap;
    nav.navigationBar.scrollEdgeAppearance = ap;
    nav.navigationBar.tintColor = TT_GREEN;
    UIViewController *top = presenter;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:nav animated:YES completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // Follow whatever the game screen allows (it is usually landscape-locked).
    UIViewController *p = self.navigationController.presentingViewController;
    return p ? p.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Troubleshoot";
    self.view.backgroundColor = TT_BG;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    if (self.exitCode == NSNotFound) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Re-check" style:UIBarButtonItemStylePlain target:self action:@selector(reload)];
    }

    self.scrollView = [UIScrollView new];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.stack = [UIStackView new];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 14;
    [self.scrollView addSubview:self.stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *preferredWidth = [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-40];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-32],
        [self.stack.centerXAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.centerXAnchor],
        [self.stack.widthAnchor constraintLessThanOrEqualToConstant:680],
        preferredWidth,
    ]];

    [self reload];
}

- (void)close {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
    NSString *stage = self.stageProvider ? self.stageProvider() : nil;
    self.diagnosis = [TerraCrashAnalyzer diagnoseWithExitCode:self.exitCode stageName:stage];
    for (UIView *v in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:v]; [v removeFromSuperview]; }
    [self.stack addArrangedSubview:[self headerCard]];
    if (self.diagnosis.evidence.length) [self.stack addArrangedSubview:[self evidenceCard]];
    if (self.diagnosis.fixes.count) [self.stack addArrangedSubview:[self fixesCard]];
    [self.stack addArrangedSubview:[self actionButtons]];
}

#pragma mark Cards

- (UIView *)card {
    UIView *c = [UIView new];
    c.backgroundColor = TT_CARD;
    c.layer.cornerRadius = 14;
    c.layer.cornerCurve = kCACornerCurveContinuous;
    c.layer.borderWidth = 1;
    c.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    return c;
}

- (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

- (UIView *)wrap:(UIStackView *)inner {
    UIView *c = [self card];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [inner.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-16],
        [inner.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [inner.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
    ]];
    return c;
}

- (UIView *)headerCard {
    UIColor *tint; NSString *symbol;
    switch (self.diagnosis.severity) {
        case TerraDiagnosisSeverityOK:      tint = TT_GREEN; symbol = (self.exitCode == NSNotFound) ? @"hourglass" : @"checkmark.seal.fill"; break;
        case TerraDiagnosisSeverityWarning: tint = TT_AMBER; symbol = @"exclamationmark.triangle.fill"; break;
        case TerraDiagnosisSeverityProblem: tint = TT_RED;   symbol = @"xmark.octagon.fill"; break;
    }
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold]]];
    icon.tintColor = tint;
    icon.contentMode = UIViewContentModeCenter;
    [icon.widthAnchor constraintEqualToConstant:36].active = YES;

    NSString *kicker = (self.exitCode == NSNotFound) ? @"WHILE LOADING" : [NSString stringWithFormat:@"GAME EXITED · CODE %ld", (long)self.exitCode];
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self label:kicker font:[UIFont systemFontOfSize:11 weight:UIFontWeightHeavy] color:tint],
        [self label:self.diagnosis.title font:[UIFont systemFontOfSize:22 weight:UIFontWeightBold] color:UIColor.whiteColor],
        [self label:self.diagnosis.summary font:[UIFont systemFontOfSize:15] color:TT_DIM],
    ]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 6;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon, texts]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 12;
    return [self wrap:row];
}

- (UIView *)evidenceCard {
    UILabel *code = [self label:self.diagnosis.evidence
                           font:[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]
                          color:[UIColor colorWithWhite:0.88 alpha:1]];
    UIView *codeBox = [UIView new];
    codeBox.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    codeBox.layer.cornerRadius = 8;
    code.translatesAutoresizingMaskIntoConstraints = NO;
    [codeBox addSubview:code];
    [NSLayoutConstraint activateConstraints:@[
        [code.topAnchor constraintEqualToAnchor:codeBox.topAnchor constant:10],
        [code.bottomAnchor constraintEqualToAnchor:codeBox.bottomAnchor constant:-10],
        [code.leadingAnchor constraintEqualToAnchor:codeBox.leadingAnchor constant:10],
        [code.trailingAnchor constraintEqualToAnchor:codeBox.trailingAnchor constant:-10],
    ]];
    UIStackView *inner = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self label:@"FOUND IN THE LOG" font:[UIFont systemFontOfSize:11 weight:UIFontWeightHeavy] color:TT_DIM],
        codeBox,
    ]];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 10;
    return [self wrap:inner];
}

- (UIView *)fixesCard {
    UIStackView *inner = [UIStackView new];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 12;
    [inner addArrangedSubview:[self label:@"HOW TO FIX" font:[UIFont systemFontOfSize:11 weight:UIFontWeightHeavy] color:TT_DIM]];
    [self.diagnosis.fixes enumerateObjectsUsingBlock:^(NSString *fix, NSUInteger i, BOOL *stop) {
        UILabel *num = [self label:[NSString stringWithFormat:@"%lu", (unsigned long)(i + 1)]
                              font:[UIFont systemFontOfSize:13 weight:UIFontWeightBold] color:UIColor.whiteColor];
        num.textAlignment = NSTextAlignmentCenter;
        num.backgroundColor = TT_GREEN;
        num.layer.cornerRadius = 11;
        num.layer.masksToBounds = YES;
        [num.widthAnchor constraintEqualToConstant:22].active = YES;
        [num.heightAnchor constraintEqualToConstant:22].active = YES;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
            num, [self label:fix font:[UIFont systemFontOfSize:15] color:[UIColor colorWithWhite:0.92 alpha:1]]]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentTop;
        row.spacing = 12;
        [inner addArrangedSubview:row];
    }];
    return [self wrap:inner];
}

- (UIButton *)actionButton:(NSString *)title symbol:(NSString *)symbol action:(SEL)action primary:(BOOL)primary {
    UIButtonConfiguration *cfg = primary ? [UIButtonConfiguration filledButtonConfiguration]
                                         : [UIButtonConfiguration tintedButtonConfiguration];
    cfg.title = title;
    cfg.image = [UIImage systemImageNamed:symbol];
    cfg.imagePadding = 6;
    cfg.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    cfg.baseBackgroundColor = primary ? [UIColor colorWithRed:0x3C/255.0 green:0x85/255.0 blue:0x27/255.0 alpha:1] : TT_RAISED;
    cfg.baseForegroundColor = UIColor.whiteColor;
    cfg.contentInsets = NSDirectionalEdgeInsetsMake(12, 10, 12, 10);
    UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIView *)actionButtons {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self actionButton:@"Full Log" symbol:@"doc.text.magnifyingglass" action:@selector(showLog) primary:NO],
        [self actionButton:@"Share Log" symbol:@"square.and.arrow.up" action:@selector(shareLog:) primary:YES],
        [self actionButton:@"Copy" symbol:@"doc.on.doc" action:@selector(copyReport:) primary:NO],
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 10;
    return row;
}

#pragma mark Actions

- (void)showLog {
    [self.navigationController pushViewController:[TerraLogViewerViewController new] animated:YES];
}

- (void)shareLog:(UIButton *)sender {
    NSMutableArray *items = [NSMutableArray arrayWithObject:[self.diagnosis reportText]];
    [items addObjectsFromArray:[TerraCrashAnalyzer logFileURLs]];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    avc.popoverPresentationController.sourceView = sender;
    avc.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:avc animated:YES completion:nil];
}

- (void)copyReport:(UIButton *)sender {
    UIPasteboard.generalPasteboard.string = [self.diagnosis reportText];
    UIButtonConfiguration *cfg = sender.configuration;
    NSString *old = cfg.title;
    cfg.title = @"Copied";
    cfg.image = [UIImage systemImageNamed:@"checkmark"];
    sender.configuration = cfg;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIButtonConfiguration *c = sender.configuration;
        c.title = old;
        c.image = [UIImage systemImageNamed:@"doc.on.doc"];
        sender.configuration = c;
    });
}

@end
