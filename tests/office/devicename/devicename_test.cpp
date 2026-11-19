#include "office/devicename.h"
#include <QCoreApplication>
#include <cstdio>
#include <cstdlib>

static int checks;
static void require(bool value) { ++checks; if (!value) { std::fprintf(stderr,"FAIL check %d\n",checks); std::abort(); } }
static QByteArray clean(const QString& input) { return office::sanitizePairingDeviceName(input); }
static bool validUtf8(const QByteArray& bytes) { return QString::fromUtf8(bytes).toUtf8()==bytes && !bytes.contains(QByteArray("\xef\xbf\xbd")); }

int main(int argc,char** argv) {
    QCoreApplication app(argc,argv);
    require(clean(QStringLiteral("Alice's MacBook Pro"))=="Alice's MacBook Pro");
    require(clean(QStringLiteral("  会议室 Mac\t "))==QStringLiteral("会议室 Mac").toUtf8());
    require(clean(QStringLiteral("Mac\x01\nBook\x7f"))=="MacBook");
    require(clean(QString::fromUtf8("Mac\xc2\x85Book"))=="MacBook");                    // C1 NEL
    require(clean(QString::fromUtf8("evil\xe2\x80\xaetxt.app"))=="eviltxt.app");       // RLO bidi override
    require(clean(QString::fromUtf8("a\xe2\x80\x8b" "b\xe2\x80\xa8" "c"))=="abc");       // ZWSP, line separator
    QString surrogate=QStringLiteral("Mac"); surrogate+=QChar(0xD800); surrogate+=QStringLiteral("Book");
    const QByteArray unpaired=clean(surrogate); require(unpaired.startsWith("Mac") && unpaired.endsWith("Book") && QString::fromUtf8(unpaired).toUtf8()==unpaired);
    for (const auto& empty : {QString(), QStringLiteral("   "), QStringLiteral("\r\n\t"), QString::fromUtf8("\xe2\x80\xae\xe2\x80\x8b")})
        require(clean(empty)=="Moonlight Desk");
    const QString exact(64,QLatin1Char('m')); require(clean(exact)==exact.toUtf8());
    require(clean(exact+QStringLiteral("x"))==exact.toUtf8());
    require(clean(QString(63,QLatin1Char('a'))+QStringLiteral(" b"))==QByteArray(63,'a'));
    const QByteArray chinese=clean(QString(30,QChar(0x4F1A))); require(chinese.size()==63 && validUtf8(chinese) && QString::fromUtf8(chinese).size()==21);
    QString emoji; for (int i=0;i<20;++i) emoji+=QString::fromUtf8("\xf0\x9f\x92\xbb");
    const QByteArray fourByte=clean(emoji); require(fourByte.size()==64 && validUtf8(fourByte));
    const QByteArray shifted=clean(QStringLiteral("a")+emoji); require(shifted.size()==61 && validUtf8(shifted));
    for (const auto& input : {QStringLiteral("Mac"), QString(70,QChar(0xE9)), QStringLiteral("x")+emoji, QString(100,QChar(0x3042))}) {
        const QByteArray out=clean(input); require(out.size()<=64 && !out.isEmpty() && validUtf8(out));
    }
    require(office::pairingDeviceNameQuery(QStringLiteral("Alice's Mac & Co=1?#%"))=="Alice%27s%20Mac%20%26%20Co%3D1%3F%23%25");
    require(office::pairingDeviceNameQuery(QStringLiteral("会"))=="%E4%BC%9A");
    require(office::pairingDeviceNameQuery(QStringLiteral("\n"))=="Moonlight%20Desk");
    const QByteArray local=office::pairingDeviceNameQuery();
    require(!local.isEmpty() && local.size()<=64*3);
    for (const char byte : local) require(QByteArray("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%").contains(byte));
    std::printf("office device name: %d checks passed\n",checks);
    return 0;
}
