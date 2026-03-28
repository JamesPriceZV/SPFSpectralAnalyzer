#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)tryBlock:(void (NS_NOESCAPE ^)(void))block error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            userInfo[@"NSExceptionName"] = exception.name;
            if (exception.reason) {
                userInfo[@"NSExceptionReason"] = exception.reason;
            }
            if (exception.userInfo) {
                userInfo[@"NSExceptionUserInfo"] = exception.userInfo;
            }
            *error = [NSError errorWithDomain:@"ObjCExceptionCatcher"
                                         code:1
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
