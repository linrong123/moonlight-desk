#include "office/clipboardsync.h"
#include "office/clipboardresponse.h"
#include <QByteArray>
#include <QCoreApplication>
#include <QString>
#include <cstdio>
#include <cstdlib>
#include <string>

using office::ClipboardReply;
using office::ClipboardSync;

static int checks;
static void require(bool value) { ++checks; if (!value) { std::fprintf(stderr,"FAIL check %d\n",checks); std::abort(); } }

static ClipboardReply ok(std::uint64_t sequence, const std::string& text = {}, bool hasText = true, bool tooLarge = false) {
    ClipboardReply reply; reply.status=200; reply.hasSequence=true; reply.sequence=sequence; reply.hasText=hasText; reply.tooLarge=tooLarge; reply.text=text; return reply;
}
static ClipboardReply status(int code) { ClipboardReply reply; reply.status=code; return reply; }
static QString getXml(const QByteArray& text, const QString& sequence = QStringLiteral("42")) {
    return QStringLiteral("<root status_code=\"200\" status_message=\"OK\"><sequence>%1</sequence><hasText>1</hasText><tooLarge>0</tooLarge><text>%2</text></root>")
        .arg(sequence, QString::fromLatin1(text.toBase64()));
}
static void rejected(const QString& input) {
    const auto reply = office::parseClipboardResponse(input);
    require(reply.status==0 && !reply.hasSequence && !reply.hasText && reply.text.empty());
}
static ClipboardSync activeSync() { ClipboardSync sync; sync.setSupported(true); return sync; }

static void normalization() {
    require(office::normalizeClipboardText("a\r\nb\rc\nd") == "a\nb\nc\nd");
    require(office::normalizeClipboardText("\r\r\n\n") == "\n\n\n");
    require(office::normalizeClipboardText(std::string("x\0y",3)) == std::string("x\0y",3));
}

static void push() {
    ClipboardSync off; std::string text="hi";
    require(off.focusGained(1,true,text) == ClipboardSync::Push::Skip); // host lacks OfficeClipboard
    auto sync = activeSync();
    require(sync.active() && sync.enabled() && !sync.denied());
    text="a\r\nb";
    require(sync.wantsLocal(7) && sync.focusGained(7,true,text) == ClipboardSync::Push::Send && text=="a\nb");
    text="a\nb";
    require(!sync.wantsLocal(7) && sync.focusGained(7,true,text) == ClipboardSync::Push::Skip); // same changeCount
    text.clear(); require(sync.focusGained(8,false,text) == ClipboardSync::Push::Skip); // image or empty pasteboard
    require(!sync.wantsLocal(8)); // a non-text copy is adopted, not retried
    std::string big(office::clipboardMaxBytes + 1, 'x');
    require(sync.focusGained(9,true,big) == ClipboardSync::Push::TooLarge);
    std::string limit(office::clipboardMaxBytes, 'x');
    require(sync.focusGained(10,true,limit) == ClipboardSync::Push::Send);
    std::string crlf; for (std::size_t i = 0; i < office::clipboardMaxBytes / 2; ++i) crlf += "\r\n";
    require(sync.focusGained(11,true,crlf) == ClipboardSync::Push::Send && crlf.size()==office::clipboardMaxBytes/2); // limit after normalization

    // Transport failure and 5xx retry on the next focus gain; 400/413 do not.
    for (int code : {0,500,503}) {
        auto retry = activeSync(); std::string value="x";
        require(retry.focusGained(3,true,value) == ClipboardSync::Push::Send);
        require(retry.pushFinished(status(code),3) == ClipboardSync::Reply::None && retry.wantsLocal(3));
    }
    for (int code : {400,413,404}) { // bare HTTP 413 included
        auto stops = activeSync(); std::string value="x";
        require(stops.focusGained(3,true,value) == ClipboardSync::Push::Send);
        require(stops.pushFinished(status(code),3) == ClipboardSync::Reply::None && !stops.wantsLocal(3));
    }
    auto moved = activeSync(); std::string value="x";
    require(moved.focusGained(3,true,value) == ClipboardSync::Push::Send);
    value="y"; require(moved.focusGained(4,true,value) == ClipboardSync::Push::Send);
    moved.pushFinished(status(0),3); require(!moved.wantsLocal(4)); // stale failure does not reopen a newer push
    auto pushed = activeSync(); value="x";
    require(pushed.focusGained(3,true,value) == ClipboardSync::Push::Send);
    require(pushed.pushFinished(ok(9,{},false),3) == ClipboardSync::Reply::None && pushed.hasRemoteSequence() && pushed.remoteSequence()==9);
    ClipboardSync::Reply outcome;
    require(!pushed.pullFinished(ok(9,"x"),outcome,3,3,true,"x")); // our own push is not pulled back
}

