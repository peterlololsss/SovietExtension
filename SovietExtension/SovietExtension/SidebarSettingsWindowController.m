#import "SidebarSettingsWindowController.h"

#import "SidebarManager.h"
#import <QuartzCore/QuartzCore.h>


static const NSInteger kYMSidebarSettingsLabelRoleTitle = 9201;
static const NSInteger kYMSidebarSettingsLabelRolePrimary = 9202;
static const NSInteger kYMSidebarSettingsLabelRoleSubtitle = 9203;
static const NSInteger kYMSidebarSettingsLabelRoleSecondary = 9204;
static NSPasteboardType const kYMSidebarSettingsPasteboardType =
    @"com.mustangym.SovietExtension.sidebar-entry.v2";

// Panel metrics, typography, and colors, kept in one place so the layout
// stays on a 4 pt grid and follows the current Aqua or Dark Aqua appearance.
typedef struct {
    CGFloat panelWidth;
    CGFloat panelHeight;
    CGFloat panelMinimumWidth;
    CGFloat panelMinimumHeight;
    CGFloat footerHeight;
    CGFloat separatorHeight;
    CGFloat bodyTopPadding;
    CGFloat headingHorizontalInset;
    CGFloat titleHeight;
    CGFloat titleSubtitleGap;
    CGFloat subtitleHeight;
    CGFloat subtitleCardGap;
    CGFloat cardOuterMargin;
    CGFloat cardGap;
    CGFloat bodyBottomPadding;
    CGFloat cardPadding;
    CGFloat groupLabelHeight;
    CGFloat headingTableGap;
    CGFloat tableActionGap;
    CGFloat moveButtonWidth;
    CGFloat moveButtonHeight;
    CGFloat compactGap;
    CGFloat cardCornerRadius;
    CGFloat cardBorderWidth;
    CGFloat minimumRowHeight;
    CGFloat rowVerticalRoom;
    CGFloat statusOriginY;
    CGFloat statusHeight;
    CGFloat statusMinimumWidth;
    CGFloat statusTrailingRoom;
    CGFloat footerButtonOriginY;
    CGFloat footerButtonHeight;
    CGFloat cancelButtonWidth;
    CGFloat saveButtonWidth;
    CGFloat rowCheckboxLeadingInset;
    CGFloat rowCheckboxVerticalInset;
    CGFloat rowCheckboxTrailingRoom;
    CGFloat dragHandleRightInset;
    CGFloat dragHandleWidth;
    CGFloat dragHandleVerticalInset;
    CGFloat dragLineInset;
    CGFloat dragLineSpacing;
    CGFloat dragLineWidth;
    CGFloat scrollEdgeTolerance;
} YMSidebarSettingsDesignMetrics;

static const YMSidebarSettingsDesignMetrics kYMSidebarDesignMetrics = {
    .panelWidth = 620.0,
    .panelHeight = 640.0,
    .panelMinimumWidth = 580.0,
    .panelMinimumHeight = 560.0,
    .footerHeight = 68.0,
    .separatorHeight = 1.0,
    .bodyTopPadding = 24.0,
    .headingHorizontalInset = 32.0,
    .titleHeight = 28.0,
    .titleSubtitleGap = 4.0,
    .subtitleHeight = 16.0,
    .subtitleCardGap = 8.0,
    .cardOuterMargin = 24.0,
    .cardGap = 8.0,
    .bodyBottomPadding = 12.0,
    .cardPadding = 16.0,
    .groupLabelHeight = 16.0,
    .headingTableGap = 8.0,
    .tableActionGap = 8.0,
    .moveButtonWidth = 68.0,
    .moveButtonHeight = 28.0,
    .compactGap = 8.0,
    .cardCornerRadius = 18.0,
    .cardBorderWidth = 1.0,
    .minimumRowHeight = 36.0,
    .rowVerticalRoom = 16.0,
    .statusOriginY = 24.0,
    .statusHeight = 20.0,
    .statusMinimumWidth = 140.0,
    .statusTrailingRoom = 48.0,
    .footerButtonOriginY = 20.0,
    .footerButtonHeight = 32.0,
    .cancelButtonWidth = 80.0,
    .saveButtonWidth = 84.0,
    .rowCheckboxLeadingInset = 8.0,
    .rowCheckboxVerticalInset = 4.0,
    .rowCheckboxTrailingRoom = 48.0,
    .dragHandleRightInset = 16.0,
    .dragHandleWidth = 24.0,
    .dragHandleVerticalInset = 8.0,
    .dragLineInset = 6.0,
    .dragLineSpacing = 4.0,
    .dragLineWidth = 1.25,
    .scrollEdgeTolerance = 0.5,
};

typedef NS_ENUM(NSInteger, YMSidebarSettingsTypographyToken) {
    YMSidebarTypographyPanelTitle,
    YMSidebarTypographyRowTitle,
    YMSidebarTypographySectionLabel,
    YMSidebarTypographySubtitle,
    YMSidebarTypographySecondaryNote,
};

static NSFont *YMFontForTypographyToken(
    YMSidebarSettingsTypographyToken token)
{
    switch (token) {
        case YMSidebarTypographyPanelTitle:
            return [NSFont systemFontOfSize:22.0
                                     weight:NSFontWeightSemibold];
        case YMSidebarTypographyRowTitle:
            return [NSFont systemFontOfSize:14.0
                                     weight:NSFontWeightMedium];
        case YMSidebarTypographySectionLabel:
            return [NSFont systemFontOfSize:13.0
                                     weight:NSFontWeightMedium];
        case YMSidebarTypographySecondaryNote:
            return [NSFont systemFontOfSize:11.0
                                     weight:NSFontWeightRegular];
        case YMSidebarTypographySubtitle:
        default:
            return [NSFont systemFontOfSize:12.0
                                     weight:NSFontWeightRegular];
    }
}

typedef NS_ENUM(NSInteger, YMSidebarSettingsColorToken) {
    YMSidebarColorYMWindowSurface,
    YMSidebarColorYMContentSurface,
    YMSidebarColorYMCardSurface,
    YMSidebarColorYMCardBorder,
    YMSidebarColorYMTextTitle,
    YMSidebarColorYMTextPrimary,
    YMSidebarColorYMTextValue,
    YMSidebarColorYMTextSubtitle,
    YMSidebarColorYMTextSecondary,
    YMSidebarColorStatusReady,
    YMSidebarColorStatusWarning,
    YMSidebarColorStatusError,
};

