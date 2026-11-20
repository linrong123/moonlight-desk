#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <SDL_syswm.h>
#include <map>
#include <set>
#include <string>
#include "toolbar.h"

// All AppKit work and callbacks run on the session's main thread. The sheet owns
// its completion target until dismissal; invalidation clears the session callback
// before ending the sheet, so delayed completions cannot reach a dead session.

// Native windows that currently carry an office toolbar. The SDL listener
// wrappers below only change behavior for these windows.
static std::set<void*>& officeToolbarWindows() {
    static std::set<void*> windows;
    return windows;
}

// SDL asks for a hidden menu bar in its FULLSCREEN_DESKTOP Space, which also pins
// the window toolbar on screen. Keep SDL's choice but let the menu bar and the
// toolbar auto-hide together (revealed at the top edge), as in other remote
// desktop apps. AppKit rejects AutoHideToolbar without FullScreen and
// AutoHideMenuBar, and AutoHideMenuBar without HideDock or AutoHideDock.
static NSApplicationPresentationOptions officeFullscreenOptions(NSApplicationPresentationOptions options) {
    if (!(options & NSApplicationPresentationFullScreen)) return options;
    if (options & NSApplicationPresentationHideMenuBar) {
        options = (options & ~NSApplicationPresentationHideMenuBar) | NSApplicationPresentationAutoHideMenuBar;
    }
    if (options & NSApplicationPresentationAutoHideMenuBar) {
        if (!(options & (NSApplicationPresentationHideDock | NSApplicationPresentationAutoHideDock))) {
            options |= NSApplicationPresentationAutoHideDock;
        }
        options |= NSApplicationPresentationAutoHideToolbar;
    }
    return options;
}

