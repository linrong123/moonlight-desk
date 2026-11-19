#include "office/displayscale.h"
#include <QCoreApplication>
#include <cstdio>
#include <cstdlib>

static int checks;
static void require(bool value) { ++checks; if (!value) { std::fprintf(stderr,"FAIL check %d\n",checks); std::abort(); } }
static QString payload() {
    return QStringLiteral("<root status_code=\"200\" status_message=\"OK\"><scale>150</scale><recommended>125</recommended><supportedScales>100,125,150,200</supportedScales><displayToken>0123456789abcdefABCDEF0123456789</displayToken></root>");
}
static void rejected(const QString& input) {
    const auto result = office::parseDisplayScaleResponse(input);
    require(!result.valid() && result.status==0 && result.current==0 && result.recommended==0 && result.supported.empty() && result.token.isEmpty());
}
int main(int argc,char** argv) {
    QCoreApplication app(argc,argv);
    const auto valid = office::parseDisplayScaleResponse(payload());
    require(valid.valid() && valid.current==150 && valid.recommended==125 && valid.supported==std::vector<int>({100,125,150,200}) && valid.token==QStringLiteral("0123456789abcdefABCDEF0123456789"));
    auto boundary=payload(); boundary.replace("150</scale>","500</scale>"); boundary.replace("125</recommended>","100</recommended>"); boundary.replace("100,125,150,200","100,125,150,175,200,225,250,300,350,400,450,500");
    require(office::parseDisplayScaleResponse(boundary).valid());
    auto singleton=payload(); singleton.replace("125</recommended>","150</recommended>"); singleton.replace("100,125,150,200","150"); require(office::parseDisplayScaleResponse(singleton).valid());
    for (int status : {400,409,422,501,503}) {
        const auto result=office::parseDisplayScaleResponse(QStringLiteral("<root status_code=\"%1\" status_message=\"ignored\"><message>Remote text &amp; more</message><scale>150</scale></root>").arg(status));
        require(result.status==status && !result.valid() && result.current==0 && result.recommended==0 && result.supported.empty() && result.token.isEmpty());
    }
    for (const auto& tag : {"scale","recommended","supportedScales","displayToken"}) {
        auto missing=payload(); const QString name=QString::fromLatin1(tag); const int start=missing.indexOf("<"+name+">"); const int end=missing.indexOf("</"+name+">",start)+name.size()+3; missing.remove(start,end-start); rejected(missing);
        auto duplicate=payload(); duplicate.replace("</root>","<"+name+">150</"+name+"></root>"); rejected(duplicate);
    }
    for (const auto& invalid : {"", "0", "99", "151", "+150", "0150", "150 ", " 150", "150.0", "999999999999999999999999999999", "１５０"}) {
        auto changed=payload(); changed.replace("150</scale>",QString::fromUtf8(invalid)+"</scale>"); rejected(changed);
        changed=payload(); changed.replace("125</recommended>",QString::fromUtf8(invalid)+"</recommended>"); rejected(changed);
    }
    for (const auto& invalid : {"", "100,150,125,200", "100,125,150,150,200", "100,125,150,201", "100, 125,150,200", "100,125,150,200,", ",100,125,150,200", "100,,125,150,200", "100,125", "100,150", "0100,125,150,200"}) {
        auto changed=payload(); changed.replace("100,125,150,200",QString::fromLatin1(invalid)); rejected(changed);
    }
    for (const auto& invalid : {"", "0123456789abcdefABCDEF012345678", "0123456789abcdefABCDEF01234567890", "g123456789abcdefABCDEF0123456789", "0123456789abcdefABCDEF0123456789\n"}) {
        auto changed=payload(); changed.replace("0123456789abcdefABCDEF0123456789",QString::fromLatin1(invalid)); rejected(changed);
    }
    for (const auto& status : {"0","201","500","0200","+200","200 ",""}) { auto changed=payload(); changed.replace("status_code=\"200\"",QStringLiteral("status_code=\"%1\"").arg(status)); rejected(changed); }
    rejected(QString()); rejected(payload().left(payload().size()-1)); rejected(payload()+payload()); rejected("x"+payload()); rejected(payload()+"x");
    rejected("<!DOCTYPE root>"+payload()); rejected("<!DOCTYPE root [<!ENTITY test '150'>]>"+payload());
    auto nested=payload(); nested.replace("<scale>150</scale>","<scale><nested>150</nested></scale>"); rejected(nested);
    nested=payload(); nested.replace("<scale>150</scale>","<wrapper><scale>150</scale></wrapper>"); rejected(nested);
    auto attr=payload(); attr.replace("<scale>","<scale value=\"150\">"); rejected(attr);
    attr=payload(); attr.replace("status_code=\"200\"", "status_code=\"200\" status_code=\"200\""); rejected(attr);
    attr=payload(); attr.replace("<root ","<root xmlns=\"example\" "); rejected(attr);
    auto unknown=payload(); unknown.replace("</root>","<unknown>value</unknown></root>"); rejected(unknown);
    rejected(QStringLiteral("<root status_code=\"503\"><message>x</message><message>x</message></root>"));
    const auto partialFailure = office::parseDisplayScaleResponse(QStringLiteral("<root status_code=\"409\"><scale>nonsense</scale><displayToken>0123456789abcdefABCDEF0123456789</displayToken></root>"));
    require(partialFailure.status == 409 && partialFailure.current == 0 && partialFailure.token.isEmpty() && partialFailure.supported.empty());
    rejected(QStringLiteral("<root status_code=\"409\"><displayToken>bad</displayToken></root>"));
    rejected(QStringLiteral("<root status_code=\"200\"/>"));
    rejected(QStringLiteral("<root status_code=\"503\"><message><b>nested</b></message></root>"));
    auto textAtRoot = payload(); textAtRoot.replace("</root>", "unexpected</root>"); rejected(textAtRoot);
    auto successMessage = payload(); successMessage.replace("</root>", "<message>ignored</message></root>"); rejected(successMessage);
    auto escapedDigits = payload(); escapedDigits.replace("150</scale>", "&#49;50</scale>"); require(office::parseDisplayScaleResponse(escapedDigits).valid());
    require(office::parseDisplayScaleResponse("<?xml version=\"1.0\"?><!-- response -->" + payload() + "<!-- end -->").valid());
    auto exact=payload(); exact.insert(exact.indexOf('>')+1, QString(8192-exact.size(),' ')); require(exact.toUtf8().size()==8192); require(office::parseDisplayScaleResponse(exact).valid()); rejected(exact+" ");
    auto unicode=payload(); unicode.replace("status_message=\"OK\"", "status_message=\""+QString(3000,QChar(0x4e2d))+"\""); rejected(unicode);
    std::printf("PASS: %d strict display-scale response checks (QtCore only, no UI)\n",checks);
}
