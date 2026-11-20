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

@interface OfficeToolbarTarget : NSObject <NSToolbarDelegate, NSMenuItemValidation, NSMenuDelegate, NSWindowDelegate> {
@public
    std::function<void(office::Action, int, int)> action;
    NSWindow* streamWindow;
    SDL_Window* sdlWindow;
    // Toolbar: device name and statistics summary on the left, the control
    // center menu and the disconnect button on the right.
    NSTextField* device;
    NSTextField* summary;
    NSTextField* status;
    NSButton* controlButton;
    NSButton* disconnectButton;
    NSMenu* controlMenu;
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
- (void)showControlCenter:(id)sender;
- (NSMenu*)buildControlMenu;
- (void)invalidate;
- (BOOL)streamFullscreen;
- (NSString*)fullscreenTitle;
- (void)poll;
- (void)setPanelVisible:(BOOL)visible;
- (void)setSummary:(NSString*)line details:(NSString*)full;
@end

@implementation OfficeToolbarTarget
- (void)send:(office::Action)kind first:(int)first second:(int)second {
    // The callback can destroy MacToolbar (and clear action) synchronously.
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
- (void)refreshFullscreen { fullscreenShown = [self streamFullscreen]; }
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
    auto callback = action;
    [self invalidate];
    if (callback) callback(office::Action::Disconnect, 0, 0);
}
- (void)devices:(id)sender { (void)sender; [self send:office::Action::Devices first:0 second:0]; }
- (void)showControlCenter:(id)sender {
    if (invalidated) return;
    NSView* anchor = [sender isKindOfClass:[NSView class]] ? sender : controlButton;
    if (!anchor.window) return;
    const NSRect bounds = anchor.bounds;
    const NSPoint below = NSMakePoint(NSMinX(bounds), anchor.isFlipped ? NSMaxY(bounds) + 4 : NSMinY(bounds) - 4);
    // Menu actions run inside the tracking loop and may destroy the toolbar.
    [self retain];
    [controlMenu popUpMenuPositioningItem:nil atLocation:below inView:anchor];
    [self release];
}
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
- (NSMenu*)buildControlMenu {
    NSMenu* menu = [[[NSMenu alloc] initWithTitle:@"控制中心"] autorelease];
    NSMenu* display = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSMenu* resolutionMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    for (NSUInteger i = 0; i < resolutions.count; ++i) {
        NSMenuItem* item = [self itemTitled:resolutionTitles[i] action:@selector(resolutionChanged:) tag:(NSInteger)i];
        item.toolTip = @"修改远端桌面分辨率；确认后会短暂重连，Windows不会注销";
        [resolutionMenu addItem:item];
    }
    [display addItem:[self submenuTitled:@"分辨率" items:resolutionMenu]];
    NSMenu* scaleMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [display addItem:[self submenuTitled:@"画面缩放" items:scaleMenu]];
    scaleMenu.delegate = self;
    [self fillScaleMenu:scaleMenu];
    [menu addItem:[self submenuTitled:@"显示" items:display]];
    NSMenu* input = [[[NSMenu alloc] initWithTitle:@""] autorelease];
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
    [menu addItem:[self submenuTitled:@"鼠标与键盘" items:input]];
    [menu addItem:[self itemTitled:@"连接信息…" action:@selector(statistics:) tag:0]];
    if (hasDevices) [menu addItem:[self itemTitled:@"设备列表…" action:@selector(devices:) tag:0]];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* fullscreenItem = [self itemTitled:[self fullscreenTitle] action:@selector(fullscreen:) tag:0];
    fullscreenItem.attributedTitle = officeMenuTitle([self fullscreenTitle], officeFullscreenShortcut, NO, nil);
    [menu addItem:fullscreenItem];
    NSMenuItem* disconnectItem = [self itemTitled:@"断开连接" action:@selector(disconnect:) tag:0];
    disconnectItem.attributedTitle = officeMenuTitle(@"断开连接", nil, NO, NSColor.systemRedColor);
    [menu addItem:disconnectItem];
    return menu;
}
- (void)invalidate {
    invalidated = YES;
    action = {};
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    panel.delegate = nil;
    [panel orderOut:nil];
    [controlMenu cancelTrackingWithoutAnimation];
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
    if (![summary.stringValue isEqualToString:shown]) summary.stringValue = shown;
    if (![details isEqualToString:full]) {
        [details release];
        details = [full copy];
        summary.toolTip = full.length ? full : @"连接后显示延迟、帧率和码率";
        [self updatePanel];
    }
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
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[@"office.device", @"office.summary", @"office.status", @"office.control", @"office.disconnect",
        NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    NSMutableArray* items = [NSMutableArray arrayWithArray:@[@"office.device", @"office.summary"]];
    if (@available(macOS 11.0, *)) {} else { [items addObject:@"office.status"]; }
    [items addObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier, @"office.control", @"office.disconnect"]];
    return items;
}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
        willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem* item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    NSMenuItem* overflow = nil;
    NSString* title = nil;
    if ([identifier isEqualToString:@"office.device"]) {
        title = @"设备";
        item.view = device;
    } else if ([identifier isEqualToString:@"office.summary"]) {
        title = @"连接信息";
        item.view = summary;
        overflow = [self itemTitled:@"连接信息…" action:@selector(statistics:) tag:0];
    } else if ([identifier isEqualToString:@"office.status"]) {
        title = @"连接状态";
        item.view = status;
    } else if ([identifier isEqualToString:@"office.control"]) {
        title = @"控制中心";
        item.view = controlButton;
        // Narrow windows move the item into the overflow menu: same structure.
        overflow = [self submenuTitled:title items:[self buildControlMenu]];
    } else if ([identifier isEqualToString:@"office.disconnect"]) {
        title = @"断开";
        item.view = disconnectButton;
        overflow = [self itemTitled:title action:@selector(disconnect:) tag:0];
        overflow.attributedTitle = officeMenuTitle(title, nil, NO, NSColor.systemRedColor);
    } else {
        return nil;
    }
    item.label = title;
    item.paletteLabel = title;
    if (!overflow) overflow = [self itemTitled:title action:nil tag:0];
    item.menuFormRepresentation = overflow;
    return item;
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
    [device release];
    [summary release];
    [status release];
    [controlButton release];
    [disconnectButton release];
    [controlMenu release];
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
        target->device = [[NSTextField labelWithString:@"远程电脑"] retain];
        target->device.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
        target->device.lineBreakMode = NSLineBreakByTruncatingTail;
        [target->device.widthAnchor constraintLessThanOrEqualToConstant:220].active = YES;
        target->summary = [[NSTextField labelWithString:@"统计读取中"] retain];
        target->summary.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize
            weight:NSFontWeightRegular];
        target->summary.textColor = NSColor.secondaryLabelColor;
        target->summary.lineBreakMode = NSLineBreakByTruncatingTail;
        target->summary.toolTip = @"连接后显示延迟、帧率和码率";
        // Fixed width: per-second updates must not relayout the toolbar.
        [target->summary.widthAnchor constraintEqualToConstant:260].active = YES;
        target->status = [[NSTextField labelWithString:@""] retain];
        target->status.frame = NSMakeRect(0, 0, 230, 20);
        target->controlMenu = [[target buildControlMenu] retain];
        target->controlButton = [[NSButton buttonWithTitle:@"控制中心 ▾" target:target
            action:@selector(showControlCenter:)] retain];
        target->controlButton.toolTip = @"显示、鼠标与键盘、连接信息、全屏和断开";
        [target->controlButton sizeToFit];
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
        if (!text.length) text = @"远程电脑";
        if ([target->device.stringValue isEqualToString:text]) return;
        target->device.stringValue = text;
        target->device.toolTip = text;
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
