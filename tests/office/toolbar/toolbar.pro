QT += core gui quick network
CONFIG += c++17
TEMPLATE = app
TARGET = OfficeToolbarPreview
INCLUDEPATH += ../../../app ../../../libs/mac/include ../../../libs/mac/include/SDL2
LIBS += -L$$PWD/../../../libs/mac/lib -lSDL2 -framework AppKit
SOURCES += preview.cpp ../../../app/office/toolbar_mac.mm
