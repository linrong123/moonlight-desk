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
// Stand-ins for SDL's window delegate: the wrapper must land on the delegate's
// actual class whatever its name, and leave unrelated classes alone.
static int fakeEnterCalls;
@interface FakeSdlListener : NSObject <NSWindowDelegate>
@end
@implementation FakeSdlListener
- (NSApplicationPresentationOptions)window:(NSWindow*)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options {
    (void)window; return options;
}
- (void)windowDidEnterFullScreen:(NSNotification*)notification { (void)notification; ++fakeEnterCalls; }
@end
@interface OtherSdlListener : FakeSdlListener
@end
@implementation OtherSdlListener
- (NSApplicationPresentationOptions)window:(NSWindow*)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)options {
    (void)window; return options;
}
@end
@interface EmptyListener : NSObject <NSWindowDelegate>
@end
@implementation EmptyListener
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
    using O = NSApplicationPresentationOptions;
    const O sdlDesktop = NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    const O autoHide = NSApplicationPresentationFullScreen | NSApplicationPresentationHideDock |
        NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideToolbar;
    // A delegate without the wrapped methods: nothing is added, a log line still says so.
    EmptyListener* empty = [EmptyListener new];
    window.delegate = empty;
    assert(officeWrapFullscreenListener(window).find("not installed: EmptyListener") != std::string::npos);
    assert(!class_getInstanceMethod(EmptyListener.class, @selector(windowDidBecomeKey:)));
    FakeSdlListener* listener = [FakeSdlListener new];
    window.delegate = listener;
    const SEL optionsSelector = @selector(window:willUseFullScreenPresentationOptions:);
    const IMP fakeOriginal = class_getMethodImplementation(FakeSdlListener.class, optionsSelector);
    const IMP otherOriginal = class_getMethodImplementation(OtherSdlListener.class, optionsSelector);
    std::vector<std::tuple<office::Action,int,int>> events;
    auto toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int x,int y){events.emplace_back(a,x,y);},true);
    auto target = (OfficeToolbarTarget*)window.toolbar.delegate;
    // The toolbar wrapped the delegate's actual class, only its implemented methods.
    const IMP fakeWrapped = class_getMethodImplementation(FakeSdlListener.class, optionsSelector);
    assert(fakeWrapped != fakeOriginal);
    assert(class_getMethodImplementation(OtherSdlListener.class, optionsSelector) == otherOriginal);
    assert(!class_getInstanceMethod(FakeSdlListener.class, @selector(windowDidBecomeKey:)));
    assert([listener window:window willUseFullScreenPresentationOptions:sdlDesktop] == autoHide);
    NSWindow* unregistered = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,10,10)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    unregistered.releasedWhenClosed = NO;
    assert([listener window:unregistered willUseFullScreenPresentationOptions:sdlDesktop] == sdlDesktop);
    [listener windowDidEnterFullScreen:[NSNotification notificationWithName:NSWindowDidEnterFullScreenNotification object:window]];
    assert(fakeEnterCalls == 1); // original runs first; not fullscreen, so the menu bar is untouched
    const std::string logged = officeWrapFullscreenListener(window);
    assert(logged.find("wrapped FakeSdlListener: window:willUseFullScreenPresentationOptions: windowDidEnterFullScreen:") != std::string::npos);
    assert(class_getMethodImplementation(FakeSdlListener.class, optionsSelector) == fakeWrapped); // wrapped once per class
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
    auto toolbarItem = [&](NSString* identifier) -> NSToolbarItem* {
        for (NSToolbarItem* item in window.toolbar.items) if ([item.itemIdentifier isEqualToString:identifier]) return item;
        return nil;
    };
    // First line of a (possibly two-line, attributed) menu title.
    auto label = [](NSMenuItem* item) -> NSString* {
        if (item.separatorItem) return @"-";
        NSString* text = item.attributedTitle.length ? item.attributedTitle.string : item.title;
        return [text componentsSeparatedByString:@"\n"].firstObject;
    };
    auto labels = [&](NSMenu* menu) -> NSArray* {
        NSMutableArray* result = [NSMutableArray array];
        for (NSMenuItem* item in menu.itemArray) [result addObject:label(item)];
        return result;
    };
    // Indices checked after validation, as AppKit does before showing a menu.
    auto checked = [&](NSMenu* menu) -> std::vector<NSInteger> {
        std::vector<NSInteger> result;
        for (NSInteger i = 0; i < menu.numberOfItems; ++i) {
            NSMenuItem* item = [menu itemAtIndex:i];
            if (item.separatorItem || !item.action) continue;
            [target validateMenuItem:item];
            if (item.state == NSControlStateValueOn) result.push_back(i);
        }
        return result;
    };
    auto redText = [](NSAttributedString* text) -> bool {
        NSColor* color = [text attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nullptr];
        return [color isEqual:NSColor.systemRedColor];
    };
    // Toolbar: info capsule on the left, centered icon group, red disconnect on the far right.
    NSArray* center = @[@"office.display", @"office.input", @"office.fullscreen", @"office.devices"];
    NSMutableArray* expectedIds = [NSMutableArray arrayWithArray:@[@"office.info"]];
    if (@available(macOS 11.0, *)) {} else { [expectedIds addObject:@"office.status"]; }
    [expectedIds addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [expectedIds addObjectsFromArray:center];
    [expectedIds addObjectsFromArray:@[NSToolbarFlexibleSpaceItemIdentifier, @"office.disconnect"]];
    assert([[window.toolbar.items valueForKey:@"itemIdentifier"] isEqualToArray:expectedIds]);
    if (@available(macOS 13.0, *)) {
        assert([window.toolbar.centeredItemIdentifiers isEqualToSet:[NSSet setWithArray:center]]);
    }
    assert(!toolbarItem(@"office.control") && !toolbarItem(@"office.device") && !toolbarItem(@"office.summary"));
    // Info capsule: one button (dot, bold name, gap, grey summary, info symbol) that toggles the panel.
    NSButton* info = target->infoButton;
    assert(toolbarItem(@"office.info").view == info && info.target == target && info.action == @selector(statistics:));
    assert([info.attributedTitle.string isEqualToString:@"● 远程电脑    统计读取中"]);
    assert([info.toolTip isEqualToString:@"连接后显示延迟、帧率和码率"]);
    if (@available(macOS 11.0, *)) assert(info.image && info.imagePosition == NSImageTrailing);
    NSFont* nameFont = [info.attributedTitle attribute:NSFontAttributeName atIndex:2 effectiveRange:nullptr];
    assert(nameFont.fontDescriptor.symbolicTraits & NSFontDescriptorTraitBold);
    NSAttributedString* infoTitle = info.attributedTitle;
    assert([[infoTitle attribute:NSForegroundColorAttributeName atIndex:infoTitle.length - 1 effectiveRange:nullptr]
        isEqual:NSColor.secondaryLabelColor]);
    const CGFloat infoWidth = target->infoWidth.constant;
    assert(target->infoWidth.active && infoWidth > 0);
    toolbar->setDeviceName("办公电脑");
    assert([target->deviceName isEqualToString:@"办公电脑"] && [info.attributedTitle.string isEqualToString:@"● 办公电脑    统计读取中"]);
    toolbar->setDeviceName("一个非常非常非常非常非常非常非常非常非常非常非常长的远程电脑名称");
    assert([info.attributedTitle.string containsString:@"…    统计读取中"]); // the name is cut, never the summary
    assert(target->infoWidth.constant <= infoWidth + officeDeviceNameWidth);
    toolbar->setDeviceName("");
    assert([target->deviceName isEqualToString:@"远程电脑"] && target->infoWidth.constant == infoWidth);
    assert([label(toolbarItem(@"office.info").menuFormRepresentation) isEqualToString:@"连接信息…"]);
    // Center icons: 显示 and 鼠标与键盘 open their menus on click; their overflow
    // entries come from NSMenuToolbarItem itself (label + the same menu).
    NSMenu* const iconMenus[] = {target->displayMenu, target->inputMenu};
    NSString* const iconTitles[] = {@"显示", @"鼠标与键盘"};
    for (int i = 0; i < 2; ++i) {
        NSToolbarItem* item = toolbarItem(center[i]);
        assert([item isKindOfClass:NSMenuToolbarItem.class] && ((NSMenuToolbarItem*)item).menu == iconMenus[i]);
        assert(((NSMenuToolbarItem*)item).showsIndicator && !item.action && item.toolTip.length);
        assert([item.label isEqualToString:iconTitles[i]]);
        if (@available(macOS 11.0, *)) assert(item.image);
        NSMenuItem* overflow = item.menuFormRepresentation;
        fprintf(stderr, "overflow %s: title=%s submenu=%s same=%d\n", iconTitles[i].UTF8String,
            overflow.title.UTF8String ?: "(nil)", overflow.submenu ? "yes" : "no", overflow.submenu == iconMenus[i]);
        if (overflow) {
            assert([overflow.title isEqualToString:iconTitles[i]]);
            if (overflow.submenu) assert([labels(overflow.submenu) isEqualToArray:labels(iconMenus[i])]);
        }
    }
    // Fullscreen icon: toggles directly; icon, tooltip and overflow title follow the state.
    NSToolbarItem* fullscreenIcon = toolbarItem(@"office.fullscreen");
    assert(fullscreenIcon.target == target && fullscreenIcon.action == @selector(fullscreen:));
    assert([fullscreenIcon.toolTip isEqualToString:@"进入全屏（⌃⌥⇧X）"]);
    if (@available(macOS 11.0, *)) assert([fullscreenIcon.image.accessibilityDescription isEqualToString:@"进入全屏"]);
    NSMenuItem* fullscreenItem = fullscreenIcon.menuFormRepresentation;
    [target validateMenuItem:fullscreenItem];
    assert([label(fullscreenItem) hasPrefix:@"进入全屏"] && [fullscreenItem.attributedTitle.string containsString:@"⌃⌥⇧X"]);
    assert(fullscreenItem.keyEquivalent.length == 0); // the SDL shortcut already toggles it
    target->fullscreenShown = YES;
    [target decorateFullscreenItem];
    assert([fullscreenIcon.toolTip isEqualToString:@"退出全屏（⌃⌥⇧X）"] && [label(fullscreenItem) hasPrefix:@"退出全屏"]);
    if (@available(macOS 11.0, *)) assert([fullscreenIcon.image.accessibilityDescription isEqualToString:@"退出全屏"]);
    [target poll]; // the hidden window is not fullscreen: polling restores the state
    assert([fullscreenIcon.toolTip isEqualToString:@"进入全屏（⌃⌥⇧X）"]);
    if (@available(macOS 11.0, *)) assert([fullscreenIcon.image.accessibilityDescription isEqualToString:@"进入全屏"]);
    assert([target validateToolbarItem:fullscreenIcon]);
    // Devices icon only with a device manager.
    NSToolbarItem* devicesIcon = toolbarItem(@"office.devices");
    assert(devicesIcon.target == target && devicesIcon.action == @selector(devices:));
    assert([label(devicesIcon.menuFormRepresentation) isEqualToString:@"设备列表…"]);
    [target devices:devicesIcon];
    assert(events.back() == std::make_tuple(office::Action::Devices,0,0));
    // Red disconnect at the far right, after a flexible space.
    assert(toolbarItem(@"office.disconnect").view == target->disconnectButton && redText(target->disconnectButton.attributedTitle));
    assert(redText(toolbarItem(@"office.disconnect").menuFormRepresentation.attributedTitle));
    // 显示 › 分辨率: only the current resolution is checked.
    NSMenu* display = target->displayMenu;
    assert([labels(display) isEqualToArray:(@[@"分辨率", @"画面缩放"])]);
    NSMenu* resolutionMenu = [display itemAtIndex:0].submenu;
    assert(resolutionMenu.numberOfItems == 6 && [label([resolutionMenu itemAtIndex:3]) isEqualToString:@"2560 × 1440"]);
    assert(checked(resolutionMenu) == std::vector<NSInteger>{1});
    // 显示 › 画面缩放: filled from the host's choices when opened, one check mark.
    NSMenu* scaleMenu = [display itemAtIndex:1].submenu;
    assert(scaleMenu.delegate == target);
    [target menuNeedsUpdate:scaleMenu];
    assert([labels(scaleMenu) isEqualToArray:@[@"读取中…"]] && ![scaleMenu itemAtIndex:0].enabled);
    toolbar->setDisplayScales({100,125,150,200},150,false);
    NSToolbarItem* displayItem = toolbarItem(@"office.display");
    toolbar->setDisplayScales({100,125,150,200},150,false);
    assert(toolbarItem(@"office.display") == displayItem);
    [target menuNeedsUpdate:scaleMenu];
    assert([labels(scaleMenu) isEqualToArray:(@[@"100%", @"125%", @"150%", @"200%"])]);
    assert(checked(scaleMenu) == std::vector<NSInteger>{2});
    for (NSMenuItem* item in scaleMenu.itemArray) assert([target validateMenuItem:item]);
    [target scaleChanged:[scaleMenu itemAtIndex:3]];
    assert(events.back() == std::make_tuple(office::Action::DisplayScale,200,0));
    toolbar->setDisplayScales({100,125,150,200},200,true);
    [target menuNeedsUpdate:scaleMenu];
    assert(checked(scaleMenu) == std::vector<NSInteger>{3} && ![target validateMenuItem:[scaleMenu itemAtIndex:0]]);
    const size_t beforePending = events.size();
    [target scaleChanged:[scaleMenu itemAtIndex:0]];
    assert(events.size() == beforePending);
    toolbar->setDisplayScales({},0,false);
    [target menuNeedsUpdate:scaleMenu];
    assert([labels(scaleMenu) isEqualToArray:@[@"不可用"]]);
    // 鼠标与键盘: three single-choice modes with a grey description, then 暂停输入
    // and 同步剪贴板.
    NSMenu* input = target->inputMenu;
    assert([labels(input) isEqualToArray:(@[@"本机鼠标（推荐办公）", @"远端鼠标", @"游戏模式（锁定鼠标）", @"-", @"暂停输入", @"同步剪贴板"])]);
    assert([[input itemAtIndex:0].attributedTitle.string hasSuffix:@"\n显示本机光标，响应最快，适合日常办公"]);
    assert([[input itemAtIndex:1].attributedTitle.string hasSuffix:@"\n显示被控端的光标样式"]);
    assert([[input itemAtIndex:2].attributedTitle.string hasSuffix:@"\n鼠标锁定在画面内，适合游戏或 3D 软件；按 ⌃⌥⇧Z 释放"]);
    NSAttributedString* firstMode = [input itemAtIndex:0].attributedTitle;
    NSColor* noteColor = [firstMode attribute:NSForegroundColorAttributeName atIndex:firstMode.length - 1 effectiveRange:nullptr];
    assert([noteColor isEqual:NSColor.secondaryLabelColor]);
    assert(checked(input) == std::vector<NSInteger>{0});
    [target mouseChanged:[input itemAtIndex:2]];
    assert(events.back() == std::make_tuple(office::Action::Mouse,2,0));
    assert(checked(input) == std::vector<NSInteger>{2});
    [target mouseChanged:[input itemAtIndex:0]];
    assert(events.back() == std::make_tuple(office::Action::Mouse,0,0) && checked(input) == std::vector<NSInteger>{0});
    // 暂停输入 toggles and is checked while paused.
    [target inputPause:[input itemAtIndex:4]];
    assert(events.back() == std::make_tuple(office::Action::InputPause,1,0));
    assert(checked(input) == (std::vector<NSInteger>{0, 4}));
    [target inputPause:[input itemAtIndex:4]];
    assert(events.back() == std::make_tuple(office::Action::InputPause,0,0) && checked(input) == std::vector<NSInteger>{0});
    // 同步剪贴板: greyed out with a hint until the host reports OfficeClipboard;
    // checked per device; a host refusal keeps the choice but explains it.
    NSMenuItem* clipboardItem = [input itemAtIndex:5];
    assert(![target validateMenuItem:clipboardItem] && checked(input) == std::vector<NSInteger>{0});
    assert([clipboardItem.toolTip isEqualToString:@"被控端不支持剪贴板同步，请更新被控端"]);
    const size_t beforeClipboard = events.size();
    [target clipboardSync:clipboardItem];
    assert(events.size() == beforeClipboard);
    toolbar->setClipboard(true,true,false);
    assert([target validateMenuItem:clipboardItem] && checked(input) == (std::vector<NSInteger>{0, 5}));
    assert([clipboardItem.toolTip isEqualToString:@"切换窗口时自动同步文本剪贴板（最多 1 MB），按设备记住"]);
    [target clipboardSync:clipboardItem];
    assert(events.back() == std::make_tuple(office::Action::Clipboard,0,0) && checked(input) == std::vector<NSInteger>{0});
    [target clipboardSync:clipboardItem];
    assert(events.back() == std::make_tuple(office::Action::Clipboard,1,0) && checked(input) == (std::vector<NSInteger>{0, 5}));
    toolbar->setClipboard(true,false,false); // remembered off for this device
    assert([target validateMenuItem:clipboardItem] && checked(input) == std::vector<NSInteger>{0});
    toolbar->setClipboard(true,true,true);
    [target validateMenuItem:clipboardItem];
    assert([clipboardItem.toolTip isEqualToString:@"被控端拒绝了剪贴板同步（可能已在被控端关闭）；重新连接后再试"]);
    toolbar->setClipboard(true,true,false);
    const size_t beforeSync = events.size();
    toolbar->setInputPaused(true); // restored after reconnect: no event
    assert(events.size() == beforeSync && checked(input) == (std::vector<NSInteger>{0, 4, 5}));
    // Already paused by the user: the resolution sheet neither pauses nor resumes.
    [target resolutionChanged:[resolutionMenu itemAtIndex:3]];
    assert(events.size() == beforeSync && pendingCompletion);
    assert(![target validateMenuItem:[resolutionMenu itemAtIndex:0]] && ![target validateMenuItem:[input itemAtIndex:4]]);
    assert(![target validateMenuItem:clipboardItem]);
    [target clipboardSync:clipboardItem];
    assert(events.size() == beforeSync); // no toggle behind the confirmation sheet
    complete(NSAlertFirstButtonReturn);
    assert(events.size() == beforeSync + 1 && events.back() == std::make_tuple(office::Action::Resolution,2560,1440));
    toolbar->setInputPaused(false);
    // Spaces fullscreen: SDL's hidden menu bar becomes auto-hide with the toolbar;
    // only valid AppKit combinations are produced.
    assert(officeFullscreenOptions(sdlDesktop) == autoHide);
    const O proposed = NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock;
    assert(officeFullscreenOptions(proposed) == (proposed | NSApplicationPresentationAutoHideToolbar));
    assert(officeFullscreenOptions(NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar) ==
        (NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationAutoHideDock |
         NSApplicationPresentationAutoHideToolbar));
    assert(officeFullscreenOptions(NSApplicationPresentationFullScreen) == NSApplicationPresentationFullScreen);
    const O windowed = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    assert(officeFullscreenOptions(windowed) == windowed);
    // Resident statistics summary in the capsule; details are the tooltip; the
    // dot turns green with statistics; the capsule keeps its width.
    toolbar->setStatistics("延迟 12 ms · 60 帧/秒 · 18.5 Mbps", "视频：1920×1080\n码率：18.5 Mbps");
    assert([info.attributedTitle.string isEqualToString:@"● 远程电脑    延迟 12 ms · 60 帧/秒 · 18.5 Mbps"]);
    assert([info.toolTip isEqualToString:@"视频：1920×1080\n码率：18.5 Mbps"]);
    assert([[info.attributedTitle attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nullptr]
        isEqual:NSColor.systemGreenColor]);
    assert(target->infoWidth.constant == infoWidth);
    // 连接信息… toggles a non-activating panel that never takes the stream
    // window's keyboard focus and joins the fullscreen Space.
    NSMenuItem* statisticsItem = toolbarItem(@"office.info").menuFormRepresentation;
    const size_t beforeStats = events.size();
    [info sendAction:info.action to:info.target]; // a click anywhere on the capsule (hidden window: no performClick)
    assert(events.size() == beforeStats + 1 && events.back() == std::make_tuple(office::Action::Statistics,1,0));
    assert(target->panel && [target->panel.title isEqualToString:@"连接信息"]);
    [target validateMenuItem:statisticsItem];
    assert(statisticsItem.state == NSControlStateValueOn);
    assert(![target->panel canBecomeKeyWindow] && ![target->panel canBecomeMainWindow]);
    assert(target->panel.collectionBehavior & NSWindowCollectionBehaviorFullScreenAuxiliary);
    assert(!target->panel.visible); // the stream window is hidden in this check
    assert([target->panelText.stringValue isEqualToString:@"视频：1920×1080\n码率：18.5 Mbps"]);
    [target statistics:statisticsItem];
    assert(events.back() == std::make_tuple(office::Action::Statistics,0,0));
    [target validateMenuItem:statisticsItem];
    assert(statisticsItem.state == NSControlStateValueOff);
    toolbar->setStatisticsVisible(true); // restored after reconnect: no event
    [target validateMenuItem:statisticsItem];
    assert(events.size() == beforeStats + 2 && statisticsItem.state == NSControlStateValueOn);
    [target windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:target->panel]];
    [target validateMenuItem:statisticsItem];
    assert(events.back() == std::make_tuple(office::Action::Statistics,0,0) && statisticsItem.state == NSControlStateValueOff);
    toolbar->setStatistics("", "");
    assert([info.attributedTitle.string isEqualToString:@"● 远程电脑    统计读取中"]);
    assert([[info.attributedTitle attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nullptr]
        isEqual:NSColor.tertiaryLabelColor]);
    assert(window.childWindows.count == 0 && originalContent.subviews.count == 0);
    // Not paused: the resolution sheet pauses input and resumes it on close.
    const size_t before = events.size();
    [target resolutionChanged:[resolutionMenu itemAtIndex:1]]; // current: no sheet
    assert(events.size() == before && !pendingCompletion);
    [target resolutionChanged:[resolutionMenu itemAtIndex:3]];
    assert(events.size()==before+1 && events.back()==std::make_tuple(office::Action::InputPause,1,0));
    assert(checked(resolutionMenu) == std::vector<NSInteger>{1}); // a proposal is never shown as current
    complete(NSAlertSecondButtonReturn);
    assert(events.size()==before+2 && events.back()==std::make_tuple(office::Action::InputPause,0,0));
    [target resolutionChanged:[resolutionMenu itemAtIndex:3]];
    complete(NSAlertFirstButtonReturn);
    assert(events.back()==std::make_tuple(office::Action::Resolution,2560,1440));
    [target resolutionChanged:[resolutionMenu itemAtIndex:3]];
    const auto countBeforeTeardown = events.size();
    toolbar.reset();
    complete(NSAlertFirstButtonReturn);
    assert(events.size()==countBeforeTeardown && window.toolbar==nil && !window.visible);
    toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int x,int y){events.emplace_back(a,x,y);},false);
    target = (OfficeToolbarTarget*)window.toolbar.delegate;
    assert(!toolbarItem(@"office.devices")); // no device manager in this process
    if (@available(macOS 13.0, *)) {
        assert(![window.toolbar.centeredItemIdentifiers containsObject:@"office.devices"]);
    }
    [target resolutionChanged:[[target->displayMenu itemAtIndex:0].submenu itemAtIndex:3]];
    [target disconnect:nil];
    const auto afterDisconnect = events.size();
    assert(std::get<0>(events.back())==office::Action::Disconnect);
    complete(NSAlertFirstButtonReturn);
    assert(events.size()==afterDisconnect);
    toolbar.reset();
    toolbar = std::make_unique<office::MacToolbar>(window,1920,1080,office::MouseMode::Local,
        [&](office::Action a,int,int){if(a==office::Action::InputPause) toolbar.reset();},false);
    target = (OfficeToolbarTarget*)window.toolbar.delegate;
    [target resolutionChanged:[[target->displayMenu itemAtIndex:0].submenu itemAtIndex:3]];
    assert(!pendingCompletion && !toolbar);
    assert(class_getMethodImplementation(FakeSdlListener.class, optionsSelector) == fakeWrapped);
    window.delegate = nil;
    [window close]; [window release];
    [unregistered close]; [unregistered release];
    [listener release]; [empty release];
    puts("PASS: fullscreen wrapper on the delegate's actual class (once, implemented methods only), hidden native toolbar, unchanged contentView, no child windows, toolbar layout (info capsule left, centered icons display/input/fullscreen/devices, red disconnect far right), info capsule title/width/click, icon menus and overflow forms with single check marks (resolution, DPI, mouse), input pause, clipboard toggle (unsupported/denied hints), fullscreen icon/tooltip and auto-hide options, connection info panel, resolution cancel/confirm (also while paused), disconnect/teardown callback safety; no visible UI");
} }
