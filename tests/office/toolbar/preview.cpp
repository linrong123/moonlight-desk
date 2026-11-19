#include "office/toolbar.h"
#include <QGuiApplication>
#include <QTimer>
#include <cstdio>

// Local UI harness using the production native toolbar and SDL event loop.
// It deliberately has no connection, pairing identity or remote input sender.
static int runPreview() {
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_VIDEO) != 0) return 1;
    auto window = SDL_CreateWindow("Office 工具栏本地验证 · 未连接任何电脑",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 1100, 680,
        SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (!window) return 2;
    bool running = true;
    std::unique_ptr<office::Toolbar> toolbar;
    toolbar = office::createToolbar(window, 1920, 1080, office::MouseMode::Local,
        [&](office::Action action, int first, int second) {
            std::printf("action=%d value=%d,%d\n", int(action), first, second);
            std::fflush(stdout);
            if (action == office::Action::Disconnect) running = false;
            else if (action == office::Action::Fullscreen)
                SDL_SetWindowFullscreen(window, SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
            else toolbar->setStatus("本地操作已收到；此验证窗口不连接远程电脑");
        });
    if (!toolbar) return 3;
    toolbar->setStatus("本地 UI 验证：检查菜单、应用、全屏及断开；不代表远端设置生效");
    while (running) {
        SDL_Event event;
        if (SDL_WaitEventTimeout(&event, 50) && event.type == SDL_QUIT) running = false;
    }
    toolbar.reset();
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}

int main(int argc, char** argv) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName("OfficeToolbarPreview");
    // Match Session::exec(): enter SDL only after Qt/AppKit have initialized.
    QTimer::singleShot(0, [&app] { app.exit(runPreview()); });
    return app.exec();
}
