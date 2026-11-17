//
//  AccountLoginViewController.m
//  Amethyst
//
//  ★ [TERRA-STYLE] "Add an account" — Minecraft-launcher look (solid charcoal, square-ish
//  cards, crisp borders, green accents, bevelled block icons). Behaviour is unchanged:
//  - four tappable login-method cards (Microsoft / Ely.by / custom third-party / local)
//  - selection goes back to AccountListViewController through onSelectLoginType
//  - [ACCT-DUP]/[ACCT-DONE] re-entry guard and unlock rules kept as before
//  Cards use UIView + UITapGestureRecognizer (card.tag = type + 1), same as before.
//

#import "AccountLoginViewController.h"
#import "TerraStyle.h"
#import "utils.h"

/// Max content width on iPad / wide windows.
static const CGFloat kTerraLoginMaxWidth = 640;

@interface AccountLoginViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *cardStack;
@property (nonatomic, strong) UIView *headerContainer;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
// ★ [ACCT-DUP] 重入守卫：本页选中一种登录方式后即锁死，忽略后续点击，
//   避免快速双击触发两次登录（本地账户 = 两个随机 UUID = 两条相同账户）。
@property (nonatomic) BOOL ameLoginTypeSelected;
@end

@implementation AccountLoginViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"i18n_str_2", nil);
    [TerraStyle applyToViewController:self];
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // navigationController may not be attached yet in viewDidLoad; re-apply for the bar tint.
    [TerraStyle applyToViewController:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 确保 scrollView contentSize 正确
    [self.scrollView layoutIfNeeded];
}

#pragma mark - Setup

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = UIColor.clearColor;
    self.scrollView.delegate = self;
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scrollView];

    // Full-width content container; the column inside is centered and capped at 640pt.
    UIView *content = [[UIView alloc] init];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:content];

    UIStackView *column = [[UIStackView alloc] init];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.axis = UILayoutConstraintAxisVertical;
    column.alignment = UIStackViewAlignmentFill;
    column.spacing = 0;
    [content addSubview:column];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *fullWidth = [column.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-40];
    fullWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [content.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [content.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor],

        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-32],
        [column.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [column.widthAnchor constraintLessThanOrEqualToConstant:kTerraLoginMaxWidth],
        [column.widthAnchor constraintLessThanOrEqualToAnchor:content.widthAnchor constant:-40],
        fullWidth,
    ]];

    [self setupHeader];
    [column addArrangedSubview:self.headerContainer];
    [column setCustomSpacing:22 afterView:self.headerContainer];

    UILabel *methods = [TerraStyle sectionLabel:@"Sign-in method"];
    [column addArrangedSubview:methods];
    [column setCustomSpacing:10 afterView:methods];

    // 四张登录卡片
    self.cardStack = [[UIStackView alloc] init];
    self.cardStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardStack.axis = UILayoutConstraintAxisVertical;
    self.cardStack.spacing = 10;
    self.cardStack.alignment = UIStackViewAlignmentFill;
    [column addArrangedSubview:self.cardStack];

    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeMicrosoft
        title:localize(@"i18n_str_10", nil)
        description:@"Own Minecraft: Java Edition? Play online servers and Realms."
        symbol:@"xbox.logo" fallback:@"person.crop.square.fill"
        face:[UIColor colorWithRed:0.06 green:0.49 blue:0.06 alpha:1.0]
        primary:YES]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLittleSkin
        title:@"Ely.by"
        description:@"Free Ely.by account with custom skins."
        symbol:@"person.text.rectangle.fill" fallback:@"person.fill.viewfinder"
        face:[UIColor colorWithRed:0.16 green:0.42 blue:0.72 alpha:1.0]
        primary:NO]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeThirdParty
        title:localize(@"i18n_str_13", nil)
        description:@"Any authlib-injector (Yggdrasil) server."
        symbol:@"server.rack" fallback:@"globe"
        face:[UIColor colorWithRed:0.72 green:0.47 blue:0.12 alpha:1.0]
        primary:NO]];
    [self.cardStack addArrangedSubview:[self createLoginCardWithType:AccountLoginTypeLocal
        title:localize(@"i18n_str_15", nil)
        description:@"Offline — just pick a username."
        symbol:@"wifi.slash" fallback:@"person.fill"
        face:[UIColor colorWithWhite:0.36 alpha:1.0]
        primary:NO]];

    [column setCustomSpacing:16 afterView:self.cardStack];
    UILabel *note = [[UILabel alloc] init];
    note.text = @"Offline accounts can't join servers that require a Microsoft login.";
    note.font = TerraStyle.captionFont;
    note.textColor = TerraStyle.dimText;
    note.numberOfLines = 0;
    note.textAlignment = NSTextAlignmentCenter;
    [column addArrangedSubview:note];
}

