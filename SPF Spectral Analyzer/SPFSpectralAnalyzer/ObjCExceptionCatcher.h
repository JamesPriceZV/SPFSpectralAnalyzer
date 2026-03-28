#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Catches Objective-C NSException thrown by Core Data / CloudKit operations.
/// Swift's do/catch cannot catch NSException, so modelContext.save() during
/// active CloudKit sync can crash the app with an uncatchable exception.
/// This helper converts NSException into NSError for Swift consumption.
@interface ObjCExceptionCatcher : NSObject

/// Executes the block and returns YES on success.
/// If an NSException is thrown, catches it, wraps it in an NSError, and returns NO.
+ (BOOL)tryBlock:(void (NS_NOESCAPE ^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