static NSColor *YMStatusColorDerivedFromNativeColor(NSColor *semanticColor,
                                                     BOOL light)
{
    NSAppearance *appearance = [NSAppearance appearanceNamed:
        light ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    __block NSColor *resolvedColor = nil;
    [appearance performAsCurrentDrawingAppearance:^{
        CGFloat anchorFraction = light ? 0.58 : 0.32;
        NSColor *blended =
            [semanticColor blendedColorWithFraction:anchorFraction
                                             ofColor:NSColor.labelColor] ?:
            NSColor.labelColor;
        resolvedColor =
            [blended colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?:
            blended;
    }];
    return resolvedColor ?: NSColor.labelColor;
}

static NSColor *YMSubtitleColorForDesignMode(BOOL light)
{
    NSAppearance *appearance = [NSAppearance appearanceNamed:
        light ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    __block NSColor *resolvedColor = nil;
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *subtitle =
            [NSColor.labelColor colorWithAlphaComponent:light ? 0.70 : 0.72];
        resolvedColor =
            [subtitle colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?:
            subtitle;
    }];
    return resolvedColor ?: NSColor.labelColor;
}

static NSColor *YMColorForDesignToken(YMSidebarSettingsColorToken token,
                                      BOOL light)
{
    switch (token) {
        case YMSidebarColorYMWindowSurface:
            return light
                ? [NSColor colorWithCalibratedWhite:0.96 alpha:0.98]
                : [NSColor colorWithCalibratedWhite:0.08 alpha:0.96];
        case YMSidebarColorYMContentSurface:
            return light
                ? [NSColor colorWithCalibratedWhite:0.94 alpha:0.98]
                : [NSColor colorWithCalibratedWhite:0.06 alpha:0.96];
        case YMSidebarColorYMCardSurface:
            return light
                ? [NSColor colorWithCalibratedWhite:1.00 alpha:0.82]
                : [NSColor colorWithCalibratedWhite:0.12 alpha:0.78];
        case YMSidebarColorYMCardBorder:
            return light
                ? [NSColor colorWithCalibratedWhite:0.0 alpha:0.08]
                : [NSColor colorWithCalibratedWhite:1.0 alpha:0.10];
        case YMSidebarColorYMTextTitle:
            return [NSColor colorWithCalibratedWhite:light ? 0.08 : 0.98
                                                       alpha:1.0];
        case YMSidebarColorYMTextPrimary:
            return [NSColor colorWithCalibratedWhite:light ? 0.16 : 0.92
                                                       alpha:1.0];
        case YMSidebarColorYMTextValue:
            return [NSColor colorWithCalibratedWhite:light ? 0.24 : 0.86
                                                       alpha:1.0];
        case YMSidebarColorYMTextSubtitle:
            return YMSubtitleColorForDesignMode(light);
        case YMSidebarColorYMTextSecondary:
            return [NSColor colorWithCalibratedWhite:light ? 0.52 : 0.62
                                                       alpha:1.0];
        case YMSidebarColorStatusReady:
            return YMStatusColorDerivedFromNativeColor(NSColor.systemGreenColor,
                                                        light);
        case YMSidebarColorStatusWarning:
            return YMStatusColorDerivedFromNativeColor(NSColor.systemOrangeColor,
                                                        light);
        case YMSidebarColorStatusError:
            return YMStatusColorDerivedFromNativeColor(NSColor.systemRedColor,
                                                        light);
    }
    return NSColor.labelColor;
}

@interface YMSidebarSettingsTableView : NSTableView
@property(nonatomic, assign) id spaceTarget;
@property(nonatomic) SEL spaceAction;
@end

@implementation YMSidebarSettingsTableView

- (void)keyDown:(NSEvent *)event
{
    if ([event.charactersIgnoringModifiers isEqualToString:@" "] &&
        self.selectedRow >= 0 && self.spaceAction != nil) {
        [NSApp sendAction:self.spaceAction to:self.spaceTarget from:self];
        return;
    }
    [super keyDown:event];
}

@end

@interface YMSidebarSettingsEntryButton : NSButton
@property(nonatomic, copy) NSString *entryIdentifier;
@end

@implementation YMSidebarSettingsEntryButton
@end

@interface YMSidebarSettingsDragHandleView : NSView
@end

@implementation YMSidebarSettingsDragHandleView

- (NSView *)hitTest:(NSPoint)point
{
    (void)point;
    return nil;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [NSColor.tertiaryLabelColor setStroke];
    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = kYMSidebarDesignMetrics.dragLineWidth;
    CGFloat middle = NSMidY(self.bounds);
    CGFloat lineSpacing = kYMSidebarDesignMetrics.dragLineSpacing;
    for (CGFloat offset = -lineSpacing;
         offset <= lineSpacing;
         offset += lineSpacing) {
        CGFloat inset = kYMSidebarDesignMetrics.dragLineInset;
        [path moveToPoint:NSMakePoint(inset, middle + offset)];
        [path lineToPoint:NSMakePoint(NSWidth(self.bounds) - inset,
                                      middle + offset)];
    }
    [path stroke];
}

@end

// Row cell whose drag image is a faithful snapshot of the whole cell.
//
// The row's visible label is the checkbox's own title (an NSButtonTypeSwitch),
// and the cell sets no `textField`/`imageView` outlets. NSTableCellView's
// default `draggingImageComponents` are derived from exactly those outlets, so
// with them nil the default drag image does not match the rendered row — which
// makes the title appear to jump horizontally while dragging. Snapshotting the
// whole cell at its own bounds keeps the drag image aligned with the row. This
// only affects the in-flight drag image; the settled/reload layout (verified
// stable elsewhere) is untouched.
@interface YMSidebarSettingsEntryCell : NSTableCellView
@end

@implementation YMSidebarSettingsEntryCell

- (NSArray<NSDraggingImageComponent *> *)draggingImageComponents
{
    const NSRect bounds = self.bounds;
    if (NSIsEmptyRect(bounds)) {
        return [super draggingImageComponents];
    }
    NSBitmapImageRep *rep =
        [self bitmapImageRepForCachingDisplayInRect:bounds];
    if (rep == nil) {
        return [super draggingImageComponents];
    }
    [self cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
    [image addRepresentation:rep];
    NSDraggingImageComponent *component = [NSDraggingImageComponent
        draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
    component.contents = image;
    // MEASURED, not inferred: AppKit sets the dragging item's frame to the
    // CELL's rect in table coordinates (logged as {{16,y},{540,36}} against a
    // row of {{0,y},{572,36}}), and a component frame is relative to that. So
    // the correct value here is the cell's own bounds at the origin. An earlier
    // attempt used the cell's offset within the row, which pushed the image one
    // inset to the right.
    //
    // Note the horizontal shift this once chased was never the drag image: it
    // was the table being wider than its clip view and scrolling sideways. See
    // the column-width correction in the table layout.
    component.frame = NSMakeRect(0, 0, NSWidth(bounds), NSHeight(bounds));
    return @[ component ];
}

@end

@interface SidebarSettingsWindowController ()
    <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NSVisualEffectView *effectView;
@property(nonatomic, strong) NSView *rootContentView;
@property(nonatomic, strong) NSScrollView *contentScrollView;
@property(nonatomic, strong) NSView *scrollDocumentView;
@property(nonatomic, strong) NSView *footerView;
@property(nonatomic, strong) NSBox *footerSeparator;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *primaryGroupLabel;
@property(nonatomic, strong) NSTextField *secondaryGroupLabel;
@property(nonatomic, strong) NSView *primaryCard;
@property(nonatomic, strong) NSView *secondaryCard;
@property(nonatomic, strong) NSScrollView *primaryTableScrollView;
@property(nonatomic, strong) NSScrollView *secondaryTableScrollView;
@property(nonatomic, strong) YMSidebarSettingsTableView *primaryTable;
@property(nonatomic, strong) YMSidebarSettingsTableView *secondaryTable;
@property(nonatomic, strong) NSButton *primaryMoveUpButton;
@property(nonatomic, strong) NSButton *primaryMoveDownButton;
@property(nonatomic, strong) NSButton *secondaryMoveUpButton;
@property(nonatomic, strong) NSButton *secondaryMoveDownButton;
@property(nonatomic, strong) NSButton *cancelButton;
@property(nonatomic, strong) NSButton *saveButton;
@property(nonatomic, strong) YMSidebarSettingsDraft *draft;
@property(nonatomic, copy) NSString *inlineMessage;
@property(nonatomic) CGFloat rowHeight;
@property(nonatomic) BOOL updatingSelection;
@property(nonatomic) BOOL pinScrollToTop;
@end

@implementation SidebarSettingsWindowController

- (instancetype)init
{
    NSPanel *panel = [SidebarSettingsWindowController ym_createPanel];
    self = [super initWithWindow:panel];
    if (self) {
        self.rowHeight = [self ym_resolvedRowHeight];
        panel.delegate = self;
        [self ym_buildInterfaceInView:panel.contentView];
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(ym_sidebarStateDidChange:)
                   name:YMNavigationSidebarStateDidChangeNotification
                 object:nil];
        [self ym_reloadDraftFromManager];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

+ (NSPanel *)ym_createPanel
{
    NSRect frame = NSMakeRect(0, 0,
                              kYMSidebarDesignMetrics.panelWidth,
                              kYMSidebarDesignMetrics.panelHeight);
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.title = @"管理左侧入口";
    panel.contentMinSize = NSMakeSize(
        kYMSidebarDesignMetrics.panelMinimumWidth,
        kYMSidebarDesignMetrics.panelMinimumHeight);
    panel.releasedWhenClosed = NO;
    panel.movableByWindowBackground = YES;
    panel.level = NSFloatingWindowLevel;
    panel.opaque = NO;

    NSView *contentView = [[NSView alloc] initWithFrame:frame];
    contentView.wantsLayer = YES;
    panel.contentView = contentView;
    return panel;
}

- (void)showWindowCentered
{
    [SidebarManager registerDefaults];
    if (!self.window.isVisible) {
        [self ym_reloadDraftFromManager];
        [self.window center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (CGFloat)ym_resolvedRowHeight
{
    NSFont *font = YMFontForTypographyToken(YMSidebarTypographyRowTitle);
    CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading);
    return MAX(kYMSidebarDesignMetrics.minimumRowHeight,
               lineHeight + kYMSidebarDesignMetrics.rowVerticalRoom);
}

- (void)ym_buildInterfaceInView:(NSView *)contentView
{
    self.rootContentView = contentView;

    self.effectView = [[NSVisualEffectView alloc] initWithFrame:contentView.bounds];
    self.effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.effectView.material = NSVisualEffectMaterialUnderWindowBackground;
    self.effectView.state = NSVisualEffectStateActive;
    [contentView addSubview:self.effectView];

    self.contentScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.contentScrollView.drawsBackground = NO;
    self.contentScrollView.borderType = NSNoBorder;
    self.contentScrollView.hasHorizontalScroller = NO;
    self.contentScrollView.hasVerticalScroller = YES;
    self.contentScrollView.autohidesScrollers = YES;
    self.contentScrollView.scrollerStyle = NSScrollerStyleOverlay;
    [contentView addSubview:self.contentScrollView];

    self.scrollDocumentView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.scrollDocumentView.wantsLayer = YES;
    self.contentScrollView.documentView = self.scrollDocumentView;

    self.titleLabel = [self ym_labelWithText:@"管理左侧入口"
                                        font:YMFontForTypographyToken(
                                            YMSidebarTypographyPanelTitle)
                                        role:kYMSidebarSettingsLabelRoleTitle];
    self.titleLabel.accessibilityRole = NSAccessibilityHeadingRole;
    [self.scrollDocumentView addSubview:self.titleLabel];

    self.subtitleLabel = [self ym_labelWithText:@"选择要显示的入口，并在各分组内调整顺序"
                                           font:YMFontForTypographyToken(
                                               YMSidebarTypographySubtitle)
                                           role:kYMSidebarSettingsLabelRoleSubtitle];
    [self.scrollDocumentView addSubview:self.subtitleLabel];

    self.primaryCard = [self ym_cardView];
    self.secondaryCard = [self ym_cardView];
    [self.scrollDocumentView addSubview:self.primaryCard];
    [self.scrollDocumentView addSubview:self.secondaryCard];

    self.primaryGroupLabel = [self ym_labelWithText:@"主要入口"
                                               font:YMFontForTypographyToken(
                                                   YMSidebarTypographySectionLabel)
                                               role:kYMSidebarSettingsLabelRolePrimary];
    self.secondaryGroupLabel = [self ym_labelWithText:@"发现与服务"
                                                 font:YMFontForTypographyToken(
                                                     YMSidebarTypographySectionLabel)
                                                 role:kYMSidebarSettingsLabelRolePrimary];
    [self.primaryCard addSubview:self.primaryGroupLabel];
    [self.secondaryCard addSubview:self.secondaryGroupLabel];

    self.primaryTable = [self ym_tableForGroup:@"primary" title:@"主要入口"];
    self.secondaryTable = [self ym_tableForGroup:@"secondary" title:@"发现与服务"];
    self.primaryTableScrollView = [self ym_scrollViewForTable:self.primaryTable];
    self.secondaryTableScrollView = [self ym_scrollViewForTable:self.secondaryTable];
    [self.primaryCard addSubview:self.primaryTableScrollView];
    [self.secondaryCard addSubview:self.secondaryTableScrollView];

    self.primaryMoveUpButton = [self ym_moveButtonWithTitle:@"上移"
                                                  identifier:@"sidebar.primary.moveUp"
                                                      action:@selector(ym_moveSelection:)];
    self.primaryMoveDownButton = [self ym_moveButtonWithTitle:@"下移"
                                                    identifier:@"sidebar.primary.moveDown"
                                                        action:@selector(ym_moveSelection:)];
    self.secondaryMoveUpButton = [self ym_moveButtonWithTitle:@"上移"
                                                    identifier:@"sidebar.secondary.moveUp"
                                                        action:@selector(ym_moveSelection:)];
    self.secondaryMoveDownButton = [self ym_moveButtonWithTitle:@"下移"
                                                      identifier:@"sidebar.secondary.moveDown"
                                                          action:@selector(ym_moveSelection:)];
    [self.primaryCard addSubview:self.primaryMoveUpButton];
    [self.primaryCard addSubview:self.primaryMoveDownButton];
    [self.secondaryCard addSubview:self.secondaryMoveUpButton];
    [self.secondaryCard addSubview:self.secondaryMoveDownButton];

    self.footerView = [[NSView alloc] initWithFrame:NSZeroRect];
    [contentView addSubview:self.footerView];
    self.footerSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    self.footerSeparator.boxType = NSBoxSeparator;
    [self.footerView addSubview:self.footerSeparator];

    self.statusLabel = [self ym_labelWithText:@""
                                         font:YMFontForTypographyToken(
                                             YMSidebarTypographySubtitle)
                                         role:kYMSidebarSettingsLabelRoleSubtitle];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.footerView addSubview:self.statusLabel];

    self.cancelButton = [NSButton buttonWithTitle:@"取消"
                                           target:self
                                           action:@selector(ym_cancel:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.keyEquivalent = @"\033";
    self.cancelButton.identifier = @"sidebar.cancel";
    [self.footerView addSubview:self.cancelButton];

    self.saveButton = [NSButton buttonWithTitle:@"保存"
                                         target:self
                                         action:@selector(ym_save:)];
    self.saveButton.bezelStyle = NSBezelStyleRounded;
    self.saveButton.keyEquivalent = @"\r";
    self.saveButton.identifier = @"sidebar.save";
    [self.footerView addSubview:self.saveButton];
    self.window.defaultButtonCell = self.saveButton.cell;

    self.primaryTable.nextKeyView = self.secondaryTable;
    self.secondaryTable.nextKeyView = self.primaryMoveUpButton;
    self.primaryMoveUpButton.nextKeyView = self.primaryMoveDownButton;
    self.primaryMoveDownButton.nextKeyView = self.secondaryMoveUpButton;
    self.secondaryMoveUpButton.nextKeyView = self.secondaryMoveDownButton;
    self.secondaryMoveDownButton.nextKeyView = self.cancelButton;
    self.cancelButton.nextKeyView = self.saveButton;
    self.saveButton.nextKeyView = self.primaryTable;
    self.window.initialFirstResponder = self.primaryTable;

    [self ym_layoutInterface];
    [self ym_applyAdaptiveAppearance];
}

- (YMSidebarSettingsTableView *)ym_tableForGroup:(NSString *)group
                                            title:(NSString *)title
{
    YMSidebarSettingsTableView *table =
        [[YMSidebarSettingsTableView alloc] initWithFrame:NSZeroRect];
    table.identifier = [NSString stringWithFormat:@"sidebar.%@.table", group];
    table.headerView = nil;
    table.delegate = self;
    table.dataSource = self;
    table.rowHeight = self.rowHeight;
    table.intercellSpacing = NSZeroSize;
    table.backgroundColor = NSColor.clearColor;
    table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    table.allowsEmptySelection = YES;
    table.allowsMultipleSelection = NO;
    table.focusRingType = NSFocusRingTypeDefault;
    table.accessibilityLabel = title;
    table.accessibilityIdentifier = table.identifier;
    [table registerForDraggedTypes:@[kYMSidebarSettingsPasteboardType]];
    [table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    [table setDraggingSourceOperationMask:NSDragOperationNone forLocal:NO];

    NSTableColumn *column = [[NSTableColumn alloc]
        initWithIdentifier:@"sidebar.entry.column"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [table addTableColumn:column];

    table.spaceTarget = self;
    table.spaceAction = @selector(ym_toggleSelectedRowInTable:);
    return table;
}

- (NSScrollView *)ym_scrollViewForTable:(NSTableView *)table
{
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.documentView = table;
    scrollView.drawsBackground = NO;
    scrollView.borderType = NSNoBorder;
    scrollView.hasHorizontalScroller = NO;
    scrollView.hasVerticalScroller = NO;
    return scrollView;
}

- (NSButton *)ym_moveButtonWithTitle:(NSString *)title
                           identifier:(NSString *)identifier
                               action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.identifier = identifier;
    button.accessibilityLabel = title;
    return button;
}

- (NSView *)ym_cardView
{
    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.wantsLayer = YES;
    view.layer.cornerRadius = kYMSidebarDesignMetrics.cardCornerRadius;
    view.layer.masksToBounds = YES;
    view.layer.borderWidth = kYMSidebarDesignMetrics.cardBorderWidth;
    return view;
}

- (NSTextField *)ym_labelWithText:(NSString *)text
                              font:(NSFont *)font
                              role:(NSInteger)role
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.stringValue = text ?: @"";
    label.font = font;
    label.tag = role;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.lineBreakMode = NSLineBreakByClipping;
    return label;
}

- (CGFloat)ym_cardHeightForRows:(NSInteger)rowCount
{
    CGFloat fixedHeight = 2.0 * kYMSidebarDesignMetrics.cardPadding +
        kYMSidebarDesignMetrics.groupLabelHeight +
        kYMSidebarDesignMetrics.headingTableGap +
        kYMSidebarDesignMetrics.tableActionGap +
        kYMSidebarDesignMetrics.moveButtonHeight;
    return fixedHeight + self.rowHeight * rowCount;
}

- (void)ym_layoutInterface
{
    NSRect previousVisibleRect = self.contentScrollView.documentVisibleRect;
    CGFloat previousDocumentHeight = NSHeight(self.scrollDocumentView.frame);
    BOOL keepTopVisible = self.pinScrollToTop ||
        previousDocumentHeight <= NSHeight(previousVisibleRect) +
                                      kYMSidebarDesignMetrics.scrollEdgeTolerance ||
        NSMaxY(previousVisibleRect) >= previousDocumentHeight -
                                           kYMSidebarDesignMetrics.scrollEdgeTolerance;
    NSRect bounds = self.rootContentView.bounds;
    CGFloat availableHeight = MAX(0.0, NSHeight(bounds) -
                                          kYMSidebarDesignMetrics.footerHeight);
    CGFloat primaryHeight = [self ym_cardHeightForRows:3];
    CGFloat secondaryHeight = [self ym_cardHeightForRows:5];
    CGFloat requiredHeight = kYMSidebarDesignMetrics.bodyTopPadding +
        kYMSidebarDesignMetrics.titleHeight +
        kYMSidebarDesignMetrics.titleSubtitleGap +
        kYMSidebarDesignMetrics.subtitleHeight +
        kYMSidebarDesignMetrics.subtitleCardGap +
        primaryHeight + kYMSidebarDesignMetrics.cardGap +
        secondaryHeight + kYMSidebarDesignMetrics.bodyBottomPadding;
    CGFloat documentHeight = MAX(availableHeight, requiredHeight);

    self.effectView.frame = bounds;
    self.footerView.frame = NSMakeRect(0, 0, NSWidth(bounds),
                                       kYMSidebarDesignMetrics.footerHeight);
    self.footerSeparator.frame = NSMakeRect(0,
        kYMSidebarDesignMetrics.footerHeight -
            kYMSidebarDesignMetrics.separatorHeight,
        NSWidth(bounds), kYMSidebarDesignMetrics.separatorHeight);
    self.contentScrollView.frame =
        NSMakeRect(0, kYMSidebarDesignMetrics.footerHeight,
                   NSWidth(bounds), availableHeight);
    self.scrollDocumentView.frame =
        NSMakeRect(0, 0, NSWidth(bounds), documentHeight);

    CGFloat headingInset = kYMSidebarDesignMetrics.headingHorizontalInset;
    CGFloat headingWidth = MAX(0.0, NSWidth(bounds) - 2.0 * headingInset);
    CGFloat top = documentHeight - kYMSidebarDesignMetrics.bodyTopPadding;
    self.titleLabel.frame = NSMakeRect(
        headingInset, top - kYMSidebarDesignMetrics.titleHeight,
        headingWidth, kYMSidebarDesignMetrics.titleHeight);
    top -= kYMSidebarDesignMetrics.titleHeight +
        kYMSidebarDesignMetrics.titleSubtitleGap;
    self.subtitleLabel.frame = NSMakeRect(
        headingInset, top - kYMSidebarDesignMetrics.subtitleHeight,
        headingWidth, kYMSidebarDesignMetrics.subtitleHeight);
    top -= kYMSidebarDesignMetrics.subtitleHeight +
        kYMSidebarDesignMetrics.subtitleCardGap;

    CGFloat cardMargin = kYMSidebarDesignMetrics.cardOuterMargin;
    CGFloat cardWidth = MAX(0.0, NSWidth(bounds) - 2.0 * cardMargin);
    self.primaryCard.frame = NSMakeRect(cardMargin, top - primaryHeight,
                                        cardWidth,
                                        primaryHeight);
    top -= primaryHeight + kYMSidebarDesignMetrics.cardGap;
    self.secondaryCard.frame = NSMakeRect(cardMargin, top - secondaryHeight,
                                          cardWidth,
                                          secondaryHeight);

    [self ym_layoutCard:self.primaryCard
                  label:self.primaryGroupLabel
             tableScroll:self.primaryTableScrollView
                   table:self.primaryTable
                  moveUp:self.primaryMoveUpButton
                moveDown:self.primaryMoveDownButton
                rowCount:3];
    [self ym_layoutCard:self.secondaryCard
                  label:self.secondaryGroupLabel
             tableScroll:self.secondaryTableScrollView
                   table:self.secondaryTable
                  moveUp:self.secondaryMoveUpButton
                moveDown:self.secondaryMoveDownButton
                rowCount:5];

    CGFloat saveX = NSWidth(bounds) - cardMargin -
        kYMSidebarDesignMetrics.saveButtonWidth;
    CGFloat cancelX = saveX - kYMSidebarDesignMetrics.compactGap -
        kYMSidebarDesignMetrics.cancelButtonWidth;
    self.statusLabel.frame = NSMakeRect(
        headingInset, kYMSidebarDesignMetrics.statusOriginY,
        MAX(kYMSidebarDesignMetrics.statusMinimumWidth,
            cancelX - kYMSidebarDesignMetrics.statusTrailingRoom),
        kYMSidebarDesignMetrics.statusHeight);
    self.cancelButton.frame = NSMakeRect(
        cancelX, kYMSidebarDesignMetrics.footerButtonOriginY,
        kYMSidebarDesignMetrics.cancelButtonWidth,
        kYMSidebarDesignMetrics.footerButtonHeight);
    self.saveButton.frame = NSMakeRect(
        saveX, kYMSidebarDesignMetrics.footerButtonOriginY,
        kYMSidebarDesignMetrics.saveButtonWidth,
        kYMSidebarDesignMetrics.footerButtonHeight);

    if (keepTopVisible) {
        CGFloat topOrigin = MAX(0.0, documentHeight - availableHeight);
        [self.contentScrollView.contentView scrollToPoint:NSMakePoint(0,
                                                                      topOrigin)];
        [self.contentScrollView reflectScrolledClipView:
            self.contentScrollView.contentView];
    }
    self.pinScrollToTop = NO;
}

- (void)ym_layoutCard:(NSView *)card
                 label:(NSTextField *)label
            tableScroll:(NSScrollView *)tableScroll
                  table:(NSTableView *)table
                 moveUp:(NSButton *)moveUp
               moveDown:(NSButton *)moveDown
               rowCount:(NSInteger)rowCount
{
    CGFloat width = NSWidth(card.bounds);
    CGFloat tableHeight = self.rowHeight * rowCount;
    CGFloat padding = kYMSidebarDesignMetrics.cardPadding;
    CGFloat actionY = padding;
    CGFloat tableY = actionY + kYMSidebarDesignMetrics.moveButtonHeight +
        kYMSidebarDesignMetrics.tableActionGap;
    CGFloat labelY = tableY + tableHeight +
        kYMSidebarDesignMetrics.headingTableGap;
    label.frame = NSMakeRect(
        padding, labelY, MAX(0.0, width - 2.0 * padding),
        kYMSidebarDesignMetrics.groupLabelHeight);
    tableScroll.frame = NSMakeRect(
        padding, tableY, MAX(0.0, width - 2.0 * padding), tableHeight);
    // The column must be narrowed by whatever horizontal padding the effective
    // table style adds, or the table ends up WIDER than its clip view.
    //
    // These tables never set `style`, so `Automatic` resolves to
    // NSTableViewStyleInset, which pads 16pt on each side on top of the column
    // width. Setting the column to the full viewport width therefore produced a
    // 572pt document inside a 540pt clip view: 32pt of every row was clipped on
    // the right, and the 32pt of horizontal scroll range let the table slide
    // sideways. After a drop, `scrollRowToVisible:` took up that slack and the
    // clip settled at x=32, moving every row 32pt LEFT on screen while every
    // table-relative frame stayed identical. That is the reported post-reorder
    // shift; it was never the drag image.
    //
    // Derive the padding from the live geometry rather than hard-coding 32, so
    // this stays correct if the effective style or its metrics ever change.
    const CGFloat viewportWidth = NSWidth(tableScroll.contentView.bounds);
    NSTableColumn *column = table.tableColumns.firstObject;
    table.frame = NSMakeRect(0, 0, viewportWidth, tableHeight);
    column.width = viewportWidth;
    [table layoutSubtreeIfNeeded];
    const CGFloat stylePadding = NSWidth(table.frame) - viewportWidth;
    if (stylePadding > 0.0) {
        column.width = MAX(0.0, viewportWidth - stylePadding);
        table.frame = NSMakeRect(0, 0, viewportWidth, tableHeight);
    }
    moveDown.frame = NSMakeRect(
        width - padding - kYMSidebarDesignMetrics.moveButtonWidth,
        actionY, kYMSidebarDesignMetrics.moveButtonWidth,
        kYMSidebarDesignMetrics.moveButtonHeight);
    moveUp.frame = NSMakeRect(
        NSMinX(moveDown.frame) - kYMSidebarDesignMetrics.compactGap -
            kYMSidebarDesignMetrics.moveButtonWidth,
        actionY, kYMSidebarDesignMetrics.moveButtonWidth,
        kYMSidebarDesignMetrics.moveButtonHeight);
}

- (NSString *)ym_groupForTable:(NSTableView *)table
{
    if (table == self.primaryTable) {
        return @"primary";
    }
    if (table == self.secondaryTable) {
        return @"secondary";
    }
    return nil;
}

- (YMSidebarSettingsTableView *)ym_tableForGroup:(NSString *)group
{
    if ([group isEqualToString:@"primary"]) {
        return self.primaryTable;
    }
    if ([group isEqualToString:@"secondary"]) {
        return self.secondaryTable;
    }
    return nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)ym_rowsForTable:(NSTableView *)table
{
    NSString *group = [self ym_groupForTable:table];
    return group != nil ? [self.draft rowsForGroup:group] : @[];
}

- (NSDictionary<NSString *, id> *)ym_rowForIdentifier:(NSString *)identifier
{
    for (NSString *group in @[@"primary", @"secondary"]) {
        for (NSDictionary<NSString *, id> *row in
             [self.draft rowsForGroup:group]) {
            if ([row[@"identifier"] isEqualToString:identifier]) {
                return row;
            }
        }
    }
    return nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [self ym_rowsForTable:tableView].count;
}

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)rowIndex
{
    (void)tableColumn;
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self ym_rowsForTable:tableView];
    if (rowIndex < 0 || rowIndex >= (NSInteger)rows.count) {
        return nil;
    }

    NSUserInterfaceItemIdentifier reuseIdentifier = @"sidebar.entry.row";
    NSTableCellView *cell = [tableView makeViewWithIdentifier:reuseIdentifier
                                                        owner:self];
    YMSidebarSettingsEntryButton *checkbox = nil;
    YMSidebarSettingsDragHandleView *dragHandle = nil;
    if (cell == nil) {
        cell = [[YMSidebarSettingsEntryCell alloc]
            initWithFrame:NSMakeRect(0, 0, NSWidth(tableView.bounds),
                                     self.rowHeight)];
        cell.identifier = reuseIdentifier;
        checkbox = [[YMSidebarSettingsEntryButton alloc] initWithFrame:NSZeroRect];
        checkbox.identifier = @"sidebar.entry.checkbox";
        [checkbox setButtonType:NSButtonTypeSwitch];
        checkbox.font = YMFontForTypographyToken(YMSidebarTypographyRowTitle);
        checkbox.target = self;
        checkbox.action = @selector(ym_entryToggleChanged:);
        checkbox.focusRingType = NSFocusRingTypeDefault;
        checkbox.refusesFirstResponder = NO;
        checkbox.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:checkbox];
        dragHandle = [[YMSidebarSettingsDragHandleView alloc]
            initWithFrame:NSZeroRect];
        dragHandle.identifier = @"sidebar.entry.dragHandle";
        dragHandle.accessibilityElement = NO;
        dragHandle.accessibilityHidden = YES;
        dragHandle.autoresizingMask = NSViewMinXMargin;
        [cell addSubview:dragHandle];
    } else {
        checkbox = (YMSidebarSettingsEntryButton *)cell.subviews.firstObject;
        dragHandle = (YMSidebarSettingsDragHandleView *)cell.subviews.lastObject;
    }

    NSDictionary<NSString *, id> *row = rows[(NSUInteger)rowIndex];
    NSString *title = row[@"title"];
    NSString *position = [self ym_accessibilityLabelForRow:row
                                                  rowCount:rows.count];
    CGFloat checkboxVerticalInset =
        kYMSidebarDesignMetrics.rowCheckboxVerticalInset;
    checkbox.frame = NSMakeRect(
        kYMSidebarDesignMetrics.rowCheckboxLeadingInset,
        checkboxVerticalInset,
        MAX(0.0, NSWidth(tableView.bounds) -
                     kYMSidebarDesignMetrics.rowCheckboxLeadingInset -
                     kYMSidebarDesignMetrics.rowCheckboxTrailingRoom),
        self.rowHeight - 2.0 * checkboxVerticalInset);
    CGFloat dragVerticalInset = kYMSidebarDesignMetrics.dragHandleVerticalInset;
    dragHandle.frame = NSMakeRect(
        MAX(kYMSidebarDesignMetrics.rowCheckboxLeadingInset,
            NSWidth(tableView.bounds) -
                kYMSidebarDesignMetrics.dragHandleRightInset -
                kYMSidebarDesignMetrics.dragHandleWidth),
        dragVerticalInset, kYMSidebarDesignMetrics.dragHandleWidth,
        self.rowHeight - 2.0 * dragVerticalInset);
    checkbox.entryIdentifier = row[@"identifier"];
    checkbox.title = title;
    checkbox.state = [row[@"enabled"] boolValue]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    checkbox.accessibilityIdentifier = row[@"identifier"];
    checkbox.accessibilityLabel = position;
    checkbox.accessibilityHelp =
        @"按空格切换显示；拖动行或使用上移、下移调整顺序。";
    cell.accessibilityIdentifier = row[@"identifier"];
    cell.accessibilityLabel = position;
    return cell;
}

- (NSString *)ym_accessibilityLabelForRow:
        (NSDictionary<NSString *, id> *)row
                                      rowCount:(NSUInteger)rowCount
{
    NSString *groupTitle = [row[@"group"] isEqualToString:@"primary"]
        ? @"主要入口"
        : @"发现与服务";
    NSString *state = [row[@"enabled"] boolValue] ? @"已显示" : @"已隐藏";
    return [NSString stringWithFormat:@"%@，%@，第 %@ 项，共 %lu 项，%@",
                                      row[@"title"], groupTitle,
                                      row[@"position"],
                                      (unsigned long)rowCount, state];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if (self.updatingSelection) {
        return;
    }
    NSTableView *table = notification.object;
    NSArray<NSDictionary<NSString *, id> *> *rows = [self ym_rowsForTable:table];
    if (table.selectedRow < 0 || table.selectedRow >= (NSInteger)rows.count) {
        [self ym_updateMoveControls];
        return;
    }

    NSString *identifier = rows[(NSUInteger)table.selectedRow][@"identifier"];
    if (![self.draft selectIdentifier:identifier error:nil]) {
        return;
    }
    self.updatingSelection = YES;
    NSTableView *other = table == self.primaryTable
        ? self.secondaryTable
        : self.primaryTable;
    [other deselectAll:nil];
    self.updatingSelection = NO;
    [self ym_updateMoveControls];
}

- (NSString *)ym_selectedIdentifierInTable:(NSTableView *)table
{
    NSArray<NSDictionary<NSString *, id> *> *rows = [self ym_rowsForTable:table];
    if (table.selectedRow < 0 || table.selectedRow >= (NSInteger)rows.count) {
        return nil;
    }
    return rows[(NSUInteger)table.selectedRow][@"identifier"];
}

- (void)ym_reloadTablesKeepingSelection:(NSString *)identifier
                              focusTable:(NSTableView *)focusTable
{
    self.updatingSelection = YES;
    [self.primaryTable reloadData];
    [self.secondaryTable reloadData];
    [self.primaryTable deselectAll:nil];
    [self.secondaryTable deselectAll:nil];

    NSDictionary<NSString *, id> *selectedRow =
        [self ym_rowForIdentifier:identifier];
    if (selectedRow != nil) {
        YMSidebarSettingsTableView *table =
            [self ym_tableForGroup:selectedRow[@"group"]];
        NSArray<NSDictionary<NSString *, id> *> *rows =
            [self.draft rowsForGroup:selectedRow[@"group"]];
        NSUInteger index = [rows indexOfObjectPassingTest:
            ^BOOL(NSDictionary<NSString *, id> *row,
                  NSUInteger candidate,
                  BOOL *stop) {
                (void)candidate;
                if ([row[@"identifier"] isEqualToString:identifier]) {
                    *stop = YES;
                    return YES;
                }
                return NO;
            }];
        if (index != NSNotFound) {
            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
               byExtendingSelection:NO];
            [table scrollRowToVisible:(NSInteger)index];
        }
    }
    self.updatingSelection = NO;
    [self ym_updateMoveControls];
    if (focusTable != nil) {
        [self.window makeFirstResponder:focusTable];
    }
}

- (void)ym_entryToggleChanged:(YMSidebarSettingsEntryButton *)sender
{
    [self.draft selectIdentifier:sender.entryIdentifier error:nil];
    [self ym_applySelectionForIdentifier:sender.entryIdentifier];
    [self ym_toggleIdentifier:sender.entryIdentifier
                      enabled:sender.state == NSControlStateValueOn
                       sender:sender];
    NSDictionary<NSString *, id> *row =
        [self ym_rowForIdentifier:sender.entryIdentifier];
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.draft rowsForGroup:row[@"group"]];
    sender.state = [row[@"enabled"] boolValue]
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    sender.accessibilityLabel = [self ym_accessibilityLabelForRow:row
                                                        rowCount:rows.count];
    sender.superview.accessibilityLabel = sender.accessibilityLabel;
    [self.window makeFirstResponder:sender];
}

- (void)ym_applySelectionForIdentifier:(NSString *)identifier
{
    NSDictionary<NSString *, id> *selectedRow =
        [self ym_rowForIdentifier:identifier];
    if (selectedRow == nil) {
        return;
    }
    YMSidebarSettingsTableView *table =
        [self ym_tableForGroup:selectedRow[@"group"]];
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.draft rowsForGroup:selectedRow[@"group"]];
    NSUInteger index = [rows indexOfObjectPassingTest:
        ^BOOL(NSDictionary<NSString *, id> *row,
              NSUInteger candidate,
              BOOL *stop) {
            (void)candidate;
            if ([row[@"identifier"] isEqualToString:identifier]) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
    if (index == NSNotFound) {
        return;
    }
    self.updatingSelection = YES;
    [self.primaryTable deselectAll:nil];
    [self.secondaryTable deselectAll:nil];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
       byExtendingSelection:NO];
    self.updatingSelection = NO;
    [self ym_updateMoveControls];
}

- (void)ym_toggleSelectedRowInTable:(NSTableView *)table
{
    NSString *identifier = [self ym_selectedIdentifierInTable:table];
    NSDictionary<NSString *, id> *row = [self ym_rowForIdentifier:identifier];
    if (row == nil) {
        [self ym_presentInlineError:@"请先选择要修改的入口。"];
        return;
    }
    [self ym_toggleIdentifier:identifier
                      enabled:![row[@"enabled"] boolValue]
                       sender:nil];
    [self ym_reloadTablesKeepingSelection:identifier focusTable:table];
}

- (void)ym_toggleIdentifier:(NSString *)identifier
                    enabled:(BOOL)enabled
                     sender:(NSButton *)sender
{
    NSError *error = nil;
    if (![self.draft setIdentifier:identifier enabled:enabled error:&error]) {
        NSDictionary<NSString *, id> *row = [self ym_rowForIdentifier:identifier];
        sender.state = [row[@"enabled"] boolValue]
            ? NSControlStateValueOn
            : NSControlStateValueOff;
        [self ym_presentInlineError:error.localizedDescription ?:
            @"至少保留一个主要入口。"];
        NSBeep();
        return;
    }
    self.inlineMessage = nil;
    [self ym_updateStatus];
    [self ym_updateMoveControls];
}

- (void)ym_moveSelection:(NSButton *)sender
{
    NSTableView *table =
        sender == self.primaryMoveUpButton ||
                sender == self.primaryMoveDownButton
            ? self.primaryTable
            : self.secondaryTable;
    NSString *identifier = [self ym_selectedIdentifierInTable:table];
    if (identifier == nil) {
        [self ym_presentInlineError:@"请先选择要移动的入口。"];
        return;
    }
    NSInteger offset = sender == self.primaryMoveUpButton ||
                               sender == self.secondaryMoveUpButton
        ? -1
        : 1;
    NSError *error = nil;
    if (![self.draft moveIdentifier:identifier offset:offset error:&error]) {
        [self ym_presentInlineError:error.localizedDescription ?:
            @"该入口已经在边界位置。"];
        return;
    }
    self.inlineMessage = nil;
    [self ym_reloadTablesKeepingSelection:identifier focusTable:table];
    [self ym_updateStatus];
}

// TEMPORARY (2026-09-17) drag-geometry instrumentation for the reported
// post-reorder horizontal shift, which does NOT reproduce in the isolated
// AppKit harness (cellInRow.x and checkbox x are byte-identical before/after a
// simulated drop there). Logs the real window's geometry at drag start, right
// after the reload, and once AppKit has settled. Writes to
// /tmp/ym-sidebar-drag-geom.log. REMOVE once diagnosed.

// Own the drag image explicitly instead of inferring AppKit's coordinate space.
//
// The shift was never a layout error: instrumented drags show every row's
// geometry byte-identical mid-drag and from +0.03s to +1.00s after the drop. It
// is the in-flight image being placed in a space we were guessing at. AppKit
// asks the CELL for components (confirmed: the row-level override is never
// called), and a component frame is interpreted relative to the dragging item's
// own frame -- which we do not control from inside the cell, so any constant we
// pick there is a guess.
//
// Here both halves are set together, so they cannot disagree: the dragging frame
// is the ROW's rect in table coordinates, and the component is a full-row
// snapshot at that rect's own origin. Self-consistent at any table style and any
// inset.
- (void)tableView:(NSTableView *)tableView
    draggingSession:(NSDraggingSession *)session
   willBeginAtPoint:(NSPoint)screenPoint
      forRowIndexes:(NSIndexSet *)rowIndexes
{
    (void)screenPoint;
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        (void)stop;
        [rows addObject:@(index)];
    }];
    if (rows.count == 0) {
        return;
    }
    [session enumerateDraggingItemsWithOptions:0
                                       forView:tableView
                                       classes:@[ NSPasteboardItem.class ]
                                 searchOptions:@{}
                                    usingBlock:^(NSDraggingItem *item,
                                                 NSInteger index,
                                                 BOOL *stop) {
        (void)stop;
        if (index < 0 || (NSUInteger)index >= rows.count) {
            return;
        }
        const NSInteger row = rows[(NSUInteger)index].integerValue;
        NSTableRowView *rowView = [tableView rowViewAtRow:row
                                          makeIfNecessary:YES];
        if (rowView == nil) {
            return;
        }
        const NSRect rowInTable = [rowView convertRect:rowView.bounds
                                                toView:tableView];
        NSBitmapImageRep *rep =
            [rowView bitmapImageRepForCachingDisplayInRect:rowView.bounds];
        if (rep == nil) {
            return;
        }
        [rowView cacheDisplayInRect:rowView.bounds toBitmapImageRep:rep];
        NSImage *image =
            [[NSImage alloc] initWithSize:rowView.bounds.size];
        [image addRepresentation:rep];
        item.draggingFrame = rowInTable;
        item.imageComponentsProvider = ^NSArray<NSDraggingImageComponent *> *{
            NSDraggingImageComponent *component = [NSDraggingImageComponent
                draggingImageComponentWithKey:NSDraggingImageComponentIconKey];
            component.contents = image;
            component.frame =
                NSMakeRect(0, 0, NSWidth(rowInTable), NSHeight(rowInTable));
            return @[ component ];
        };
    }];
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
            pasteboardWriterForRow:(NSInteger)rowIndex
{
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self ym_rowsForTable:tableView];
    if (rowIndex < 0 || rowIndex >= (NSInteger)rows.count) {
        return nil;
    }
    NSDictionary<NSString *, id> *row = rows[(NSUInteger)rowIndex];
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setPropertyList:@{
        @"version" : @1,
        @"group" : row[@"group"],
        @"identifier" : row[@"identifier"],
    } forType:kYMSidebarSettingsPasteboardType];
    return item;
}