/// Header: grass block + "MINECRAFT: JAVA EDITION" + title + one-line subtitle.
- (void)setupHeader {
    self.headerContainer = [[UIView alloc] init];
    self.headerContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *block = [TerraStyle grassBlockOfSize:40];
    [self.headerContainer addSubview:block];

    UILabel *edition = [TerraStyle sectionLabel:@"Minecraft: Java Edition"];
    edition.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerContainer addSubview:edition];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerTitleLabel.text = @"Add an account";
    self.headerTitleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy];
    self.headerTitleLabel.textColor = TerraStyle.text;
    self.headerTitleLabel.numberOfLines = 1;
    self.headerTitleLabel.adjustsFontSizeToFitWidth = YES;
    self.headerTitleLabel.minimumScaleFactor = 0.7;
    [self.headerContainer addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerSubtitleLabel.text = @"Choose how you want to sign in.";
    self.headerSubtitleLabel.font = TerraStyle.bodyFont;
    self.headerSubtitleLabel.textColor = TerraStyle.dimText;
    self.headerSubtitleLabel.numberOfLines = 0;
    [self.headerContainer addSubview:self.headerSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [block.leadingAnchor constraintEqualToAnchor:self.headerContainer.leadingAnchor],
        [block.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor constant:2],

        [edition.leadingAnchor constraintEqualToAnchor:block.trailingAnchor constant:14],
        [edition.trailingAnchor constraintLessThanOrEqualToAnchor:self.headerContainer.trailingAnchor],
        [edition.topAnchor constraintEqualToAnchor:self.headerContainer.topAnchor],

        [self.headerTitleLabel.topAnchor constraintEqualToAnchor:edition.bottomAnchor constant:2],
        [self.headerTitleLabel.leadingAnchor constraintEqualToAnchor:edition.leadingAnchor],
        [self.headerTitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],

        [self.headerSubtitleLabel.topAnchor constraintEqualToAnchor:self.headerTitleLabel.bottomAnchor constant:4],
        [self.headerSubtitleLabel.leadingAnchor constraintEqualToAnchor:edition.leadingAnchor],
        [self.headerSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerContainer.trailingAnchor],
        [self.headerSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.headerContainer.bottomAnchor],
        [self.headerContainer.bottomAnchor constraintGreaterThanOrEqualToAnchor:block.bottomAnchor],
    ]];
}

