//
//  TerraStyle.m
//  ★ [TERRA-STYLE] see TerraStyle.h
//

#import "TerraStyle.h"

// The bevelled buttons draw their own layers and deliberately use classic (non-configuration)
// UIButton layout, so the iOS 15 edge-inset deprecations do not apply here.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static UIColor *TSRGB(int r, int g, int b) { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }

#pragma mark - Bevelled block button

/// Flat face + top highlight + bottom bevel + dark outline; pressed = darker face, no bevel.
@interface TerraBlockButton : UIButton
@property(nonatomic, strong) UIColor *face;
@property(nonatomic, strong) UIColor *highlight;
@property(nonatomic, strong) UIColor *bevel;
@property(nonatomic, strong) CALayer *topLayer;
@property(nonatomic, strong) CALayer *bottomLayer;
@end

@implementation TerraBlockButton

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.topLayer) {
        self.topLayer = [CALayer layer];
        self.bottomLayer = [CALayer layer];
        [self.layer insertSublayer:self.topLayer atIndex:0];
        [self.layer insertSublayer:self.bottomLayer atIndex:0];
    }
    CGRect b = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.topLayer.frame = CGRectMake(0, 0, b.size.width, 3);
    self.bottomLayer.frame = CGRectMake(0, b.size.height - 4, b.size.width, 4);
    [self applyState];
    [CATransaction commit];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self applyState];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.45;
}

- (void)applyState {
    BOOL down = self.highlighted;
    self.backgroundColor = down ? self.bevel : self.face;
    self.topLayer.backgroundColor = (down ? UIColor.clearColor : self.highlight).CGColor;
    self.bottomLayer.backgroundColor = (down ? UIColor.clearColor : self.bevel).CGColor;
}

@end

#pragma mark - Sidebar row

@interface TerraSidebarRow : UIButton
@property(nonatomic, strong) UIView *selectionBar;
@end
@implementation TerraSidebarRow
@end

@implementation TerraStyle

+ (UIColor *)background  { return TSRGB(0x1E, 0x1E, 0x1E); }
+ (UIColor *)surface     { return TSRGB(0x26, 0x26, 0x26); }
+ (UIColor *)raised      { return TSRGB(0x31, 0x31, 0x31); }
+ (UIColor *)border      { return [UIColor colorWithWhite:1 alpha:0.08]; }
+ (UIColor *)green       { return TSRGB(0x3C, 0x85, 0x27); }
+ (UIColor *)greenBright { return TSRGB(0x52, 0xA5, 0x35); }
+ (UIColor *)greenDark   { return TSRGB(0x2A, 0x64, 0x1C); }
+ (UIColor *)text        { return UIColor.whiteColor; }
+ (UIColor *)dimText     { return [UIColor colorWithWhite:0.70 alpha:1]; }
+ (UIColor *)danger      { return TSRGB(0xE5, 0x53, 0x53); }
+ (UIColor *)warning     { return [UIColor colorWithRed:0.95 green:0.75 blue:0.20 alpha:1]; }

+ (UIFont *)titleFont    { return [UIFont systemFontOfSize:22 weight:UIFontWeightBold]; }
+ (UIFont *)headlineFont { return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]; }
+ (UIFont *)bodyFont     { return [UIFont systemFontOfSize:14]; }
+ (UIFont *)captionFont  { return [UIFont systemFontOfSize:12]; }
+ (UIFont *)sectionFont  { return [UIFont systemFontOfSize:11 weight:UIFontWeightHeavy]; }

+ (UIView *)cardView {
    UIView *v = [UIView new];
    v.backgroundColor = self.surface;
    v.layer.cornerRadius = 6;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.borderWidth = 1;
    v.layer.borderColor = self.border.CGColor;
    return v;
}

+ (UILabel *)sectionLabel:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text.uppercaseString;
    l.font = self.sectionFont;
    l.textColor = self.dimText;
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:l.text];
    [a addAttribute:NSKernAttributeName value:@1.2 range:NSMakeRange(0, a.length)];
    l.attributedText = a;
    return l;
}

+ (UIButton *)blockButtonWithFace:(UIColor *)face highlight:(UIColor *)hi bevel:(UIColor *)bevel
                            title:(NSString *)title symbol:(NSString *)symbol {
    TerraBlockButton *b = [TerraBlockButton buttonWithType:UIButtonTypeCustom];
    b.face = face; b.highlight = hi; b.bevel = bevel;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    if (symbol) {
        UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:
                        [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]];
        [b setImage:img forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
        b.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
    }
    b.contentEdgeInsets = UIEdgeInsetsMake(10, 18, 12, 18);
    b.layer.borderWidth = 2;
    b.layer.borderColor = TSRGB(0x12, 0x12, 0x12).CGColor;
    b.clipsToBounds = YES;
    b.backgroundColor = face;
    return b;
}

