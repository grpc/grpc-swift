#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "cgrpc.h"

FOUNDATION_EXPORT double SwiftGRPCVersionNumber;
FOUNDATION_EXPORT const unsigned char SwiftGRPCVersionString[];

