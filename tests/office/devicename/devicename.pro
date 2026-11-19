QT = core
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = office-devicename-test
INCLUDEPATH += ../../../app
SOURCES += devicename_test.cpp ../../../app/office/devicename.cpp
macx: LIBS += -framework SystemConfiguration -framework CoreFoundation