- (NSDictionary<NSString *, NSString *> *)ym_parseDropPayload:(id)value
{
    if (![value isKindOfClass:NSDictionary.class] ||
        [(NSDictionary *)value count] != 3) {
        return nil;
    }
    NSDictionary *payload = value;
    if (![payload[@"version"] isEqual:@1] ||
        ![payload[@"group"] isKindOfClass:NSString.class] ||
        ![payload[@"identifier"] isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *group = payload[@"group"];
    NSString *identifier = payload[@"identifier"];
    NSDictionary<NSString *, id> *row = [self ym_rowForIdentifier:identifier];
    if (row == nil || ![row[@"group"] isEqualToString:group]) {
        return nil;
    }
    return @{
        @"group" : group,
        @"identifier" : identifier,
    };
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                  validateDrop:(id<NSDraggingInfo>)info
                   proposedRow:(NSInteger)row
         proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
    (void)dropOperation;
    id rawPayload = [info.draggingPasteboard
        propertyListForType:kYMSidebarSettingsPasteboardType];
    NSDictionary<NSString *, NSString *> *payload =
        [self ym_parseDropPayload:rawPayload];
    NSString *destinationGroup = [self ym_groupForTable:tableView];
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self ym_rowsForTable:tableView];
    if (payload == nil ||
        ![payload[@"group"] isEqualToString:destinationGroup] ||
        row < 0 || row > (NSInteger)rows.count) {
        return NSDragOperationNone;
    }
    NSUInteger sourceIndex = [rows indexOfObjectPassingTest:
        ^BOOL(NSDictionary<NSString *, id> *candidate,
              NSUInteger index,
              BOOL *stop) {
            (void)index;
            if ([candidate[@"identifier"]
                    isEqualToString:payload[@"identifier"]]) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
    NSUInteger targetIndex = (NSUInteger)row;
    if (targetIndex > sourceIndex) {
        --targetIndex;
    }
    if (targetIndex >= rows.count) {
        targetIndex = rows.count - 1;
    }
    if (sourceIndex == NSNotFound || targetIndex == sourceIndex) {
        return NSDragOperationNone;
    }
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
        acceptDrop:(id<NSDraggingInfo>)info
               row:(NSInteger)row
     dropOperation:(NSTableViewDropOperation)dropOperation
{
    (void)dropOperation;
    id payload = [info.draggingPasteboard
        propertyListForType:kYMSidebarSettingsPasteboardType];
    return [self ym_applyDropPayload:payload
                            toGroup:[self ym_groupForTable:tableView]
                                row:row];
}

- (BOOL)ym_applyDropPayload:(id)value
                    toGroup:(NSString *)destinationGroup
                        row:(NSInteger)proposedRow
{
    NSDictionary<NSString *, NSString *> *payload =
        [self ym_parseDropPayload:value];
    NSArray<NSDictionary<NSString *, id> *> *rows =
        [self.draft rowsForGroup:destinationGroup];
    if (payload == nil ||
        ![payload[@"group"] isEqualToString:destinationGroup] ||
        proposedRow < 0 || proposedRow > (NSInteger)rows.count) {
        [self ym_presentInlineError:@"拖放内容无效，排序未更改。"];
        return NO;
    }

    NSString *identifier = payload[@"identifier"];
    NSUInteger sourceIndex = [rows indexOfObjectPassingTest:
        ^BOOL(NSDictionary<NSString *, id> *row,
              NSUInteger candidate,
              BOOL *stop) {
            (void)candidate;
            if ([row[@"identifier"] isEqualToString:identifier]) {
                *stop = YES;
                return YES;
            }
            return NO;
        }];
    if (sourceIndex == NSNotFound) {
        [self ym_presentInlineError:@"拖放内容无效，排序未更改。"];
        return NO;
    }

    NSUInteger targetIndex = (NSUInteger)proposedRow;
    if (targetIndex > sourceIndex) {
        --targetIndex;
    }
    if (targetIndex >= rows.count) {
        targetIndex = rows.count - 1;
    }
    if (targetIndex == sourceIndex) {
        return NO;
    }

    NSError *error = nil;
    if (![self.draft moveIdentifier:identifier
                            toIndex:targetIndex
                            inGroup:destinationGroup
                              error:&error]) {
        [self ym_presentInlineError:error.localizedDescription ?:
            @"拖放内容无效，排序未更改。"];
        return NO;
    }
    self.inlineMessage = nil;
    [self.draft selectIdentifier:identifier error:nil];
    [self ym_reloadTablesKeepingSelection:identifier
                               focusTable:[self ym_tableForGroup:destinationGroup]];
    [self ym_updateStatus];
    return YES;
}

- (void)ym_reloadDraftFromManager
{
    NSError *error = nil;
    self.draft = [[YMSidebarSettingsDraft alloc]
        initWithConfiguration:SidebarManager.sharedManager.currentConfiguration
                         error:&error];
    self.inlineMessage = self.draft == nil
        ? (error.localizedDescription ?: @"无法读取侧边栏设置。")
        : nil;
    self.pinScrollToTop = YES;
    [self ym_layoutInterface];
    NSString *selection = self.draft.selectedIdentifier;
    [self ym_reloadTablesKeepingSelection:selection focusTable:nil];
    [self ym_applyAdaptiveAppearance];
    [self ym_updateStatus];
}

- (void)ym_updateMoveControls
{
    [self ym_updateMoveButtonsForTable:self.primaryTable
                                    up:self.primaryMoveUpButton
                                  down:self.primaryMoveDownButton
                            groupTitle:@"主要入口"];
    [self ym_updateMoveButtonsForTable:self.secondaryTable
                                    up:self.secondaryMoveUpButton
                                  down:self.secondaryMoveDownButton
                            groupTitle:@"发现与服务"];
}

- (void)ym_updateMoveButtonsForTable:(NSTableView *)table
                                   up:(NSButton *)up
                                 down:(NSButton *)down
                           groupTitle:(NSString *)groupTitle
{
    NSString *identifier = [self ym_selectedIdentifierInTable:table];
    NSDictionary<NSString *, id> *row = [self ym_rowForIdentifier:identifier];
    up.enabled = [row[@"canMoveUp"] boolValue];
    down.enabled = [row[@"canMoveDown"] boolValue];
    NSString *title = row[@"title"];
    up.accessibilityHelp = title != nil
        ? [NSString stringWithFormat:@"将“%@”在%@中上移一位。", title, groupTitle]
        : [NSString stringWithFormat:@"先在%@中选择一个入口。", groupTitle];
    down.accessibilityHelp = title != nil
        ? [NSString stringWithFormat:@"将“%@”在%@中下移一位。", title, groupTitle]
        : [NSString stringWithFormat:@"先在%@中选择一个入口。", groupTitle];
}

- (void)ym_presentInlineError:(NSString *)message
{
    self.inlineMessage = message;
    [self ym_updateStatus];
    self.statusLabel.accessibilityLabel = message;
}

- (void)ym_updateStatus
{
    SidebarManager *manager = SidebarManager.sharedManager;
    BOOL light = [self ym_shouldUseLightAppearance];
    self.saveButton.enabled = self.draft != nil && self.draft.isDirty;
    if (self.inlineMessage.length > 0) {
        self.statusLabel.stringValue = self.inlineMessage;
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusError, light);
    } else if (self.draft.isOrderDirty) {
        self.statusLabel.stringValue = @"有未保存的排序修改；保存后重启微信生效";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusWarning, light);
    } else if (self.draft.isDirty) {
        self.statusLabel.stringValue = @"有未保存的修改";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusWarning, light);
    } else if (manager.isPendingRestart) {
        self.statusLabel.stringValue = @"已保存；顺序将在重启微信后生效";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusWarning, light);
    } else if (manager.isReady) {
        self.statusLabel.stringValue = @"已连接微信";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusReady, light);
    } else if (manager.isSupported) {
        self.statusLabel.stringValue = @"等待微信侧边栏初始化";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorYMTextSubtitle, light);
    } else {
        self.statusLabel.stringValue = @"当前版本未匹配；设置仍可保存";
        self.statusLabel.textColor = YMColorForDesignToken(
            YMSidebarColorStatusWarning, light);
    }
    self.statusLabel.accessibilityLabel = self.statusLabel.stringValue;
}

