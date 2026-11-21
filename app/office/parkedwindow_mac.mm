#import <AppKit/AppKit.h>
#include <SDL_syswm.h>
#include <QCoreApplication>
#include <QMetaObject>
#include <QTimer>
#include <cstdint>
#include <string>
#include "parkedwindow.h"
#include "parkedwindowlogic.h"
#include "toolbar.h"

// Manual reference counting, like toolbar_mac.mm. Everything here runs on the
// main thread, between two sessions' SDL loops. No SDL_PumpEvents: Qt's event
// loop dispatches the window's NSEvents, the SDL window delegate queues the
// resulting SDL window/mouse events, and a timer takes only those types back
// out. User events (frame, barrier, connection lost) stay queued for the next
// session; officeNextSession flushes the old session's ones.

static_assert(static_cast<std::uint32_t>(SDL_QUIT) == office::kParkedQuitEvent, "SDL_QUIT");
static_assert(static_cast<std::uint32_t>(SDL_WINDOWEVENT) == office::kParkedWindowEvent, "SDL_WINDOWEVENT");
static_assert(SDL_WINDOWEVENT_CLOSE == office::kParkedWindowClose, "SDL_WINDOWEVENT_CLOSE");
static_assert(static_cast<std::uint32_t>(SDL_KEYDOWN) == office::kParkedInputRanges[0][0], "keyboard range");
static_assert(static_cast<std::uint32_t>(SDL_MOUSEMOTION) == office::kParkedInputRanges[1][0], "mouse range");
static_assert(static_cast<std::uint32_t>(SDL_FINGERDOWN) == office::kParkedInputRanges[2][0], "touch range");
static_assert(static_cast<std::uint32_t>(SDL_USEREVENT) == office::kParkedUserEvent, "SDL_USEREVENT");

namespace {
// Shared by the overlay, the toolbar handler and the parked window. The first
// request wins; the session handler runs later from the Qt event loop so that
// no toolbar or overlay method is on the stack when the window is released.
struct CancelLink {
    std::function<void()> handler;
    std::function<void()> requestedUi;
    bool requested = false;
};

void requestCancel(const std::shared_ptr<CancelLink>& link) {
    if (link->requested) return;
    link->requested = true;
    if (link->requestedUi) link->requestedUi();
    auto handler = link->handler;
    if (!handler) return;
    QMetaObject::invokeMethod(QCoreApplication::instance(), [handler] { handler(); }, Qt::QueuedConnection);
}
}

@interface OfficeReconnectOverlay : NSView {
@public
    std::function<void()> onCancel;
    NSProgressIndicator* spinner;
    NSTextField* label;
    NSButton* button;
}
@end

@implementation OfficeReconnectOverlay
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.wantsLayer = YES;
    self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.88].CGColor;
    if (@available(macOS 10.14, *)) self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.displayedWhenStopped = NO;
    [spinner startAnimation:nil];
    label = [[NSTextField labelWithString:@""] retain];
    label.textColor = NSColor.whiteColor;
    label.font = [NSFont systemFontOfSize:17];
    label.alignment = NSTextAlignmentCenter;
    button = [[NSButton buttonWithTitle:@"断开" target:self action:@selector(cancelRecovery:)] retain];
    button.toolTip = @"停止重连并回到工作台";
    NSStackView* stack = [NSStackView stackViewWithViews:@[spinner, label, button]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
    ]];
    return self;
}
- (void)dealloc {
    [spinner release];
    [label release];
    [button release];
    [super dealloc];
}
- (void)setMessage:(NSString*)message cancelling:(BOOL)cancelling {
    label.stringValue = message;
    button.enabled = !cancelling;
}
- (void)cancelRecovery:(id)sender {
    (void)sender;
    if (onCancel) onCancel();
}
// Escape and the standard cancel command act like 断开; other keys and all
// pointer input stay local so nothing reaches the SDL window meanwhile.
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { (void)event; return YES; }
- (void)keyDown:(NSEvent*)event { if (event.keyCode == 53) [self cancelRecovery:nil]; }
- (void)keyUp:(NSEvent*)event { (void)event; }
- (void)flagsChanged:(NSEvent*)event { (void)event; }
- (void)cancelOperation:(id)sender { [self cancelRecovery:sender]; }
- (void)mouseDown:(NSEvent*)event { (void)event; }
- (void)mouseUp:(NSEvent*)event { (void)event; }
- (void)mouseDragged:(NSEvent*)event { (void)event; }
- (void)mouseMoved:(NSEvent*)event { (void)event; }
- (void)rightMouseDown:(NSEvent*)event { (void)event; }
- (void)rightMouseUp:(NSEvent*)event { (void)event; }
- (void)rightMouseDragged:(NSEvent*)event { (void)event; }
- (void)otherMouseDown:(NSEvent*)event { (void)event; }
- (void)otherMouseUp:(NSEvent*)event { (void)event; }
- (void)otherMouseDragged:(NSEvent*)event { (void)event; }
- (void)scrollWheel:(NSEvent*)event { (void)event; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.arrowCursor]; }
@end