/// Square bevelled "block" icon tile: flat face, light top edge, dark bottom edge, dark outline.
- (UIView *)blockIconWithSymbol:(NSString *)symbol fallback:(NSString *)fallback face:(UIColor *)face {
    CGFloat size = 46;
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.userInteractionEnabled = NO;
    tile.backgroundColor = face;
    tile.layer.cornerRadius = 3;
    tile.layer.borderWidth = 2;
    tile.layer.borderColor = [UIColor colorWithWhite:0.07 alpha:1].CGColor;
    tile.clipsToBounds = YES;

    UIView *top = [[UIView alloc] init];
    top.translatesAutoresizingMaskIntoConstraints = NO;
    top.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    [tile addSubview:top];
    UIView *bottom = [[UIView alloc] init];
    bottom.translatesAutoresizingMaskIntoConstraints = NO;
    bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
    [tile addSubview:bottom];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:symbol withConfiguration:cfg] ?: [UIImage systemImageNamed:fallback withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeCenter;
    [tile addSubview:icon];

    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:size],
        [tile.heightAnchor constraintEqualToConstant:size],
        [top.topAnchor constraintEqualToAnchor:tile.topAnchor],
        [top.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
        [top.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
        [top.heightAnchor constraintEqualToConstant:4],
        [bottom.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor],
        [bottom.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor],
        [bottom.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor],
        [bottom.heightAnchor constraintEqualToConstant:5],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    return tile;
}

/// One login-method card: block icon + title (+ "Recommended" chip) + one-line description + chevron.
/// card.tag = type + 1 and a tap gesture → cardTapped: (unchanged mechanism).
- (UIView *)createLoginCardWithType:(AccountLoginType)type
                              title:(NSString *)title
                        description:(NSString *)description
                             symbol:(NSString *)symbol
                           fallback:(NSString *)fallback
                               face:(UIColor *)face
                            primary:(BOOL)primary {
    UIView *card = [TerraStyle cardView];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.userInteractionEnabled = YES;
    if (primary) {
        card.backgroundColor = TerraStyle.raised;
        card.layer.borderColor = TerraStyle.green.CGColor;
        card.layer.borderWidth = 1.5;
    }
    card.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", title, description];
    card.accessibilityTraits = UIAccessibilityTraitButton;
    card.isAccessibilityElement = YES;

    UIView *tile = [self blockIconWithSymbol:symbol fallback:fallback face:face];
    [card addSubview:tile];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    titleLabel.textColor = TerraStyle.text;
    titleLabel.numberOfLines = 1;
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel]];
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.alignment = UIStackViewAlignmentCenter;
    titleRow.spacing = 8;
    if (primary) {
        [titleRow addArrangedSubview:[TerraStyle chipWithText:@"RECOMMENDED" color:TerraStyle.greenBright]];
    }

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.text = description;
    descLabel.font = [UIFont systemFontOfSize:13];
    descLabel.textColor = TerraStyle.dimText;
    descLabel.numberOfLines = 2;

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, descLabel]];
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    texts.axis = UILayoutConstraintAxisVertical;
    texts.alignment = UIStackViewAlignmentLeading;
    texts.spacing = 3;
    texts.userInteractionEnabled = NO;
    [card addSubview:texts];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = primary ? TerraStyle.greenBright : TerraStyle.dimText;
    chevron.contentMode = UIViewContentModeCenter;
    chevron.userInteractionEnabled = NO;
    [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [card addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:76],

        [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [tile.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],

        [texts.leadingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:14],
        [texts.trailingAnchor constraintLessThanOrEqualToAnchor:chevron.leadingAnchor constant:-10],
        [texts.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [texts.topAnchor constraintGreaterThanOrEqualToAnchor:card.topAnchor constant:14],
        [texts.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-14],

        [chevron.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];

    // tag 从 1 开始，避免 0 被 UIKit 视为"未设置 tag"
    card.tag = type + 1;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    tapGesture.cancelsTouchesInView = NO;
    [card addGestureRecognizer:tapGesture];

    return card;
}

#pragma mark - Actions

/// 卡片点击处理（由 UITapGestureRecognizer 触发）
- (void)cardTapped:(UITapGestureRecognizer *)gesture {
    UIView *card = gesture.view;
    if (!card) return;
    // ★ [ACCT-DUP] 重入守卫：动画期间本页仍可接收点击 ⇒ 双击会触发两次 onSelectLoginType，
    //   进而发起两次登录（本地账户每次生成新随机 UUID ⇒ 冒出两条一模一样账户）。
    //   一旦选中即置位并锁死整页交互，忽略后续点击。
    if (self.ameLoginTypeSelected) return;
    self.ameLoginTypeSelected = YES;
    // ★ [ACCT-DONE] 只锁【会触发登录的卡片本身】(cardStack),不再 self.view.userInteractionEnabled = NO ——
    //   后者会把整页(含导航栏返回键)一起锁死,一旦宿主没消费选择就"进得去出不来"。
    self.cardStack.userInteractionEnabled = NO;

    // 还原 tag 偏移（createLoginCardWithType 中存储时 +1）
    AccountLoginType type = (AccountLoginType)(card.tag - 1);

    __weak typeof(self) weakSelf = self;
    // Press feedback: brief darken (block "pressed" look)
    [UIView animateWithDuration:0.1 animations:^{
        card.alpha = 0.65;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            card.alpha = 1.0;
        } completion:^(BOOL finished2) {
            if (weakSelf.onSelectLoginType) {
                weakSelf.onSelectLoginType(type);
            }
            // ★ [ACCT-DUP] 兜底解锁：若宿主未消费选择（不 pop 本页 / 回调为空），
            //   0.8s 后恢复交互，避免页面卡死；已 pop（view 不在 window 上）则无需恢复。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf && strongSelf.view.window) {
                    strongSelf.ameLoginTypeSelected = NO;
                    strongSelf.view.userInteractionEnabled = YES;      // ★ [ACCT-DONE] 双保险(整页)
                    strongSelf.cardStack.userInteractionEnabled = YES; // ★ [ACCT-DONE] 卡片栈
                }
            });
        }];
    }];
}

/// ★ [ACCT-DONE] 本页离开(被 pop / 被换走)时**无条件**复位选择锁与交互 —— 保证"选中一次
///   没被宿主消费"也不会把页面(或下一次进入)留在锁死态。
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.ameLoginTypeSelected = NO;
    self.view.userInteractionEnabled = YES;
    self.cardStack.userInteractionEnabled = YES;
}

@end