// SDL's window delegate (the class SDL installs, currently SDL3Cocoa_WindowListener
// through sdl2-compat) forces the menu bar hidden in a fullscreen Space
// (willUseFullScreenPresentationOptions and setMenuBarVisible:NO). The SDL source
// stays unmodified: the delegate's actual class is wrapped once at runtime, the
// wrappers call the original first and only adjust windows registered above.
// The class name is not hardcoded because it changes with the SDL build; every
// call logs which class and methods carry the wrapper. Recheck after SDL upgrades.
static std::string officeWrapFullscreenListener(NSWindow* window) {
    static std::map<Class, std::string> wrappedClasses;
    id delegate = window.delegate;
    Class listener = delegate ? object_getClass(delegate) : Nil;
    std::string result;
    if (!listener) {
        result = "fullscreen auto-hide not installed: window has no delegate";
    } else if (wrappedClasses.count(listener)) {
        result = wrappedClasses[listener];
    } else {
        std::string methods;
        const SEL optionsSelector = @selector(window:willUseFullScreenPresentationOptions:);
        if (Method method = class_getInstanceMethod(listener, optionsSelector)) {
            using Options = NSApplicationPresentationOptions (*)(id, SEL, NSWindow*, NSApplicationPresentationOptions);
            const Options original = reinterpret_cast<Options>(method_getImplementation(method));
            IMP wrapper = imp_implementationWithBlock(^NSApplicationPresentationOptions(id object, NSWindow* target,
                    NSApplicationPresentationOptions proposed) {
                const NSApplicationPresentationOptions options = original(object, optionsSelector, target, proposed);
                return officeToolbarWindows().count(target) ? officeFullscreenOptions(options) : options;
            });
            class_replaceMethod(listener, optionsSelector, wrapper, method_getTypeEncoding(method));
            methods += " window:willUseFullScreenPresentationOptions:";
        }
        for (SEL selector : {@selector(windowDidEnterFullScreen:), @selector(windowDidBecomeKey:)}) {
            Method method = class_getInstanceMethod(listener, selector);
            if (!method) continue;
            using Notify = void (*)(id, SEL, NSNotification*);
            const Notify original = reinterpret_cast<Notify>(method_getImplementation(method));
            IMP wrapper = imp_implementationWithBlock(^(id object, NSNotification* notification) {
                original(object, selector, notification);
                id target = notification.object;
                // YES restores the automatic menu bar of the fullscreen Space; SDL
                // itself does the same when the window resigns key in fullscreen.
                if ([target isKindOfClass:NSWindow.class] && officeToolbarWindows().count(target) &&
                    ([(NSWindow*)target styleMask] & NSWindowStyleMaskFullScreen)) {
                    [NSMenu setMenuBarVisible:YES];
                }
            });
            class_replaceMethod(listener, selector, wrapper, method_getTypeEncoding(method));
            methods += " ";
            methods += sel_getName(selector);
        }
        const std::string name = class_getName(listener);
        result = methods.empty()
            ? "fullscreen auto-hide not installed: " + name + " implements none of the wrapped methods"
            : "fullscreen auto-hide wrapped " + name + ":" + methods;
        wrappedClasses[listener] = result;
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Office toolbar: %s", result.c_str());
    return result;
}

// The stream window must keep keyboard focus: Session only forwards input while
// SDL reports the stream window as keyboard focus.
@interface OfficeStatisticsPanel : NSPanel
@end
@implementation OfficeStatisticsPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

// Shortcuts handled by the upstream input handler (Ctrl+Alt+Shift combos).
static NSString* const officeFullscreenShortcut = @"⌃⌥⇧X";
static NSString* const officeReleaseShortcut = @"⌃⌥⇧Z";

// Menu titles: a plain first line, an optional smaller grey note (second line
// or trailing hint) and an optional color, as an attributed title.
static NSAttributedString* officeMenuTitle(NSString* title, NSString* note, BOOL noteOnNewLine, NSColor* color) {
    // Only colored items (disconnect) set a foreground color on the first line.
    NSDictionary* attributes = color ? @{NSFontAttributeName: [NSFont menuFontOfSize:0], NSForegroundColorAttributeName: color}
        : @{NSFontAttributeName: [NSFont menuFontOfSize:0]};
    NSMutableAttributedString* text = [[[NSMutableAttributedString alloc] initWithString:title attributes:attributes] autorelease];
    if (note.length) {
        NSString* joined = [(noteOnNewLine ? @"\n" : @"    ") stringByAppendingString:note];
        [text appendAttributedString:[[[NSAttributedString alloc] initWithString:joined attributes:@{
            NSFontAttributeName: [NSFont menuFontOfSize:NSFont.smallSystemFontSize],
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor}] autorelease]];
    }
    return text;
}

// First available SF Symbol of the names (newer names first); nil before macOS 11.
static NSImage* officeSymbol(NSArray<NSString*>* names, NSString* description) {
    if (@available(macOS 11.0, *)) {
        for (NSString* name in names) {
            NSImage* image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
            if (image) return image;
        }
    }
    return nil;
}

// Truncates text with an ellipsis so that it fits the width with the attributes.
static NSString* officeFitted(NSString* text, NSDictionary* attributes, CGFloat width) {
    if ([text sizeWithAttributes:attributes].width <= width) return text;
    NSString* kept = text;
    while (kept.length) {
        kept = [kept substringToIndex:[kept rangeOfComposedCharacterSequenceAtIndex:kept.length - 1].location];
        NSString* shown = [kept stringByAppendingString:@"…"];
        if ([shown sizeWithAttributes:attributes].width <= width) return shown;
    }
    return @"…";
}

// Toolbar layout: the connection info capsule on the left, the icon group
// (display, mouse and keyboard, fullscreen, devices) in the center and the red
// disconnect button on the far right, flexible spaces in between.
static NSString* const officeInfoId = @"office.info";
static NSString* const officeStatusId = @"office.status";
static NSString* const officeDisplayId = @"office.display";
static NSString* const officeInputId = @"office.input";
static NSString* const officeFullscreenId = @"office.fullscreen";
static NSString* const officeDevicesId = @"office.devices";
static NSString* const officeDisconnectId = @"office.disconnect";
// Room for the longest usual summary, so per-second updates never relayout.
static NSString* const officeSummarySample = @"延迟 999 ms · 120 帧/秒 · 99.9 Mbps";
static const CGFloat officeDeviceNameWidth = 200;

@interface OfficeToolbarTarget : NSObject <NSToolbarDelegate, NSMenuItemValidation, NSMenuDelegate, NSWindowDelegate> {
@public
    std::function<void(office::Action, int, int)> action;
    NSWindow* streamWindow;
    SDL_Window* sdlWindow;
    // Left: one clickable info capsule (status dot, device name, summary, ⓘ)
    // that toggles the connection info panel.
    NSButton* infoButton;
    NSLayoutConstraint* infoWidth;
    NSString* deviceName;
    NSString* summaryLine;
    NSTextField* status;
    NSButton* disconnectButton;
    // Center: the menus of the 显示 and 鼠标与键盘 icons, and the fullscreen icon.
    NSMenu* displayMenu;
    NSMenu* inputMenu;
    NSMutableArray* builtMenus;  // every menu built here, overflow copies included
    NSToolbarItem* fullscreenItem;
    NSString* details;
    OfficeStatisticsPanel* panel;
    NSTextField* panelText;
    NSAlert* confirmation;
    // Choices; menu check marks are derived from these on every validation, so
    // exactly the current choice of each group is checked.
    NSArray* resolutions;      // @[@[w, h], ...]
    NSArray* resolutionTitles;
    NSInteger currentResolution;
    NSInteger mouseMode;
    NSArray* scales;           // supported Windows scale percentages
    int currentScale;
    BOOL scalePending;
    BOOL inputPaused;
    BOOL invalidated;
    BOOL hasDevices;
    BOOL fullscreenShown;
    BOOL panelWanted;
}
- (void)resolutionChanged:(id)sender;
- (void)scaleChanged:(id)sender;
- (void)mouseChanged:(id)sender;
- (void)inputPause:(id)sender;
- (void)fullscreen:(id)sender;
- (void)statistics:(id)sender;
- (void)disconnect:(id)sender;
- (void)devices:(id)sender;
- (NSMenu*)buildDisplayMenu;
- (NSMenu*)buildInputMenu;
- (void)invalidate;
- (BOOL)streamFullscreen;
- (NSString*)fullscreenTitle;
- (void)poll;
- (void)setPanelVisible:(BOOL)visible;
- (void)setSummary:(NSString*)line details:(NSString*)full;
- (void)setDeviceName:(NSString*)name;
@end

@implementation OfficeToolbarTarget
- (void)send:(office::Action)kind first:(int)first second:(int)second {
    // The callback can destroy MacToolbar (and clear action) synchronously; keep
    // this target and its menus alive until the current event finishes.
    [[self retain] autorelease];
    auto callback = action;
    if (!invalidated && callback) callback(kind, first, second);
}
- (void)mouseChanged:(id)sender {
    if (invalidated || ![sender isKindOfClass:[NSMenuItem class]]) return;
    const NSInteger mode = [sender tag];
    if (mode < 0 || mode > 2) return;
    mouseMode = mode;
    [self send:office::Action::Mouse first:(int)mode second:0];
}
- (void)scaleChanged:(id)sender {
    if (invalidated || scalePending || ![sender isKindOfClass:[NSMenuItem class]]) return;
    NSNumber* value = [sender representedObject];
    if (![value isKindOfClass:[NSNumber class]]) return;
    [self send:office::Action::DisplayScale first:value.intValue second:0];
}
- (void)inputPause:(id)sender {
    (void)sender;
    if (invalidated || confirmation) return;
    inputPaused = !inputPaused;
    [self send:office::Action::InputPause first:inputPaused ? 1 : 0 second:0];
}
- (void)resolutionChanged:(id)sender {
    if (invalidated || confirmation || ![sender isKindOfClass:[NSMenuItem class]]) return;
    const NSInteger proposed = [sender tag];
    if (proposed < 0 || proposed >= (NSInteger)resolutions.count || proposed == currentResolution) return;
    NSArray* size = resolutions[proposed];
    const int width = [size[0] intValue], height = [size[1] intValue];
    // Input is paused while the sheet is open, unless the user already paused it.
    const BOOL pauseForSheet = !inputPaused;
    [self retain];
    if (pauseForSheet) [self send:office::Action::InputPause first:1 second:0];
    if (invalidated) { [self release]; return; }
    confirmation = [[NSAlert alloc] init];
    confirmation.messageText = [NSString stringWithFormat:@"切换到 %d×%d？", width, height];
    confirmation.informativeText = @"将短暂重连，Windows不会注销";
    [confirmation addButtonWithTitle:@"切换"];
    [confirmation addButtonWithTitle:@"取消"];
    confirmation.buttons[0].keyEquivalent = @"";
    confirmation.buttons[1].keyEquivalent = @"\033";
    [confirmation beginSheetModalForWindow:streamWindow completionHandler:^(NSModalResponse response) {
        [confirmation release];
        confirmation = nil;
        if (invalidated) return;
        if (pauseForSheet) [self send:office::Action::InputPause first:0 second:0];
        if (!invalidated && response == NSAlertFirstButtonReturn) {
            [self send:office::Action::Resolution first:width second:height];
        }
    }];
    [self release];
}
// Spaces fullscreen shows the native FullScreen style; SDL's exclusive
// (non-Spaces) fullscreen is a borderless window with SDL's fullscreen flag.
- (BOOL)streamFullscreen {
    const NSWindowStyleMask style = streamWindow.styleMask;
    if (style & NSWindowStyleMaskFullScreen) return YES;
    return sdlWindow && (SDL_GetWindowFlags(sdlWindow) & SDL_WINDOW_FULLSCREEN) && !(style & NSWindowStyleMaskTitled);
}
- (NSString*)fullscreenTitle { return fullscreenShown ? @"退出全屏" : @"进入全屏"; }
// The fullscreen icon, tooltip and overflow title follow the window state.
- (void)decorateFullscreenItem {
    if (!fullscreenItem) return;
    NSString* title = [self fullscreenTitle];
    NSImage* image = officeSymbol(fullscreenShown ? @[@"arrow.down.right.and.arrow.up.left"]
        : @[@"arrow.up.left.and.arrow.down.right"], title);
    if (image) fullscreenItem.image = image;
    else if (@available(macOS 10.15, *)) fullscreenItem.title = title;
    fullscreenItem.toolTip = [NSString stringWithFormat:@"%@（%@）", title, officeFullscreenShortcut];
    fullscreenItem.menuFormRepresentation.attributedTitle = officeMenuTitle(title, officeFullscreenShortcut, NO, nil);
}
- (void)refreshFullscreen {
    const BOOL shown = [self streamFullscreen];
    if (shown == fullscreenShown) return;
    fullscreenShown = shown;
    [self decorateFullscreenItem];
}
- (void)windowFullscreenChanged:(NSNotification*)notification { (void)notification; [self poll]; }
- (void)fullscreen:(id)sender {
    (void)sender;
    if (invalidated) return;
    const NSWindowStyleMask style = streamWindow.styleMask;
    const BOOL native = (style & NSWindowStyleMaskFullScreen) != 0;
    const BOOL flagged = sdlWindow && (SDL_GetWindowFlags(sdlWindow) & SDL_WINDOW_FULLSCREEN);
    if ((style & NSWindowStyleMaskTitled) && native != flagged) {
        // The Space was entered or left with the green button or Control-Command-F,
        // which SDL does not reflect in its window flags; SDL_SetWindowFullscreen
        // would then do nothing. Toggle the Space natively so the item always
        // does what its title says.
        [streamWindow toggleFullScreen:nil];
        return;
    }
    [self send:office::Action::Fullscreen first:0 second:0];
}
- (void)statistics:(id)sender {
    (void)sender;
    if (invalidated) return;
    [self setPanelVisible:!panelWanted];
    [self send:office::Action::Statistics first:panelWanted ? 1 : 0 second:0];
}
- (void)disconnect:(id)sender {
    (void)sender;
    // Do not resume input when disconnecting while a confirmation is pending.
    [[self retain] autorelease];
    auto callback = action;
    [self invalidate];
    if (callback) callback(office::Action::Disconnect, 0, 0);
}
- (void)devices:(id)sender { (void)sender; [self send:office::Action::Devices first:0 second:0]; }
- (NSMenuItem*)itemTitled:(NSString*)title action:(SEL)selector tag:(NSInteger)tag {
    NSMenuItem* item = [[[NSMenuItem alloc] initWithTitle:title action:selector keyEquivalent:@""] autorelease];
    item.target = self;
    item.tag = tag;
    return item;
}
- (NSMenuItem*)submenuTitled:(NSString*)title items:(NSMenu*)submenu {
    NSMenuItem* item = [[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""] autorelease];
    submenu.title = title;
    item.submenu = submenu;
    return item;
}
- (NSMenu*)newMenu {
    NSMenu* menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [builtMenus addObject:menu];
    return menu;
}
// Rebuilt whenever the scale submenu opens: the host reports its choices late.
- (void)fillScaleMenu:(NSMenu*)menu {
    [menu removeAllItems];
    if (!scales.count) {
        NSMenuItem* item = [self itemTitled:scalePending ? @"读取中…" : @"不可用" action:nil tag:0];
        item.enabled = NO;
        [menu addItem:item];
        return;
    }
    for (NSNumber* value in scales) {
        NSMenuItem* item = [self itemTitled:[NSString stringWithFormat:@"%d%%", value.intValue]
            action:@selector(scaleChanged:) tag:0];
        item.representedObject = value;
        item.toolTip = scalePending ? @"Windows缩放正在设置，请稍候" : @"修改Windows系统文字和图标大小（DPI），显示可能短暂闪烁";
        [menu addItem:item];
    }
}
- (void)menuNeedsUpdate:(NSMenu*)menu {
    if ([menu.title isEqualToString:@"画面缩放"]) [self fillScaleMenu:menu];
}
// 显示: 分辨率 › and 画面缩放 ›.
- (NSMenu*)buildDisplayMenu {
    NSMenu* display = [self newMenu];
    display.title = @"显示";
    NSMenu* resolutionMenu = [self newMenu];
    for (NSUInteger i = 0; i < resolutions.count; ++i) {
        NSMenuItem* item = [self itemTitled:resolutionTitles[i] action:@selector(resolutionChanged:) tag:(NSInteger)i];
        item.toolTip = @"修改远端桌面分辨率；确认后会短暂重连，Windows不会注销";
        [resolutionMenu addItem:item];
    }
    [display addItem:[self submenuTitled:@"分辨率" items:resolutionMenu]];
    NSMenu* scaleMenu = [self newMenu];
    [display addItem:[self submenuTitled:@"画面缩放" items:scaleMenu]];
    scaleMenu.delegate = self;
    [self fillScaleMenu:scaleMenu];
    return display;
}
// 鼠标与键盘: three single-choice mouse modes with a note, then 暂停输入.
- (NSMenu*)buildInputMenu {
    NSMenu* input = [self newMenu];
    input.title = @"鼠标与键盘";
    NSString* const modes[][2] = {
        {@"本机鼠标（推荐办公）", @"显示本机光标，响应最快，适合日常办公"},
        {@"远端鼠标", @"显示被控端的光标样式"},
        {@"游戏模式（锁定鼠标）", [NSString stringWithFormat:@"鼠标锁定在画面内，适合游戏或 3D 软件；按 %@ 释放", officeReleaseShortcut]},
    };
    for (NSInteger i = 0; i < 3; ++i) {
        NSMenuItem* item = [self itemTitled:modes[i][0] action:@selector(mouseChanged:) tag:i];
        item.attributedTitle = officeMenuTitle(modes[i][0], modes[i][1], YES, nil);
        item.toolTip = modes[i][1];
        [input addItem:item];
    }
    [input addItem:[NSMenuItem separatorItem]];
    NSMenuItem* pause = [self itemTitled:@"暂停输入" action:@selector(inputPause:) tag:0];
    pause.toolTip = @"暂停期间键盘鼠标不发送到远端";
    [input addItem:pause];
    return input;
}
// The capsule title: status dot, bold device name, gap, grey summary.
- (NSAttributedString*)infoTitleWithSummary:(NSString*)line {
    NSFont* small = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    NSMutableAttributedString* text = [[[NSMutableAttributedString alloc] initWithString:@"●" attributes:@{
        NSFontAttributeName: small,
        NSForegroundColorAttributeName: details.length ? NSColor.systemGreenColor : NSColor.tertiaryLabelColor}] autorelease];
    NSDictionary* nameAttributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:NSFont.systemFontSize],
        NSForegroundColorAttributeName: NSColor.labelColor};
    NSString* name = officeFitted(deviceName ?: @"", nameAttributes, officeDeviceNameWidth);
    [text appendAttributedString:[[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:name]
        attributes:nameAttributes] autorelease]];
    [text appendAttributedString:[[[NSAttributedString alloc] initWithString:[@"    " stringByAppendingString:line ?: @""]
        attributes:@{NSFontAttributeName: small, NSForegroundColorAttributeName: NSColor.secondaryLabelColor}] autorelease]];
    return text;
}
- (void)updateInfo {
    if (!infoButton) return;
    infoButton.attributedTitle = [self infoTitleWithSummary:summaryLine];
}
// Width depends on the device name only: the summary has a fixed slot.
- (void)updateInfoWidth {
    if (!infoButton) return;
    const CGFloat text = ceil([self infoTitleWithSummary:officeSummarySample].size.width);
    const CGFloat image = infoButton.image ? infoButton.image.size.width + 6 : 0;
    const CGFloat width = text + image + 28;
    if (!infoWidth) {
        infoWidth = [[infoButton.widthAnchor constraintEqualToConstant:width] retain];
        infoWidth.active = YES;
    } else if (infoWidth.constant != width) {
        infoWidth.constant = width;
    }
}
- (void)setDeviceName:(NSString*)name {
    NSString* shown = name.length ? name : @"远程电脑";
    if ([deviceName isEqualToString:shown]) return;
    [deviceName release];
    deviceName = [shown copy];
    [self updateInfoWidth];
    [self updateInfo];
}
- (void)invalidate {
    invalidated = YES;
    action = {};
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    panel.delegate = nil;
    [panel orderOut:nil];
    for (NSMenu* menu in builtMenus) [menu cancelTrackingWithoutAnimation];
    if (confirmation) {
        [streamWindow endSheet:confirmation.window returnCode:NSModalResponseCancel];
        [confirmation.window orderOut:nil];
    }
}
- (void)ensurePanel {
    if (panel) return;
    panel = [[OfficeStatisticsPanel alloc] initWithContentRect:NSMakeRect(0, 0, 260, 120)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow |
            NSWindowStyleMaskHUDWindow | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered defer:YES];
    panel.title = @"连接信息";
    panel.releasedWhenClosed = NO;
    panel.floatingPanel = YES;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.hidesOnDeactivate = YES;
    panel.movableByWindowBackground = YES;
    // Visible over the session's fullscreen Space as well as on the desktop.
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    panel.delegate = self;
    panelText = [[NSTextField labelWithString:@""] retain];
    panelText.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    panelText.textColor = NSColor.labelColor;
    panelText.usesSingleLineMode = NO;
    panelText.maximumNumberOfLines = 0;
    panelText.selectable = NO;
    [panel.contentView addSubview:panelText];
}
- (void)updatePanel {
    if (!panel) return;
    panelText.stringValue = details.length ? details : @"等待视频统计…";
    [panelText sizeToFit];
    const CGFloat margin = 12;
    const NSSize text = panelText.frame.size;
    panelText.frameOrigin = NSMakePoint(margin, margin);
    const NSRect frame = panel.frame;
    // Never shrink the width while numbers change, to avoid jitter.
    const CGFloat width = MAX(MAX((CGFloat)260, ceil(text.width) + 2 * margin), [panel contentRectForFrameRect:frame].size.width);
    NSRect wanted = [panel frameRectForContentRect:NSMakeRect(0, 0, width, ceil(text.height) + 2 * margin)];
    if (NSEqualSizes(frame.size, wanted.size)) return;
    // Keep the top-left corner where the user left it.
    wanted.origin = NSMakePoint(frame.origin.x, NSMaxY(frame) - wanted.size.height);
    [panel setFrame:wanted display:panel.visible];
}
- (void)placePanel {
    // Top right of the video area of the stream window.
    const NSRect area = [streamWindow convertRectToScreen:streamWindow.contentLayoutRect];
    const NSSize size = panel.frame.size;
    [panel setFrameOrigin:NSMakePoint(NSMaxX(area) - size.width - 16, NSMaxY(area) - size.height - 16)];
}
- (void)syncPanel {
    if (!panel || invalidated) return;
    if (!panelWanted || !streamWindow.visible) {
        if (panel.visible) [panel orderOut:nil];
        return;
    }
    // A non-activating panel never becomes key; orderFront: does not take focus.
    if (!panel.visible && NSApp.active) [panel orderFront:nil];
}
- (void)setPanelVisible:(BOOL)visible {
    panelWanted = visible;
    if (visible) {
        [self ensurePanel];
        [self updatePanel];
        if (!panel.visible) [self placePanel];
    }
    [self syncPanel];
}
- (void)setSummary:(NSString*)line details:(NSString*)full {
    NSString* shown = line.length ? line : @"统计读取中";
    const BOOL hadDetails = details.length != 0;
    const BOOL lineChanged = ![summaryLine isEqualToString:shown];
    if (lineChanged) {
        [summaryLine release];
        summaryLine = [shown copy];
    }
    if (![details isEqualToString:full]) {
        [details release];
        details = [full copy];
        infoButton.toolTip = full.length ? full : @"连接后显示延迟、帧率和码率";
        [self updatePanel];
    }
    // The capsule keeps its width: only its title changes (dot color, summary).
    if (lineChanged || hadDetails != (details.length != 0)) [self updateInfo];
    [self syncPanel];
}
- (void)poll {
    if (invalidated) return;
    [self refreshFullscreen];
    [self syncPanel];
}
- (void)windowWillClose:(NSNotification*)notification {
    // The user closed the panel with its close button.
    if (notification.object != panel || !panelWanted) return;
    panelWanted = NO;
    [self send:office::Action::Statistics first:0 second:0];
}
- (NSArray<NSToolbarItemIdentifier>*)centerItemIdentifiers {
    NSMutableArray* items = [NSMutableArray arrayWithArray:@[officeDisplayId, officeInputId, officeFullscreenId]];
    if (hasDevices) [items addObject:officeDevicesId];
    return items;
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[officeInfoId, officeStatusId, officeDisplayId, officeInputId, officeFullscreenId, officeDevicesId,
        officeDisconnectId, NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    NSMutableArray* items = [NSMutableArray arrayWithObject:officeInfoId];
    if (@available(macOS 11.0, *)) {} else { [items addObject:officeStatusId]; }
    // The flexible spaces keep the disconnect button away from the icon group.
    [items addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [items addObjectsFromArray:[self centerItemIdentifiers]];
    [items addObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier, officeDisconnectId]];
    return items;
}
// An icon-only toolbar button; before macOS 11 (no SF Symbols) it shows its title.
- (void)decorateIconItem:(NSToolbarItem*)item symbols:(NSArray<NSString*>*)names title:(NSString*)title {
    NSImage* image = officeSymbol(names, title);
    if (image) item.image = image;
    else if (@available(macOS 10.15, *)) item.title = title;
    if (@available(macOS 10.15, *)) item.bordered = YES;
}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
        willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem* item = nil;
    NSMenuItem* overflow = nil;
    NSString* title = nil;
    const BOOL display = [identifier isEqualToString:officeDisplayId];
    if ([identifier isEqualToString:officeInfoId]) {
        title = @"连接信息";
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        item.view = infoButton;
        overflow = [self itemTitled:@"连接信息…" action:@selector(statistics:) tag:0];
    } else if ([identifier isEqualToString:officeStatusId]) {
        title = @"连接状态";
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        item.view = status;
    } else if (display || [identifier isEqualToString:officeInputId]) {
        // A click opens the menu (no primary action). NSMenuToolbarItem builds
        // its own overflow entry (label + this menu) and ignores a custom
        // menuFormRepresentation, so none is set here.
        title = display ? @"显示" : @"鼠标与键盘";
        NSMenuToolbarItem* menuItem = [[[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        menuItem.menu = display ? displayMenu : inputMenu;
        menuItem.showsIndicator = YES;
        item = menuItem;
        [self decorateIconItem:item symbols:display ? @[@"display"] : @[@"computermouse", @"keyboard"] title:title];
        item.toolTip = display ? @"显示：分辨率、画面缩放" : @"鼠标与键盘：鼠标模式、暂停输入";
    } else if ([identifier isEqualToString:officeFullscreenId]) {
        title = @"全屏";
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        item.target = self;
        item.action = @selector(fullscreen:);
        if (@available(macOS 10.15, *)) item.bordered = YES;
        overflow = [self itemTitled:[self fullscreenTitle] action:@selector(fullscreen:) tag:0];
        [fullscreenItem release];
        fullscreenItem = [item retain];
    } else if ([identifier isEqualToString:officeDevicesId]) {
        title = @"设备列表";
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        item.target = self;
        item.action = @selector(devices:);
        [self decorateIconItem:item symbols:@[@"list.bullet", @"rectangle.stack"] title:title];
        item.toolTip = @"设备列表";
        overflow = [self itemTitled:@"设备列表…" action:@selector(devices:) tag:0];
    } else if ([identifier isEqualToString:officeDisconnectId]) {
        title = @"断开";
        item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
        item.view = disconnectButton;
        overflow = [self itemTitled:title action:@selector(disconnect:) tag:0];
        overflow.attributedTitle = officeMenuTitle(title, nil, NO, NSColor.systemRedColor);
    } else {
        return nil;
    }
    item.label = title;
    item.paletteLabel = title;
    if ([item isKindOfClass:NSMenuToolbarItem.class]) return item;
    if (!overflow) overflow = [self itemTitled:title action:nil tag:0];
    item.menuFormRepresentation = overflow;
    if (item == fullscreenItem) [self decorateFullscreenItem];
    return item;
}
- (BOOL)validateToolbarItem:(NSToolbarItem*)item {
    (void)item;
    return !invalidated;
}
- (BOOL)validateMenuItem:(NSMenuItem*)item {
    if (invalidated) return NO;
    const SEL selector = item.action;
    BOOL on = NO;
    BOOL enabled = YES;
    if (selector == @selector(resolutionChanged:)) {
        on = item.tag == currentResolution;
        enabled = !confirmation;
    } else if (selector == @selector(scaleChanged:)) {
        on = [item.representedObject intValue] == currentScale;
        enabled = !scalePending && !confirmation;
    } else if (selector == @selector(mouseChanged:)) {
        on = item.tag == mouseMode;
    } else if (selector == @selector(inputPause:)) {
        on = inputPaused;
        enabled = !confirmation;
    } else if (selector == @selector(statistics:)) {
        on = panelWanted;
    } else if (selector == @selector(fullscreen:)) {
        [self refreshFullscreen];
        item.attributedTitle = officeMenuTitle([self fullscreenTitle], officeFullscreenShortcut, NO, nil);
    }
    item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    return enabled;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    panel.delegate = nil;
    [panel orderOut:nil];
    [panel release];
    [panelText release];
    [details release];
    [infoButton release];
    [infoWidth release];
    [deviceName release];
    [summaryLine release];
    [status release];
    [disconnectButton release];
    [displayMenu release];
    [inputMenu release];
    [builtMenus release];
    [fullscreenItem release];
    [confirmation release];
    [resolutions release];
    [resolutionTitles release];
    [scales release];
    [super dealloc];
}
@end

namespace office {
class MacToolbar final : public Toolbar {
    OfficeToolbarTarget* target;
    NSToolbar* nativeToolbar;
    NSToolbar* previousToolbar;
    NSWindowStyleMask previousStyle;
    BOOL previousTransparent;
    NSWindowTitleVisibility previousTitleVisibility;
    NSString* previousSubtitle;
    NSInteger previousToolbarStyle;
    std::vector<int> displayScales;
    int displayScale = 0;
    bool displayScalePending = true;
public:
    MacToolbar(NSWindow* parent, int width, int height, MouseMode mode,
               std::function<void(Action, int, int)> callback, bool hasDeviceManager,
               SDL_Window* sdlWindow = nullptr) {
        target = [[OfficeToolbarTarget alloc] init];
        target->action = std::move(callback);
        target->streamWindow = parent;
        target->sdlWindow = sdlWindow;
        target->hasDevices = hasDeviceManager;
        target->mouseMode = static_cast<NSInteger>(mode);
        NSMutableArray* sizes = [NSMutableArray array];
        NSMutableArray* titles = [NSMutableArray array];
        const int known[][2] = {{1280,720},{1920,1080},{1920,1200},{2560,1440},{2560,1600},{3840,2160}};
        target->currentResolution = -1;
        for (const auto& size : known) {
            if (width == size[0] && height == size[1]) target->currentResolution = (NSInteger)sizes.count;
            [sizes addObject:@[@(size[0]), @(size[1])]];
            [titles addObject:[NSString stringWithFormat:@"%d × %d", size[0], size[1]]];
        }
        if (target->currentResolution < 0) {
            target->currentResolution = (NSInteger)sizes.count;
            [sizes addObject:@[@(width), @(height)]];
            [titles addObject:[NSString stringWithFormat:@"当前 %d × %d", width, height]];
        }
        target->resolutions = [sizes copy];
        target->resolutionTitles = [titles copy];
        target->scales = [@[] retain];
        target->scalePending = YES;
        target->fullscreenShown = [target streamFullscreen];
        target->builtMenus = [[NSMutableArray alloc] init];
        target->summaryLine = [@"统计读取中" copy];
        // One button for the whole capsule: a single toolbar control gets one
        // system background (Liquid Glass on macOS 26) sized to it with the
        // button's own padding. Separate label items were grouped onto one
        // glass piece edge to edge, without padding or spacing.
        target->infoButton = [[NSButton buttonWithTitle:@"" target:target action:@selector(statistics:)] retain];
        target->infoButton.bezelStyle = NSBezelStyleTexturedRounded;
        target->infoButton.image = officeSymbol(@[@"info.circle"], @"连接信息");
        target->infoButton.imagePosition = NSImageTrailing;
        target->infoButton.imageHugsTitle = YES;
        target->infoButton.alignment = NSTextAlignmentLeft;
        target->infoButton.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        target->infoButton.toolTip = @"连接后显示延迟、帧率和码率";
        [target->infoButton setAccessibilityLabel:@"连接信息"];
        [target setDeviceName:@"远程电脑"];
        target->status = [[NSTextField labelWithString:@""] retain];
        target->status.frame = NSMakeRect(0, 0, 230, 20);
        target->displayMenu = [[target buildDisplayMenu] retain];
        target->inputMenu = [[target buildInputMenu] retain];
        target->disconnectButton = [[NSButton buttonWithTitle:@"断开" target:target
            action:@selector(disconnect:)] retain];
        target->disconnectButton.attributedTitle = [[[NSAttributedString alloc] initWithString:@"断开" attributes:@{
            NSFontAttributeName: target->disconnectButton.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize],
            NSForegroundColorAttributeName: NSColor.systemRedColor}] autorelease];
        if (@available(macOS 11.0, *)) target->disconnectButton.hasDestructiveAction = YES;
        target->disconnectButton.toolTip = @"断开连接；主动断开不会自动重连";
        [target->disconnectButton sizeToFit];
        previousToolbar = [parent.toolbar retain];
        previousStyle = parent.styleMask;
        previousTransparent = parent.titlebarAppearsTransparent;
        previousTitleVisibility = parent.titleVisibility;
        previousSubtitle = nil;
        if (@available(macOS 11.0, *)) previousSubtitle = [parent.subtitle copy];
        parent.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        parent.titlebarAppearsTransparent = NO;
        parent.titleVisibility = NSWindowTitleVisible;
        nativeToolbar = [[NSToolbar alloc] initWithIdentifier:@"office.session.toolbar"];
        nativeToolbar.delegate = target;
        nativeToolbar.displayMode = NSToolbarDisplayModeIconOnly;
        nativeToolbar.allowsUserCustomization = NO;
        nativeToolbar.autosavesConfiguration = NO;
        // Older systems center the icon group approximately with the two flexible spaces.
        if (@available(macOS 13.0, *)) {
            nativeToolbar.centeredItemIdentifiers = [NSSet setWithArray:[target centerItemIdentifiers]];
        }
        if (@available(macOS 11.0, *)) {
            previousToolbarStyle = parent.toolbarStyle;
            parent.toolbarStyle = NSWindowToolbarStyleExpanded;
        }
        parent.toolbar = nativeToolbar;
        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        [center addObserver:target selector:@selector(windowFullscreenChanged:)
            name:NSWindowDidEnterFullScreenNotification object:parent];
        [center addObserver:target selector:@selector(windowFullscreenChanged:)
            name:NSWindowDidExitFullScreenNotification object:parent];
        officeToolbarWindows().insert(parent);
        officeWrapFullscreenListener(parent);
        setStatus("分辨率切换会短暂重连");
    }
    ~MacToolbar() override {
        [target invalidate];
        NSWindow* parent = target->streamWindow;
        officeToolbarWindows().erase(parent);
        if (parent.toolbar == nativeToolbar) parent.toolbar = previousToolbar;
        nativeToolbar.delegate = nil;
        parent.styleMask = (parent.styleMask & ~NSWindowStyleMaskFullSizeContentView) |
            (previousStyle & NSWindowStyleMaskFullSizeContentView);
        parent.titlebarAppearsTransparent = previousTransparent;
        parent.titleVisibility = previousTitleVisibility;
        if (@available(macOS 11.0, *)) {
            parent.subtitle = previousSubtitle;
            parent.toolbarStyle = static_cast<NSWindowToolbarStyle>(previousToolbarStyle);
        }
        [previousSubtitle release];
        [previousToolbar release];
        [nativeToolbar release];
        [target release];
    }
    void setDeviceName(const char* name) override {
        NSString* text = [NSString stringWithUTF8String:name ? name : ""] ?: @"";
        [target setDeviceName:text];
    }
    void setInputPaused(bool paused) override {
        // Session state only (for example kept across a reconnect); no Action.
        if (!target->invalidated) target->inputPaused = paused ? YES : NO;
    }
    void setStatus(const char* text) override {
        // Polled from the session loop: also catches fullscreen changes that
        // have no notification, such as SDL's exclusive fullscreen.
        [target poll];
        NSString* message = [NSString stringWithUTF8String:text ? text : ""] ?: @"";
        if ([target->status.stringValue isEqualToString:message]) return;
        target->status.stringValue = message;
        if (@available(macOS 11.0, *)) target->streamWindow.subtitle = message;
    }
    void setDisplayScales(const std::vector<int>& supported, int current, bool pending) override {
        if (displayScales == supported && displayScale == current && displayScalePending == pending) return;
        displayScales = supported;
        displayScale = current;
        displayScalePending = pending;
        NSMutableArray* values = [NSMutableArray array];
        for (int value : supported) [values addObject:@(value)];
        [target->scales release];
        target->scales = [values copy];
        target->currentScale = current;
        target->scalePending = pending ? YES : NO;
        // Open menus are refreshed by menuNeedsUpdate: the next time they open.
    }
    void setStatistics(const char* summaryText, const char* detailText) override {
        NSString* line = [NSString stringWithUTF8String:summaryText ? summaryText : ""] ?: @"";
        NSString* full = [NSString stringWithUTF8String:detailText ? detailText : ""] ?: @"";
        [target setSummary:line details:full];
    }
    void setStatisticsVisible(bool visible) override {
        if (!target->invalidated) [target setPanelVisible:visible ? YES : NO];
    }
};

std::unique_ptr<Toolbar> createToolbar(SDL_Window* window, int width, int height,
        MouseMode mode, std::function<void(Action, int, int)> action, bool hasDeviceManager) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) return {};
    return std::make_unique<MacToolbar>(info.info.cocoa.window, width, height, mode, std::move(action),
        hasDeviceManager, window);
}
}
