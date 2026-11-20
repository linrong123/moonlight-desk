#include "localclipboard.h"

#import <AppKit/AppKit.h>

// Manual reference counting, like toolbar_mac.mm. Called on the main thread.
namespace office {
long localClipboardChangeCount() {
    @autoreleasepool {
        return static_cast<long>([NSPasteboard generalPasteboard].changeCount);
    }
}

LocalClipboard readLocalClipboard() {
    @autoreleasepool {
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        LocalClipboard result;
        result.changeCount = static_cast<long>(pasteboard.changeCount);
        // http://nspasteboard.org: password managers mark secrets this way.
        NSArray* types = pasteboard.types;
        if ([types containsObject:@"org.nspasteboard.ConcealedType"] ||
            [types containsObject:@"org.nspasteboard.TransientType"]) {
            result.concealed = true;
            return result;
        }
        NSString* string = [pasteboard stringForType:NSPasteboardTypeString];
        // dataUsingEncoding keeps embedded NUL characters that UTF8String drops.
        NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            result.hasText = true;
            if (data.length) result.text.assign(static_cast<const char*>(data.bytes), data.length);
        }
        return result;
    }
}

long writeLocalClipboard(const std::string& text) {
    @autoreleasepool {
        NSString* string = [[[NSString alloc] initWithBytes:text.data() length:text.size()
                                                   encoding:NSUTF8StringEncoding] autorelease];
        if (!string) return -1;
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        if (![pasteboard setString:string forType:NSPasteboardTypeString]) return -1;
        return static_cast<long>(pasteboard.changeCount);
    }
}
}