- (void)ym_save:(NSButton *)sender
{
    (void)sender;
    if (self.draft == nil || !self.draft.isDirty) {
        return;
    }
    NSError *error = nil;
    if (![SidebarManager.sharedManager saveConfiguration:self.draft.configuration
                                                    error:&error]) {
        [self ym_presentInlineError:error.localizedDescription ?:
            @"侧边栏设置未保存，请重试。"];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"无法保存侧边栏设置";
        alert.informativeText = self.statusLabel.stringValue;
        [alert addButtonWithTitle:@"好"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    [self ym_reloadDraftFromManager];
    [self.window close];
}

- (void)ym_cancel:(NSButton *)sender
{
    (void)sender;
    [self.draft cancel];
    [self.window close];
}

- (void)ym_sidebarStateDidChange:(NSNotification *)notification
{
    (void)notification;
    if (!self.window.isVisible || self.draft.isDirty) {
        [self ym_updateStatus];
        return;
    }
    [self ym_reloadDraftFromManager];
}

- (void)windowDidResize:(NSNotification *)notification
{
    (void)notification;
    [self ym_layoutInterface];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    (void)notification;
    [self ym_applyAdaptiveAppearance];
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    [self.draft cancel];
    self.draft = nil;
    self.inlineMessage = nil;
}

- (BOOL)ym_shouldUseLightAppearance
{
    NSAppearance *appearance = self.window.effectiveAppearance ?:
        NSAppearance.currentAppearance;
    NSString *bestMatch = [appearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua,
    ]];
    return ![bestMatch isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSColor *)ym_labelColorForRole:(NSInteger)role light:(BOOL)light
{
    switch (role) {
        case kYMSidebarSettingsLabelRoleTitle:
            return YMColorForDesignToken(YMSidebarColorYMTextTitle, light);
        case kYMSidebarSettingsLabelRolePrimary:
            return YMColorForDesignToken(YMSidebarColorYMTextPrimary, light);
        case kYMSidebarSettingsLabelRoleSubtitle:
            return YMColorForDesignToken(YMSidebarColorYMTextSubtitle, light);
        default:
            return YMColorForDesignToken(YMSidebarColorYMTextSecondary, light);
    }
}

- (void)ym_applyLabelColorsInView:(NSView *)view light:(BOOL)light
{
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:NSTextField.class]) {
            NSTextField *label = (NSTextField *)subview;
            if (label.tag >= kYMSidebarSettingsLabelRoleTitle &&
                label.tag <= kYMSidebarSettingsLabelRoleSecondary) {
                label.textColor = [self ym_labelColorForRole:label.tag
                                                       light:light];
            }
        }
        [self ym_applyLabelColorsInView:subview light:light];
    }
}

- (void)ym_applyAdaptiveAppearance
{
    BOOL light = [self ym_shouldUseLightAppearance];
    self.window.backgroundColor = YMColorForDesignToken(
        YMSidebarColorYMWindowSurface, light);
    self.rootContentView.layer.backgroundColor = YMColorForDesignToken(
        YMSidebarColorYMContentSurface, light).CGColor;
    for (NSView *card in @[self.primaryCard, self.secondaryCard]) {
        card.layer.backgroundColor = YMColorForDesignToken(
            YMSidebarColorYMCardSurface, light).CGColor;
        card.layer.borderColor = YMColorForDesignToken(
            YMSidebarColorYMCardBorder, light).CGColor;
    }
    [self ym_applyLabelColorsInView:self.rootContentView light:light];
    [self ym_updateStatus];
}

@end