+ (UIButton *)blockButtonWithTitle:(NSString *)title symbol:(NSString *)symbol primary:(BOOL)primary {
    if (primary) {
        return [self blockButtonWithFace:self.green highlight:self.greenBright bevel:self.greenDark title:title symbol:symbol];
    }
    return [self blockButtonWithFace:TSRGB(0x48, 0x48, 0x48) highlight:TSRGB(0x6A, 0x6A, 0x6A) bevel:TSRGB(0x2C, 0x2C, 0x2C)
                               title:title symbol:symbol];
}

+ (UIButton *)dangerButtonWithTitle:(NSString *)title symbol:(NSString *)symbol {
    return [self blockButtonWithFace:TSRGB(0xB8, 0x3B, 0x3B) highlight:TSRGB(0xD9, 0x5C, 0x5C) bevel:TSRGB(0x7A, 0x22, 0x22)
                               title:title symbol:symbol];
}

+ (UILabel *)chipWithText:(NSString *)text color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:@"  %@  ", text];
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    l.textColor = color;
    l.backgroundColor = [color colorWithAlphaComponent:0.16];
    l.layer.cornerRadius = 4;
    l.layer.masksToBounds = YES;
    [l setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [l.heightAnchor constraintEqualToConstant:20].active = YES;
    return l;
}

+ (UIView *)grassBlockOfSize:(CGFloat)size {
    UIView *v = [UIView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.userInteractionEnabled = NO;
    NSArray<UIColor *> *dirt = @[[UIColor colorWithRed:0.52 green:0.36 blue:0.24 alpha:1],
                                 [UIColor colorWithRed:0.44 green:0.30 blue:0.20 alpha:1],
                                 [UIColor colorWithRed:0.60 green:0.43 blue:0.29 alpha:1]];
    NSArray<UIColor *> *grass = @[[UIColor colorWithRed:0.38 green:0.62 blue:0.24 alpha:1],
                                  [UIColor colorWithRed:0.32 green:0.54 blue:0.20 alpha:1]];
    const int grid[4][4] = {{0,0,0,0},{0,1,0,2},{3,2,1,2},{2,1,3,1}};
    CGFloat cell = size / 4.0;
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) {
        UIView *px = [[UIView alloc] initWithFrame:CGRectMake(c * cell, r * cell, cell, cell)];
        int val = grid[r][c];
        px.backgroundColor = val == 0 ? grass[(r + c) % 2] : dirt[val - 1];
        [v addSubview:px];
    }
    [v.widthAnchor constraintEqualToConstant:size].active = YES;
    [v.heightAnchor constraintEqualToConstant:size].active = YES;
    return v;
}

+ (UIButton *)sidebarRowWithTitle:(NSString *)title symbol:(NSString *)symbol {
    TerraSidebarRow *b = [TerraSidebarRow buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:self.dimText forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 12);
    if (symbol) {
        [b setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
        b.tintColor = self.dimText;
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 10, 0, -10);
    }
    b.layer.cornerRadius = 4;
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.whiteColor;
    bar.hidden = YES;
    [b addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:b.leadingAnchor],
        [bar.centerYAnchor constraintEqualToAnchor:b.centerYAnchor],
        [bar.widthAnchor constraintEqualToConstant:3],
        [bar.heightAnchor constraintEqualToConstant:22],
        [b.heightAnchor constraintGreaterThanOrEqualToConstant:42],
    ]];
    b.selectionBar = bar;
    return b;
}

+ (void)setSidebarRow:(UIButton *)row selected:(BOOL)selected {
    UIColor *fg = selected ? self.text : self.dimText;
    [row setTitleColor:fg forState:UIControlStateNormal];
    row.tintColor = fg;
    row.titleLabel.font = [UIFont systemFontOfSize:15 weight:selected ? UIFontWeightBold : UIFontWeightMedium];
    row.backgroundColor = selected ? [UIColor colorWithWhite:1 alpha:0.06] : UIColor.clearColor;
    if ([row isKindOfClass:TerraSidebarRow.class]) ((TerraSidebarRow *)row).selectionBar.hidden = !selected;
}

+ (UISearchTextField *)searchFieldWithPlaceholder:(NSString *)placeholder {
    UISearchTextField *f = [UISearchTextField new];
    f.placeholder = placeholder;
    f.backgroundColor = self.raised;
    f.textColor = self.text;
    f.tintColor = self.greenBright;
    f.font = [UIFont systemFontOfSize:15];
    f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{NSForegroundColorAttributeName: self.dimText}];
    f.layer.cornerRadius = 6;
    f.layer.borderWidth = 1;
    f.layer.borderColor = self.border.CGColor;
    [f.heightAnchor constraintGreaterThanOrEqualToConstant:40].active = YES;
    return f;
}

+ (void)applyToViewController:(UIViewController *)vc {
    vc.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    vc.view.backgroundColor = self.background;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = self.background;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor,
                               NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]};
    vc.navigationItem.standardAppearance = ap;
    vc.navigationItem.scrollEdgeAppearance = ap;
    vc.navigationItem.compactAppearance = ap;
    if (vc.navigationController) {
        vc.navigationController.navigationBar.tintColor = self.greenBright;
        vc.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
}

@end
