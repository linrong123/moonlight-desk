#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <Block.h>
#include "../../../app/office/toolbar_mac.mm"
#include <cassert>
#include <tuple>
#include <vector>
static int subtitleWrites;
@interface HiddenStatusWindow : NSWindow
@end
@implementation HiddenStatusWindow
- (void)setSubtitle:(NSString*)value { ++subtitleWrites; [super setSubtitle:value]; }
@end
static void (^pendingCompletion)(NSModalResponse);
@interface NSAlert (HiddenToolbarCheck)
- (void)hiddenBegin:(NSWindow*)window completionHandler:(void (^)(NSModalResponse))completion;
@end
@implementation NSAlert (HiddenToolbarCheck)
- (void)hiddenBegin:(NSWindow*)window completionHandler:(void (^)(NSModalResponse))completion {
    assert(!window.visible);
    assert(!pendingCompletion);
    pendingCompletion = Block_copy(completion);
}
@end
static void complete(NSModalResponse response) {
    auto block = pendingCompletion;
    pendingCompletion = nil;
    block(response);
    Block_release(block);
}
int main() { @autoreleasepool {
    [NSApplication sharedApplication];
    method_exchangeImplementations(class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:)),
        class_getInstanceMethod(NSAlert.class, @selector(hiddenBegin:completionHandler:)));
    NSWindow* window = [[HiddenStatusWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO;
    NSView* originalContent = window.contentView;
    const NSRect initialLayout = window.contentLayoutRect;
    std::vector<std::tuple<office::Action,int,int>> events;
    auto toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int x,int y){events.emplace_back(a,x,y);},true);
    auto target = (OfficeToolbarTarget*)window.toolbar.delegate;
    assert(window.toolbar && !window.visible && window.childWindows.count == 0);
    assert(window.contentView == originalContent && originalContent.subviews.count == 0);
    assert(!(window.styleMask & NSWindowStyleMaskFullSizeContentView));
    assert(window.contentLayoutRect.size.height <= initialLayout.size.height);
    assert(window.contentLayoutRect.size.width > 0 && window.contentLayoutRect.size.height > 0);
    toolbar->setStatus("本地状态");
    const int writes = subtitleWrites;
    toolbar->setStatus("本地状态");
    assert(subtitleWrites == writes);
    toolbar->setStatus("状态已变");
    assert(subtitleWrites == writes + 1);
    assert(!target->scale.enabled);
    toolbar->setDisplayScales({100,125,150,200},150,false);
    assert(target->scale.enabled && [target->scale.selectedItem.representedObject intValue] == 150);
    NSToolbarItem* scaleItem = window.toolbar.items[2];
    toolbar->setDisplayScales({100,125,150,200},150,false);
    assert(window.toolbar.items[2] == scaleItem);
    [target->scale selectItemAtIndex:3]; [target scaleChanged:target->scale];
    assert(events.back() == std::make_tuple(office::Action::DisplayScale,200,0));
    toolbar->setDisplayScales({},0,false); assert(!target->scale.enabled);
    auto toolbarItem = [&](NSString* identifier) -> NSToolbarItem* {
        for (NSToolbarItem* item in window.toolbar.items) if ([item.itemIdentifier isEqualToString:identifier]) return item;
        return nil;
    };
    // Pop-up menus keep their own single check mark; only overflow choices are
    // marked by validation (tag = index).
    assert(target->mouse.indexOfSelectedItem == 0);
    for (NSMenuItem* item in target->mouse.menu.itemArray) assert([target validateMenuItem:item]);
    assert([target->mouse itemAtIndex:0].state == NSControlStateValueOn);
    assert([target->mouse itemAtIndex:1].state == NSControlStateValueOff && [target->mouse itemAtIndex:2].state == NSControlStateValueOff);
    NSMenu* mouseOverflow = toolbarItem(@"office.mouse").menuFormRepresentation.submenu;
    [target->mouse selectItemAtIndex:2];
    for (NSMenuItem* item in mouseOverflow.itemArray) [target validateMenuItem:item];
    assert(mouseOverflow.itemArray[2].state == NSControlStateValueOn && mouseOverflow.itemArray[0].state == NSControlStateValueOff);
    assert([target->mouse itemAtIndex:0].state == NSControlStateValueOff && [target->mouse itemAtIndex:2].state == NSControlStateValueOn);
    [target->mouse selectItemAtIndex:0];
    // The fullscreen label follows the real window state.
    NSMenuItem* fullscreenOverflow = toolbarItem(@"office.fullscreen").menuFormRepresentation;
    [target validateMenuItem:fullscreenOverflow];
    assert([target->fullscreenButton.title isEqualToString:@"全屏"] && [fullscreenOverflow.title isEqualToString:@"全屏"]);
    // Spaces fullscreen: SDL's hidden menu bar becomes auto-hide with the toolbar;
    // only valid AppKit combinations are produced.
    using O = NSApplicationPresentationOptions;
    const O sdlDesktop = NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    assert(officeFullscreenOptions(sdlDesktop) == (NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock |
        NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideToolbar));
    const O proposed = NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock;
    assert(officeFullscreenOptions(proposed) == (proposed | NSApplicationPresentationAutoHideToolbar));
    assert(officeFullscreenOptions(NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar) ==
        (NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock |
         NSApplicationPresentationAutoHideToolbar));
    assert(officeFullscreenOptions(NSApplicationPresentationFullScreen) == NSApplicationPresentationFullScreen);
    const O windowed = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    assert(officeFullscreenOptions(windowed) == windowed);
    // Resident statistics summary; details are the tooltip.
    assert(toolbarItem(@"office.summary").view == target->summary);
    toolbar->setStatistics("延迟 12 ms · 60 帧/秒 · 18.5 Mbps", "视频：1920×1080\n码率：18.5 Mbps");
    assert([target->summary.stringValue isEqualToString:@"延迟 12 ms · 60 帧/秒 · 18.5 Mbps"]);
    assert([target->summary.toolTip isEqualToString:@"视频：1920×1080\n码率：18.5 Mbps"]);
    // The statistics button toggles a non-activating panel that never takes the
    // stream window's keyboard focus and joins the fullscreen Space.
    const size_t beforeStats = events.size();
    [target statistics:nil];
    assert(events.size() == beforeStats + 1 && events.back() == std::make_tuple(office::Action::Statistics,1,0));
    assert(target->statisticsButton.state == NSControlStateValueOn && target->panel);
    assert(![target->panel canBecomeKeyWindow] && ![target->panel canBecomeMainWindow]);
    assert(target->panel.collectionBehavior & NSWindowCollectionBehaviorFullScreenAuxiliary);
    assert(!target->panel.visible); // the stream window is hidden in this check
    assert([target->panelText.stringValue isEqualToString:@"视频：1920×1080\n码率：18.5 Mbps"]);
    NSMenuItem* statisticsOverflow = toolbarItem(@"office.statistics").menuFormRepresentation;
    [target validateMenuItem:statisticsOverflow];
    assert(statisticsOverflow.state == NSControlStateValueOn);
    [target statistics:nil];
    assert(events.back() == std::make_tuple(office::Action::Statistics,0,0));
    assert(target->statisticsButton.state == NSControlStateValueOff);
    toolbar->setStatisticsVisible(true); // restored after reconnect: no event
    assert(events.size() == beforeStats + 2 && target->statisticsButton.state == NSControlStateValueOn);
    [target windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:target->panel]];
    assert(events.back() == std::make_tuple(office::Action::Statistics,0,0) && target->statisticsButton.state == NSControlStateValueOff);
    toolbar->setStatistics("", "");
    assert([target->summary.stringValue isEqualToString:@"统计读取中"]);
    assert(window.childWindows.count == 0 && originalContent.subviews.count == 0);
    const size_t before = events.size();
    [target->resolution selectItemAtIndex:3]; [target resolutionChanged:target->resolution];
    assert(events.size()==before+1 && std::get<0>(events.back())==office::Action::InputPause && std::get<1>(events.back())==1);
    assert(target->resolution.indexOfSelectedItem==target->currentResolution);
    complete(NSAlertSecondButtonReturn);
    assert(events.size()==before+2 && std::get<0>(events.back())==office::Action::InputPause && std::get<1>(events.back())==0);
    [target->resolution selectItemAtIndex:3]; [target resolutionChanged:target->resolution];
    complete(NSAlertFirstButtonReturn);
    assert(events.back()==std::make_tuple(office::Action::Resolution,2560,1440));
    [target->resolution selectItemAtIndex:3]; [target resolutionChanged:target->resolution];
    const auto countBeforeTeardown = events.size();
    toolbar.reset();
    complete(NSAlertFirstButtonReturn);
    assert(events.size()==countBeforeTeardown && window.toolbar==nil && !window.visible);
    toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int x,int y){events.emplace_back(a,x,y);},false);
    target = (OfficeToolbarTarget*)window.toolbar.delegate;
    [target->resolution selectItemAtIndex:3]; [target resolutionChanged:target->resolution];
    [target disconnect:nil];
    const auto afterDisconnect = events.size();
    assert(std::get<0>(events.back())==office::Action::Disconnect);
    complete(NSAlertFirstButtonReturn);
    assert(events.size()==afterDisconnect);
    toolbar.reset();
    toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int,int){if(a==office::Action::InputPause) toolbar.reset();},false);
    target = (OfficeToolbarTarget*)window.toolbar.delegate;
    [target->resolution selectItemAtIndex:3]; [target resolutionChanged:target->resolution];
    assert(!pendingCompletion && !toolbar);
    [window close]; [window release];
    puts("PASS: hidden native toolbar, unchanged contentView, no child windows, cached DPI controls, popup/overflow check marks, fullscreen label and auto-hide options, statistics summary/panel, resolution cancel/confirm, disconnect/teardown callback safety; no visible UI");
} }
