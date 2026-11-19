#import <AppKit/AppKit.h>
#include <SDL_syswm.h>
#include "toolbar.h"

// All AppKit work and callbacks run on the session's main thread. The sheet owns
// its completion target until dismissal; invalidation clears the session callback
// before ending the sheet, so delayed completions cannot reach a dead session.
@interface OfficeToolbarTarget : NSObject <NSToolbarDelegate, NSMenuItemValidation> {
@public
    std::function<void(office::Action, int, int)> action;
    NSWindow* streamWindow;
    NSPopUpButton* resolution;
    NSPopUpButton* mouse;
    NSPopUpButton* scale;
    NSTextField* status;
    NSAlert* confirmation;
    NSInteger currentResolution;
    BOOL invalidated;
    BOOL hasDevices;
}
- (void)resolutionChanged:(id)sender;
- (void)scaleChanged:(id)sender;
- (void)mouseChanged:(id)sender;
- (void)fullscreen:(id)sender;
- (void)statistics:(id)sender;
- (void)disconnect:(id)sender;
- (void)devices:(id)sender;
- (void)invalidate;
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
- (void)fullscreen:(id)sender { (void)sender; [self send:office::Action::Fullscreen first:0 second:0]; }
- (void)statistics:(id)sender { (void)sender; [self send:office::Action::Statistics first:0 second:0]; }
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
    if (confirmation) {
        [streamWindow endSheet:confirmation.window returnCode:NSModalResponseCancel];
        [confirmation.window orderOut:nil];
    }
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[@"office.mouse", @"office.resolution", @"office.scale", @"office.fullscreen", @"office.statistics",
        @"office.devices", @"office.disconnect", @"office.status", NSToolbarFlexibleSpaceItemIdentifier];
}
- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    NSMutableArray* items = [NSMutableArray arrayWithArray:@[@"office.mouse", @"office.resolution", @"office.scale",
        @"office.fullscreen", @"office.statistics"]];
    if (hasDevices) [items addObject:@"office.devices"];
    [items addObject:@"office.disconnect"];
    if (@available(macOS 11.0, *)) {} else { [items addObject:@"office.status"]; }
    return items;
}
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
        willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar; (void)inserted;
    NSToolbarItem* item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    NSPopUpButton* popup = nil;
    SEL selector = nullptr;
    NSString* title = nil;
    if ([identifier isEqualToString:@"office.mouse"]) { popup = mouse; title = @"鼠标"; selector = @selector(mouseChanged:); }
    else if ([identifier isEqualToString:@"office.resolution"]) { popup = resolution; title = @"远端分辨率"; selector = @selector(resolutionChanged:); }
    else if ([identifier isEqualToString:@"office.scale"]) { popup = scale; title = @"Windows缩放"; selector = @selector(scaleChanged:); }
    else if ([identifier isEqualToString:@"office.fullscreen"]) { title = @"全屏"; selector = @selector(fullscreen:); }
    else if ([identifier isEqualToString:@"office.statistics"]) { title = @"统计"; selector = @selector(statistics:); }
    else if ([identifier isEqualToString:@"office.devices"]) { title = @"设备"; selector = @selector(devices:); }
    else if ([identifier isEqualToString:@"office.disconnect"]) { title = @"断开"; selector = @selector(disconnect:); }
    else if ([identifier isEqualToString:@"office.status"]) { title = @"连接状态"; item.view = status; }
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
    } else if (selector) {
        NSButton* button = [NSButton buttonWithTitle:title target:self action:selector];
        [button sizeToFit];
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
        if (!item.hasSubmenu) item.state = item.tag == popup.indexOfSelectedItem ? NSControlStateValueOn : NSControlStateValueOff;
        return !invalidated && popup.enabled;
    }
    return !invalidated;
}
- (void)dealloc {
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
               std::function<void(Action, int, int)> callback, bool hasDeviceManager) {
        target = [[OfficeToolbarTarget alloc] init];
        target->action = std::move(callback);
        target->streamWindow = parent;
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
        setStatus("分辨率切换会短暂重连");
    }
    ~MacToolbar() override {
        [target invalidate];
        NSWindow* parent = target->streamWindow;
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
};

std::unique_ptr<Toolbar> createToolbar(SDL_Window* window, int width, int height,
        MouseMode mode, std::function<void(Action, int, int)> action, bool hasDeviceManager) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) return {};
    return std::make_unique<MacToolbar>(info.info.cocoa.window, width, height, mode, std::move(action), hasDeviceManager);
}
}