static void denied() {
    auto sync = activeSync(); std::string text="x";
    require(sync.focusGained(1,true,text) == ClipboardSync::Push::Send);
    require(sync.pushFinished(status(403),1) == ClipboardSync::Reply::Denied && sync.denied() && !sync.active());
    require(sync.baselineFinished(status(403)) == ClipboardSync::Reply::None); // reported once
    ClipboardSync::Reply outcome;
    require(!sync.pullFinished(status(403),outcome,1,1,false,{}) && outcome == ClipboardSync::Reply::None);
    text="y"; require(sync.focusGained(2,true,text) == ClipboardSync::Push::Skip && !sync.wantsLocal(2));
    sync.resetConnection(); require(sync.active() && !sync.denied()); // a new connection may try again
    auto pull = activeSync();
    require(!pull.pullFinished(status(403),outcome,1,1,false,{}) && outcome == ClipboardSync::Reply::Denied);
    auto base = activeSync();
    require(base.baselineFinished(status(403)) == ClipboardSync::Reply::Denied && base.denied() && base.deniedStatus()==403);
    // 401 (disabled client, certificate not accepted) is denied like 403: no retry loop.
    auto auth = activeSync(); text="x";
    require(auth.focusGained(1,true,text) == ClipboardSync::Push::Send);
    require(auth.pushFinished(status(401),1) == ClipboardSync::Reply::Denied && auth.denied() && auth.deniedStatus()==401);
    require(auth.pushFinished(status(401),1) == ClipboardSync::Reply::None && auth.baselineFinished(status(403)) == ClipboardSync::Reply::None);
    require(auth.deniedStatus()==401); // the first denial is the one reported
    text="y"; require(!auth.wantsLocal(2) && auth.focusGained(2,true,text) == ClipboardSync::Push::Skip);
    auth.resetConnection(); require(auth.active() && auth.deniedStatus()==0);
    auto authPull = activeSync();
    require(!authPull.pullFinished(status(401),outcome,1,1,false,{}) && outcome == ClipboardSync::Reply::Denied);
    auto authBase = activeSync();
    require(authBase.baselineFinished(status(401)) == ClipboardSync::Reply::Denied && authBase.deniedStatus()==401);
    // Bare HTTP errors keep their status; no HTTP response maps to 0 (retryable).
    require(office::clipboardErrorStatus(401)==401 && office::clipboardErrorStatus(413)==413 && office::clipboardErrorStatus(503)==503);
    require(office::clipboardErrorStatus(0)==0 && office::clipboardErrorStatus(200)==0 && office::clipboardErrorStatus(302)==0 && office::clipboardErrorStatus(600)==0);
    require(office::clipboardDenial(401) && office::clipboardDenial(403) && !office::clipboardDenial(413) && !office::clipboardDenial(0));
}

