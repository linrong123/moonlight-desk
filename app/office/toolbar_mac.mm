#import <AppKit/AppKit.h>
#include <SDL_syswm.h>
#include "toolbar.h"

@interface OfficeToolbarTarget : NSObject {
@public
    std::function<void(office::Action, int, int)> action;
    NSPanel* panel;
    NSWindow* streamWindow;
    NSPopUpButton* resolution;
    NSPopUpButton* mouse;
    NSTextField* status;
}
- (void)mouseChanged:(id)sender;
- (void)applyResolution:(id)sender;
- (void)fullscreen:(id)sender;
- (void)statistics:(id)sender;
- (void)disconnect:(id)sender;
- (void)reposition:(NSNotification*)notification;
@end

@implementation OfficeToolbarTarget
- (void)mouseChanged:(id)sender {
    (void)sender;
    action(office::Action::Mouse, (int)mouse.indexOfSelectedItem, 0);
}
- (void)applyResolution:(id)sender {
    (void)sender;
    NSArray* size = resolution.selectedItem.representedObject;
    action(office::Action::Resolution, [size[0] intValue], [size[1] intValue]);
}
- (void)fullscreen:(id)sender { (void)sender; action(office::Action::Fullscreen, 0, 0); }
- (void)statistics:(id)sender { (void)sender; action(office::Action::Statistics, 0, 0); }
- (void)disconnect:(id)sender { (void)sender; action(office::Action::Disconnect, 0, 0); }
- (void)reposition:(NSNotification*)notification {
    (void)notification;
    NSRect parent = streamWindow.frame;
    NSRect frame = panel.frame;
    NSRect screen = streamWindow.screen.visibleFrame;
    frame.origin.x = std::max(NSMinX(screen), std::min(NSMidX(parent) - frame.size.width / 2,
                                                    NSMaxX(screen) - frame.size.width));
    frame.origin.y = std::max(NSMinY(screen), std::min(NSMaxY(parent) - 110, NSMaxY(screen) - frame.size.height));
    [panel setFrame:frame display:YES];
}
@end

namespace office {
class MacToolbar final : public Toolbar {
    OfficeToolbarTarget* target;
public:
    MacToolbar(NSWindow* parent, int width, int height, MouseMode mode,
               std::function<void(Action, int, int)> callback) {
        target = [[OfficeToolbarTarget alloc] init];
        target->action = std::move(callback);
        target->streamWindow = parent;
        target->panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 700, 76)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        NSPanel* p = target->panel;
        p.title = @"办公工具栏";
        p.hidesOnDeactivate = YES;
        p.movableByWindowBackground = YES;
        p.releasedWhenClosed = NO;
        p.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
        auto label = [NSTextField labelWithString:@"鼠标"];
        label.frame = NSMakeRect(12, 44, 32, 20);
        [p.contentView addSubview:label];
        target->mouse = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(48, 39, 142, 28) pullsDown:NO];
        [target->mouse addItemsWithTitles:@[@"办公 · 本地光标", @"办公 · 远端光标", @"相对鼠标"]];
        [target->mouse selectItemAtIndex:static_cast<int>(mode)];
        target->mouse.target = target;
        target->mouse.action = @selector(mouseChanged:);
        [p.contentView addSubview:target->mouse];
        target->resolution = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(202, 39, 147, 28) pullsDown:NO];
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
        [p.contentView addSubview:target->resolution];
        NSArray* titles = @[@"应用", @"全屏", @"统计", @"断开"];
        SEL selectors[] = {@selector(applyResolution:), @selector(fullscreen:), @selector(statistics:), @selector(disconnect:)};
        for (int i = 0; i < 4; ++i) {
            NSButton* button = [NSButton buttonWithTitle:titles[i] target:target action:selectors[i]];
            button.frame = NSMakeRect(355 + i * 84, 39, 78, 28);
            [p.contentView addSubview:button];
        }
        target->status = [[NSTextField labelWithString:@"分辨率应用时会短暂重连"] retain];
        target->status.frame = NSMakeRect(14, 8, 670, 20);
        target->status.font = [NSFont systemFontOfSize:12];
        target->status.textColor = NSColor.secondaryLabelColor;
        [p.contentView addSubview:target->status];
        for (NSNotificationName name in @[NSWindowDidMoveNotification, NSWindowDidResizeNotification,
                                          NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:target selector:@selector(reposition:) name:name object:parent];
        }
        [parent addChildWindow:p ordered:NSWindowAbove];
        [target reposition:nil];
        [p orderFront:nil];
    }
    ~MacToolbar() override {
        [NSNotificationCenter.defaultCenter removeObserver:target];
        [target->streamWindow removeChildWindow:target->panel];
        [target->panel orderOut:nil];
        target->action = {};
        [target->mouse release];
        [target->resolution release];
        [target->status release];
        [target->panel release];
        [target release];
    }
    void setStatus(const char* text) override {
        NSString* message = [NSString stringWithUTF8String:text];
        if (![target->status.stringValue isEqualToString:message]) target->status.stringValue = message;
    }
};

std::unique_ptr<Toolbar> createToolbar(SDL_Window* window, int width, int height,
        MouseMode mode, std::function<void(Action, int, int)> action) {
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) return {};
    return std::make_unique<MacToolbar>(info.info.cocoa.window, width, height, mode, std::move(action));
}
}