namespace office {
namespace {
class MacParkedWindow final : public ParkedWindow {
public:
    MacParkedWindow(SDL_Window* window, NSWindow* parent, bool reconfigure, int attempt)
        : sdlWindow(window), nativeWindow(parent), windowId(SDL_GetWindowID(window)),
          resizePending(reconfigure), reconfiguring(reconfigure), attempts(attempt),
          link(std::make_shared<CancelLink>()) {
        std::weak_ptr<CancelLink> weak = link;
        link->requestedUi = [this] { refresh(); };
        overlay = [[OfficeReconnectOverlay alloc] initWithFrame:parent.contentView.bounds];
        overlay->onCancel = [weak] { if (auto shared = weak.lock()) requestCancel(shared); };
        previousResponder = [parent.firstResponder retain];
        [parent.contentView addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
        [parent makeFirstResponder:overlay];
        [parent invalidateCursorRectsForView:overlay];
        refresh();
        QObject::connect(&timer, &QTimer::timeout, [this] { pump(); });
        timer.start(50);
    }

    ~MacParkedWindow() override {
        timer.stop();
        if (!sdlWindow) return;
        link->handler = nullptr;
        toolbar.reset();
        removeOverlay();
        SDL_DestroyWindow(sdlWindow);
        // The video reference the parked session kept (session.cpp cleanup).
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
    }

    SDL_Window* window() const override { return sdlWindow; }

    void setToolbar(std::unique_ptr<Toolbar> value) override {
        toolbar = std::move(value);
        if (!toolbar) return;
        std::weak_ptr<CancelLink> weak = link;
        toolbar->setActionHandler([weak](Action action, int, int) {
            if (action != Action::Disconnect) return;
            if (auto shared = weak.lock()) requestCancel(shared);
        });
        toolbar->setStatisticsVisible(false);
        toolbar->setStatistics("正在重连", "");
        refresh();
    }

    void setCancelHandler(std::function<void()> handler) override { link->handler = std::move(handler); }

    void setRecovery(bool reconfigure, int attempt) override {
        reconfiguring = reconfigure;
        attempts = attempt;
        refresh();
    }

    void setApprovalWaiting(bool waiting) override {
        approvalWaiting = waiting;
        refresh();
    }

    void focus() override {
        if (!sdlWindow) return;
        if (SDL_GetWindowFlags(sdlWindow) & SDL_WINDOW_MINIMIZED) SDL_RestoreWindow(sdlWindow);
        SDL_RaiseWindow(sdlWindow);
        if (overlay) [nativeWindow makeFirstResponder:overlay];
    }

    Adopted adopt(std::unique_ptr<Toolbar>& out) override {
        Adopted adopted;
        if (!sdlWindow) return adopted;
        timer.stop();
        link->handler = nullptr;
        link->requested = true;
        removeOverlay();
        const Uint32 flags = SDL_GetWindowFlags(sdlWindow);
        adopted.window = sdlWindow;
        adopted.reconfigure = resizePending;
        adopted.fullscreen = (flags & SDL_WINDOW_FULLSCREEN) || (nativeWindow.styleMask & NSWindowStyleMaskFullScreen);
        adopted.maximized = (flags & SDL_WINDOW_MAXIMIZED) || nativeWindow.isZoomed;
        if (toolbar) toolbar->setActionHandler({});
        out = std::move(toolbar);
        sdlWindow = nullptr;
        nativeWindow = nil;
        return adopted;
    }

private:
    void refresh() {
        if (!overlay) return;
        const std::string text = link->requested ? std::string("正在断开…")
            : recoveryOverlayText(reconfiguring, attempts, approvalWaiting);
        NSString* message = [NSString stringWithUTF8String:text.c_str()];
        if (!message) message = @"";
        [overlay setMessage:message cancelling:link->requested ? YES : NO];
        if (toolbar) toolbar->setStatus(text.c_str());
    }

    void pump() {
        if (!sdlWindow) return;
        SDL_Event events[16];
        const auto take = [&](Uint32 first, Uint32 last) {
            int count;
            while ((count = SDL_PeepEvents(events, 16, SDL_GETEVENT, first, last)) > 0) {
                for (int i = 0; i < count; ++i) {
                    const SDL_Event& event = events[i];
                    const bool window = event.type == SDL_WINDOWEVENT;
                    if (classifyParkedEvent(event.type, window ? event.window.event : 0,
                            window ? event.window.windowID : 0, windowId) == ParkedEvent::Cancel)
                        requestCancel(link);
                }
            }
        };
        take(SDL_QUIT, SDL_QUIT);
        take(SDL_WINDOWEVENT, SDL_WINDOWEVENT);
        for (const auto& range : kParkedInputRanges) take(range[0], range[1]);
    }

    void removeOverlay() {
        if (!overlay) return;
        const BOOL focused = nativeWindow.firstResponder == overlay;
        overlay->onCancel = nullptr;
        [overlay removeFromSuperview];
        [overlay release];
        overlay = nil;
        if (focused) {
            NSResponder* next = previousResponder;
            if (![next isKindOfClass:NSView.class] || ((NSView*)next).window != nativeWindow)
                next = nativeWindow.contentView;
            [nativeWindow makeFirstResponder:next];
        }
        [previousResponder release];
        previousResponder = nil;
    }

    SDL_Window* sdlWindow;
    NSWindow* nativeWindow;  // owned by SDL
    Uint32 windowId;
    bool resizePending;
    bool reconfiguring;
    int attempts;
    bool approvalWaiting = false;
    std::shared_ptr<CancelLink> link;
    std::unique_ptr<Toolbar> toolbar;
    OfficeReconnectOverlay* overlay = nil;
    NSResponder* previousResponder = nil;
    QTimer timer;
};
}

bool parkingSupported() { return true; }

std::unique_ptr<ParkedWindow> parkWindow(SDL_Window* window, bool reconfigure, int attempt) {
    if (!window) return {};
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA || !info.info.cocoa.window)
        return {};
    return std::make_unique<MacParkedWindow>(window, info.info.cocoa.window, reconfigure, attempt);
}
}