static void pull() {
    auto sync = activeSync(); ClipboardSync::Reply outcome;
    require(sync.baselineFinished(ok(5,"old")) == ClipboardSync::Reply::None && sync.remoteSequence()==5);
    require(!sync.pullFinished(ok(5,"old"),outcome,1,1,false,{})); // baseline: existing Windows text stays put
    require(sync.pullFinished(ok(6,"新内容 😀\n"),outcome,1,1,true,"mac") && outcome == ClipboardSync::Reply::None);
    sync.localWritten(2);
    require(!sync.wantsLocal(2)); // our own write is not pushed back
    require(!sync.pullFinished(ok(6,"新内容 😀\n"),outcome,2,2,false,{})); // same sequence
    require(!sync.pullFinished(ok(7,"later"),outcome,2,3,true,"copied on Mac")); // local changed in flight: Mac wins
    require(sync.remoteSequence()==7 && sync.wantsLocal(3));
    require(!sync.pullFinished(ok(8,"same\n"),outcome,3,3,true,"same\r\n")); // identical text, no rewrite
    require(!sync.pullFinished(ok(9,{},false,true),outcome,3,3,false,{})); // tooLarge
    require(!sync.pullFinished(ok(10,{},false),outcome,3,3,false,{})); // hasText=0 (image on Windows)
    require(!sync.pullFinished(ok(11,""),outcome,3,3,false,{})); // empty text
    require(!sync.pullFinished(ok(12,std::string(office::clipboardMaxBytes + 1,'x')),outcome,3,3,false,{}));
    require(!sync.pullFinished(status(0),outcome,3,3,false,{}) && !sync.pullFinished(status(503),outcome,3,3,false,{}));
    ClipboardReply noSequence = ok(13,"x"); noSequence.hasSequence=false;
    require(!sync.pullFinished(noSequence,outcome,3,3,false,{}));
    require(sync.pullFinished(ok(14,"x"),outcome,3,3,false,{}));

    // Toggle off: nothing moves; switching on adopts both sides.
    auto toggle = activeSync(); std::string text="mac";
    toggle.setEnabled(false);
    require(!toggle.active() && toggle.focusGained(1,true,text) == ClipboardSync::Push::Skip && !toggle.wantsLocal(1));
    require(!toggle.pullFinished(ok(3,"win"),outcome,1,1,false,{}));
    toggle.setEnabled(true); toggle.adoptLocal(1);
    require(toggle.baselineFinished(ok(3,"win")) == ClipboardSync::Reply::None);
    require(toggle.focusGained(1,true,text) == ClipboardSync::Push::Skip);
    require(!toggle.pullFinished(ok(3,"win"),outcome,1,1,false,{}));
    text="new"; require(toggle.focusGained(2,true,text) == ClipboardSync::Push::Send);
    toggle.forgetRemote(); // switched on again: the next sequence is a baseline
    require(!toggle.pullFinished(ok(4,"win2"),outcome,2,2,false,{}) && toggle.remoteSequence()==4);
    require(toggle.pullFinished(ok(5,"win3"),outcome,2,2,false,{}));

    // Baseline failed: the first pull only records the sequence.
    auto noBase = activeSync();
    require(noBase.baselineFinished(status(503)) == ClipboardSync::Reply::None && !noBase.hasRemoteSequence());
    require(!noBase.pullFinished(ok(5,"already on Windows"),outcome,1,1,false,{}) && noBase.remoteSequence()==5);
    require(noBase.pullFinished(ok(6,"copied later"),outcome,1,1,false,{}));
    noBase.resetConnection(); require(!noBase.hasRemoteSequence()); // a new connection starts without a baseline
    require(!noBase.pullFinished(ok(7,"other host"),outcome,1,1,false,{}));
    ClipboardSync unsupported; unsupported.setEnabled(true);
    require(!unsupported.pullFinished(ok(1,"x"),outcome,0,0,false,{}));
}

