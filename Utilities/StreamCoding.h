/*
	This file is part of the PolKit library.
	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Foundation/Foundation.h>

@class StreamEncoder, StreamDecoder;

@protocol StreamCoding
- (void) encodeToStreamEncoder:(StreamEncoder*)encoder;
- (id) initWithStreamDecoder:(StreamDecoder*)decoder;
@end

@interface StreamEncoder : NSObject
{
@private
	NSOutputStream*			_stream;
	NSUInteger				_version;
}
+ (BOOL) encodeRootObject:(id<StreamCoding>)object toStream:(NSOutputStream*)stream version:(NSUInteger)version;
+ (NSData*) encodeRootObjectToData:(id)object version:(NSUInteger)version;

@property(nonatomic, readonly) NSUInteger version;

- (void) encodeBytes:(const void*)buffer length:(NSInteger)length;
- (void) encodeObject:(id<StreamCoding>)object;
- (void) encodeString:(NSString*)string;
- (void) encodeData:(NSData*)data;
- (void) encodeUInt32:(UInt32)value;
@end

@interface StreamDecoder : NSObject
{
@private
	NSInputStream*			_stream;
	NSUInteger				_version;
}
+ (id) decodeRootObjectFromStream:(NSInputStream*)stream;
+ (id) decodeRootObjectFromData:(NSData*)data;

@property(nonatomic, readonly) NSUInteger version;

- (void) decodeBytes:(void*)buffer length:(NSInteger)length;
- (id) decodeObject;
- (NSString*) decodeString;
- (NSData*) decodeData;
- (UInt32) decodeUInt32;
@end
