///
/// Copyright (c) 2016 Dropbox, Inc. All rights reserved.
///
/// Auto-generated by Stone, do not modify.
///

#import <Foundation/Foundation.h>

#import "DBSerializableProtocol.h"

@class DBFILESListRevisionsArg;
@class DBFILESListRevisionsMode;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - API Object

///
/// The `ListRevisionsArg` struct.
///
/// This class implements the `DBSerializable` protocol (serialize and
/// deserialize instance methods), which is required for all Obj-C SDK API route
/// objects.
///
@interface DBFILESListRevisionsArg : NSObject <DBSerializable, NSCopying>

#pragma mark - Instance fields

/// The path to the file you want to see the revisions of.
@property (nonatomic, readonly, copy) NSString *path;

/// Determines the behavior of the API in listing the revisions for a given file
/// path or id.
@property (nonatomic, readonly) DBFILESListRevisionsMode *mode;

/// The maximum number of revision entries returned.
@property (nonatomic, readonly) NSNumber *limit;

#pragma mark - Constructors

///
/// Full constructor for the struct (exposes all instance variables).
///
/// @param path The path to the file you want to see the revisions of.
/// @param mode Determines the behavior of the API in listing the revisions for
/// a given file path or id.
/// @param limit The maximum number of revision entries returned.
///
/// @return An initialized instance.
///
- (instancetype)initWithPath:(NSString *)path
                        mode:(nullable DBFILESListRevisionsMode *)mode
                       limit:(nullable NSNumber *)limit;

///
/// Convenience constructor (exposes only non-nullable instance variables with
/// no default value).
///
/// @param path The path to the file you want to see the revisions of.
///
/// @return An initialized instance.
///
- (instancetype)initWithPath:(NSString *)path;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark - Serializer Object

///
/// The serialization class for the `ListRevisionsArg` struct.
///
@interface DBFILESListRevisionsArgSerializer : NSObject

///
/// Serializes `DBFILESListRevisionsArg` instances.
///
/// @param instance An instance of the `DBFILESListRevisionsArg` API object.
///
/// @return A json-compatible dictionary representation of the
/// `DBFILESListRevisionsArg` API object.
///
+ (nullable NSDictionary *)serialize:(DBFILESListRevisionsArg *)instance;

///
/// Deserializes `DBFILESListRevisionsArg` instances.
///
/// @param dict A json-compatible dictionary representation of the
/// `DBFILESListRevisionsArg` API object.
///
/// @return An instantiation of the `DBFILESListRevisionsArg` object.
///
+ (DBFILESListRevisionsArg *)deserialize:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