static void parser() {
    const QByteArray chinese = QStringLiteral("中文剪贴板 😀\r\n第二行").toUtf8();
    const auto reply = office::parseClipboardResponse(getXml(chinese, QStringLiteral("18446744073709551615")));
    require(reply.status==200 && reply.hasSequence && reply.sequence==18446744073709551615ULL && reply.hasText && !reply.tooLarge);
    require(reply.text == office::normalizeClipboardText(chinese.toStdString()) && reply.text.find('\r')==std::string::npos);
    const auto empty = office::parseClipboardResponse(QStringLiteral("<root status_code=\"200\"><sequence>3</sequence><hasText>1</hasText><text></text></root>"));
    require(empty.status==200 && empty.hasText && empty.text.empty());
    const auto none = office::parseClipboardResponse(QStringLiteral("<root status_code=\"200\" status_message=\"OK\"><sequence>0</sequence><hasText>0</hasText><tooLarge>1</tooLarge><extra>ignored</extra></root>"));
    require(none.status==200 && none.hasSequence && none.sequence==0 && !none.hasText && none.tooLarge);
    const auto post = office::parseClipboardResponse(QStringLiteral("<root status_code=\"200\"><sequence>43</sequence></root>"));
    require(post.status==200 && post.hasSequence && post.sequence==43 && !post.hasText);
    const auto spaced = office::parseClipboardResponse(QStringLiteral("<root status_code=\"200\">\n  <sequence> 7 </sequence>\n  <hasText>1</hasText>\n  <text>\n%1\n</text>\n</root>").arg(QString::fromLatin1(QByteArray("ok").toBase64())));
    require(spaced.status==200 && spaced.sequence==7 && spaced.text=="ok");
    const QByteArray limit(static_cast<int>(office::clipboardMaxBytes), 'a');
    require(office::parseClipboardResponse(getXml(limit)).text.size()==office::clipboardMaxBytes);
    for (int code : {400,403,413,503}) {
        const auto error = office::parseClipboardResponse(QStringLiteral("<root status_code=\"%1\" status_message=\"x\"><sequence>bad</sequence><text>!!</text></root>").arg(code));
        require(error.status==code && !error.hasSequence && !error.hasText && error.text.empty());
    }

    rejected(QString());
    rejected(QStringLiteral("<root><sequence>1</sequence></root>"));
    rejected(QStringLiteral("<root status_code=\"200\" status_code=\"200\"></root>"));
    rejected(QStringLiteral("<root status_code=\"99\"></root>"));
    rejected(QStringLiteral("<root status_code=\"600\"></root>"));
    rejected(QStringLiteral("<other status_code=\"200\"></other>"));
    rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence></root><root status_code=\"200\"/>"));
    rejected(QStringLiteral("<!DOCTYPE root [<!ENTITY e \"1\">]><root status_code=\"200\"><sequence>&e;</sequence></root>"));
    rejected(QStringLiteral("<root xmlns:x=\"urn:x\" status_code=\"200\"><sequence>1</sequence></root>"));
    rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence><sequence>2</sequence></root>"));
    rejected(QStringLiteral("<root status_code=\"200\"><sequence a=\"1\">1</sequence></root>"));
    rejected(QStringLiteral("<root status_code=\"200\"><sequence><x/></sequence></root>"));
    rejected(QStringLiteral("<root status_code=\"200\">loose<sequence>1</sequence></root>"));
    for (const auto& bad : {"", "-1", "+1", "1.0", "0x10", "18446744073709551616", "123456789012345678901", "１"})
        rejected(getXml("ok", QString::fromUtf8(bad)));
    for (const auto& bad : {"2", "yes", "", " 1"}) {
        rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence><hasText>%1</hasText></root>").arg(QString::fromUtf8(bad)));
        rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence><tooLarge>%1</tooLarge></root>").arg(QString::fromUtf8(bad)));
    }
    rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence><hasText>1</hasText></root>")); // text missing
    for (const auto& bad : {"b2s", "b2s==", "b2=s", "=b2s", "b2 s", "b2-_", "b2s=x", "!!!!", "中文中文"})
        rejected(QStringLiteral("<root status_code=\"200\"><sequence>1</sequence><hasText>1</hasText><text>%1</text></root>").arg(QString::fromUtf8(bad)));
    rejected(getXml(QByteArray("\xff\xfe", 2)));          // invalid UTF-8
    rejected(getXml(QByteArray("\xed\xa0\x80", 3)));      // UTF-16 surrogate encoded as UTF-8
    rejected(getXml(QByteArray(static_cast<int>(office::clipboardMaxBytes) + 1, 'a')));
    rejected(QStringLiteral("<root status_code=\"200\"><pad>%1</pad></root>").arg(QString(2 * 1024 * 1024, QLatin1Char('a'))));
}

int main(int argc,char** argv) {
    QCoreApplication app(argc,argv);
    normalization();
    push();
    denied();
    pull();
    parser();
    std::printf("PASS office clipboard (%d checks)\n",checks);
    return 0;
}
