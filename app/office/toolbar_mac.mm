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

@interface OfficeToolbarTarget : NSObject <NSToolbarDelegate, NSMenuItemValidation, NSWindowDelegate> {
@public
    std::function<void(office::Action, int, int)> action;
    NSWindow* streamWindow;
    SDL_Window* sdlWindow;
    NSPopUpButton* resolution;
    NSPopUpButton* mouse;
    NSPopUpButton* scale;
    NSTextField* status;
    NSButton* fullscreenButton;
    NSButton* statisticsButton;
    NSTextField* summary;
    NSString* details;
    OfficeStatisticsPanel* panel;
    NSTextField* panelText;
    NSAlert* confirmation;
    NSInteger currentResolution;
    BOOL invalidated;
    BOOL hasDevices;
    BOOL fullscreenShown;
    BOOL panelWanted;
}
- (void)resolutionChanged:(id)sender;
- (void)scaleChanged:(id)sender;
- (void)mouseChanged:(id)sender;
- (void)fullscreen:(id)sender;
- (void)statistics:(id)sender;
- (void)disconnect:(id)sender;
- (void)devices:(id)sender;
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
    if ([sender isKindOfClass:[NSMenuItem class]]) [mouse selectItemAtIndex:[sender tag]];
    [self send:office::Action::Mouse first:(int)mouse.indexOfSelectedItem second:0];
}
- (void)scaleChanged:(id)sender {
    if (!scale.enabled || invalidated) return;
    if ([sender isKindOfClass:[NSMenuItem class]]) [scale selectItemAtIndex:[sender tag]];
    [self send:office::Action::DisplayScale first:[scale.selectedItem.representedObject intValue] second:0];
}
- (void)resolutionChanged:(id)sender {
    if (invalidated || confirmation) return;
    if ([sender isKindOfClass:[NSMenuItem class]]) [resolution selectItemAtIndex:[sender tag]];
    const NSInteger proposed = resolution.indexOfSelectedItem;
    if (proposed == currentResolution) return;
    NSArray* size = resolution.selectedItem.representedObject;
    const int width = [size[0] intValue], height = [size[1] intValue];
    // A proposed value is never displayed as the current remote resolution.
    [resolution selectItemAtIndex:currentResolution];
    [self retain];
    [self send:office::Action::InputPause first:1 second:0];
    if (invalidated) { [self release]; return; }
    confirmation = [[NSAlert alloc] init];
    confirmation.messageText = [NSString stringWithFormat:@"切换到 %d×%d？", width, height];
    confirmation.informativeText = @"将短暂重连，Windows不会注销";
    [confirmation addButtonWithTitle:@"切换"];
    [confirmation addButtonWithTitle:@"取消"];
    confirmation.buttons[0].keyEquivalent = @"";
    confirmation.buttons[1].keyEquivalent = @"\033";
    resolution.enabled = NO;
    [confirmation beginSheetModalForWindow:streamWindow completionHandler:^(NSModalResponse response) {
        [confirmation release];
        confirmation = nil;
        if (invalidated) return;
        resolution.enabled = YES;
        [resolution selectItemAtIndex:currentResolution];
        [self send:office::Action::InputPause first:0 second:0];
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
- (NSString*)fullscreenTitle { return fullscreenShown ? @"退出全屏" : @"全屏"; }
- (void)refreshFullscreen {
    const BOOL shown = [self streamFullscreen];
    if (shown == fullscreenShown) return;
    fullscreenShown = shown;
    NSString* title = [self fullscreenTitle];
    fullscreenButton.title = title;
    [fullscreenButton sizeToFit];
    if (streamWindow.toolbar.delegate != self) return;
    for (NSToolbarItem* item in streamWindow.toolbar.items) {
        if (![item.itemIdentifier isEqualToString:@"office.fullscreen"]) continue;
        item.label = title;
        item.paletteLabel = title;
        item.menuFormRepresentation.title = title;
    }
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
        // would then do nothing. Toggle the Space natively so the button always
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
- (void)invalidate {
    invalidated = YES;
    action = {};
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    panel.delegate = nil;
    [panel orderOut:nil];
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
    panel.title = @"连接统计";
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
    statisticsButton.state = visible ? NSControlStateValueOn : NSControlStateValueOff;
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
    statisticsButton.state = NSControlStateValueOff;
    [self send:office::Action::Statistics first:0 second:0];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[@"office.mouse", @"office.resolution", @"office.scale", @"office.fullscreen", @"office.statistics",
        @"office.devices", @"office.disconnect", @"office.status", @"office.summary", NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    NSMutableArray* items = [NSMutableArray arrayWithArray:@[@"office.mouse", @"office.resolution", @"office.scale",
        @"office.fullscreen", @"office.statistics"]];
    if (hasDevices) [items addObject:@"office.devices"];
    [items addObject:@"office.disconnect"];
    if (@available(macOS 11.0, *)) {} else { [items addObject:@"office.status"]; }
    [items addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [items addObject:@"office.summary"];
    return items;
}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
        willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem* item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    NSPopUpButton* popup = nil;
    NSButton* button = nil;
    NSView* view = nil;
    SEL selector = nullptr;
    NSString* title = nil;
    if ([identifier isEqualToString:@"office.mouse"]) { popup = mouse; title = @"鼠标"; selector = @selector(mouseChanged:); }
    else if ([identifier isEqualToString:@"office.resolution"]) { popup = resolution; title = @"远端分辨率"; selector = @selector(resolutionChanged:); }
    else if ([identifier isEqualToString:@"office.scale"]) { popup = scale; title = @"Windows缩放"; selector = @selector(scaleChanged:); }
    else if ([identifier isEqualToString:@"office.fullscreen"]) { button = fullscreenButton; title = [self fullscreenTitle]; selector = @selector(fullscreen:); }
    else if ([identifier isEqualToString:@"office.statistics"]) { button = statisticsButton; title = @"统计"; selector = @selector(statistics:); }
    else if ([identifier isEqualToString:@"office.devices"]) { title = @"设备"; selector = @selector(devices:); }
    else if ([identifier isEqualToString:@"office.disconnect"]) { title = @"断开"; selector = @selector(disconnect:); }
    else if ([identifier isEqualToString:@"office.status"]) { title = @"连接状态"; view = status; }
    else if ([identifier isEqualToString:@"office.summary"]) { title = @"连接统计"; view = summary; selector = @selector(statistics:); }
    else return nil;
    item.label = title;
    item.paletteLabel = title;
    item.target = self;
    item.action = selector;
    NSMenuItem* overflow = [[[NSMenuItem alloc] initWithTitle:title action:selector keyEquivalent:@""] autorelease];
    overflow.target = self;
    if (popup) {
        item.view = popup;
        item.toolTip = popup.toolTip;
        overflow.enabled = popup.enabled;
        NSMenu* menu = [[[NSMenu alloc] initWithTitle:title] autorelease];
        for (NSInteger i = 0; i < popup.numberOfItems; ++i) {
            NSMenuItem* choice = [[[NSMenuItem alloc] initWithTitle:[popup itemAtIndex:i].title action:selector keyEquivalent:@""] autorelease];
            choice.target = self;
            choice.tag = i;
            choice.enabled = popup.enabled;
            choice.state = i == popup.indexOfSelectedItem ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:choice];
        }
        overflow.submenu = menu;
        if (popup.constraints.count == 0) {
            [popup.widthAnchor constraintEqualToConstant:popup.frame.size.width].active = YES;
            [popup.heightAnchor constraintEqualToConstant:popup.frame.size.height].active = YES;
        }
    } else if (view) {
        item.view = view;
    } else if (selector) {
        if (!button) {
            button = [NSButton buttonWithTitle:title target:self action:selector];
            [button sizeToFit];
        }
        item.view = button;
    }
    item.menuFormRepresentation = overflow;
    return item;
}
- (BOOL)validateMenuItem:(NSMenuItem*)item {
    NSPopUpButton* popup = nil;
    if (item.action == @selector(resolutionChanged:)) popup = resolution;
    else if (item.action == @selector(scaleChanged:)) popup = scale;
    else if (item.action == @selector(mouseChanged:)) popup = mouse;
    if (popup) {
        // The pop-up button's own menu shares this target and action; it marks
        // its selected item itself. Only the overflow submenu choices carry
        // their index in the tag.
        if (item.menu != popup.menu && !item.hasSubmenu) {
            item.state = item.tag == popup.indexOfSelectedItem ? NSControlStateValueOn : NSControlStateValueOff;
        }
        return !invalidated && popup.enabled;
    }
    if (item.action == @selector(statistics:)) {
        item.state = panelWanted ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (item.action == @selector(fullscreen:)) {
        [self refreshFullscreen];
        item.title = [self fullscreenTitle];
    }
    return !invalidated;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    panel.delegate = nil;
    [panel orderOut:nil];
    [panel release];
    [panelText release];
    [details release];
    [summary release];
    [statisticsButton release];
    [fullscreenButton release];
    [confirmation release];
    [mouse release];
    [resolution release];
    [scale release];
    [status release];
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
        target->mouse = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 150, 26) pullsDown:NO];
        [target->mouse addItemsWithTitles:@[@"办公 · 本地光标", @"办公 · 远端光标", @"相对鼠标"]];
        [target->mouse selectItemAtIndex:static_cast<int>(mode)];
        target->mouse.target = target;
        target->mouse.action = @selector(mouseChanged:);
        target->resolution = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 150, 26) pullsDown:NO];
        const int sizes[][2] = {{1280,720},{1920,1080},{1920,1200},{2560,1440},{2560,1600},{3840,2160}};
        bool matched = false;
        for (const auto& size : sizes) {
            [target->resolution addItemWithTitle:[NSString stringWithFormat:@"%d × %d", size[0], size[1]]];
            target->resolution.lastItem.representedObject = @[@(size[0]), @(size[1])];
            if (width == size[0] && height == size[1]) {
                [target->resolution selectItem:target->resolution.lastItem];
                matched = true;
            }
        }
        if (!matched) {
            [target->resolution addItemWithTitle:[NSString stringWithFormat:@"当前 %d × %d", width, height]];
            target->resolution.lastItem.representedObject = @[@(width), @(height)];
            [target->resolution selectItem:target->resolution.lastItem];
        }
        target->currentResolution = target->resolution.indexOfSelectedItem;
        target->resolution.target = target;
        target->resolution.action = @selector(resolutionChanged:);
        target->resolution.toolTip = @"修改远端桌面分辨率；确认后会短暂重连，Windows不会注销";
        target->scale = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 155, 26) pullsDown:NO];
        [target->scale addItemWithTitle:@"Windows缩放 · 读取中"];
        target->scale.enabled = NO;
        target->scale.toolTip = @"修改Windows系统文字和图标大小（DPI），显示可能短暂闪烁";
        target->scale.target = target;
        target->scale.action = @selector(scaleChanged:);
        target->status = [[NSTextField labelWithString:@""] retain];
        target->status.frame = NSMakeRect(0, 0, 230, 20);
        target->fullscreenShown = [target streamFullscreen];
        target->fullscreenButton = [[NSButton buttonWithTitle:[target fullscreenTitle] target:target
            action:@selector(fullscreen:)] retain];
        [target->fullscreenButton sizeToFit];
        target->statisticsButton = [[NSButton buttonWithTitle:@"统计" target:target action:@selector(statistics:)] retain];
        [target->statisticsButton setButtonType:NSButtonTypePushOnPushOff];
        target->statisticsButton.state = NSControlStateValueOff;
        target->statisticsButton.toolTip = @"显示或隐藏连接统计浮窗";
        [target->statisticsButton sizeToFit];
        target->summary = [[NSTextField labelWithString:@"统计读取中"] retain];
        target->summary.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize
            weight:NSFontWeightRegular];
        target->summary.textColor = NSColor.secondaryLabelColor;
        target->summary.alignment = NSTextAlignmentRight;
        target->summary.lineBreakMode = NSLineBreakByTruncatingTail;
        target->summary.toolTip = @"连接后显示延迟、帧率和码率";
        // Fixed width: per-second updates must not relayout the toolbar.
        [target->summary.widthAnchor constraintEqualToConstant:260].active = YES;
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
        [target->scale removeAllItems];
        if (supported.empty()) {
            [target->scale addItemWithTitle:pending ? @"Windows缩放 · 读取中" : @"Windows缩放 · 不可用"];
        } else {
            for (int value : supported) {
                [target->scale addItemWithTitle:[NSString stringWithFormat:@"Windows缩放 · %d%%", value]];
                target->scale.lastItem.representedObject = @(value);
                if (value == current) [target->scale selectItem:target->scale.lastItem];
            }
            if (pending) target->scale.toolTip = @"Windows缩放正在设置，请稍候";
            else target->scale.toolTip = @"修改Windows系统文字和图标大小（DPI），显示可能短暂闪烁";
        }
        target->scale.enabled = !pending && !supported.empty();
        // Rebuild overflow menus to reflect the host's actual supported choices.
        const NSInteger index = [nativeToolbar.items indexOfObjectPassingTest:^BOOL(NSToolbarItem* item, NSUInteger, BOOL*) {
            return [item.itemIdentifier isEqualToString:@"office.scale"];
        }];
        if (index != NSNotFound) {
            [nativeToolbar removeItemAtIndex:index];
            [nativeToolbar insertItemWithItemIdentifier:@"office.scale" atIndex:index];
        }
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
