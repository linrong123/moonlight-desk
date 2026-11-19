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
    puts("PASS: hidden native toolbar, unchanged contentView, no child windows, cached DPI controls, resolution cancel/confirm, disconnect/teardown callback safety; no visible UI");
} }
