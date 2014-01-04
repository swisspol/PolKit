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

#import "StreamCoding.h"

#define kStreamEncoderCookie	'stcd'
#define kStreamEncoderVersion	1

@interface StreamEncoder ()
- (id) initWithStream:(NSOutputStream*)stream version:(NSUInteger)version;
@end

@interface StreamDecoder ()
- (id) initWithStream:(NSInputStream*)stream;
@end

@implementation StreamEncoder

@synthesize version=_version;

+ (BOOL) encodeRootObject:(id<StreamCoding>)object toStream:(NSOutputStream*)stream version:(NSUInteger)version
{
	BOOL					success = YES;
	StreamEncoder*			encoder;
	NSAutoreleasePool*		localPool;
	
	encoder = [[self alloc] initWithStream:stream version:version];
	if(encoder == nil)
	return NO;
	
	localPool = [NSAutoreleasePool new];
	@try {
		[encoder encodeObject:object];
	}
	@catch(id exception) {
		NSLog(@"%@", exception);
		success = NO;
	}
	[localPool drain];
	
	[encoder release];
	
	return success;
}

+ (NSData*) encodeRootObjectToData:(id)object version:(NSUInteger)version
{
	NSOutputStream*			stream = [NSOutputStream outputStreamToMemory];
	
	if([self encodeRootObject:object toStream:stream version:version])
	return [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
	
	return nil;
}

- (id) initWithStream:(NSOutputStream*)stream version:(NSUInteger)version
{
	if((stream == nil) || ([stream streamStatus] != NSStreamStatusNotOpen)) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_stream = [stream retain];
		[_stream open];
		if([_stream streamStatus] != NSStreamStatusOpen) {
			[self release];
			return nil;
		}
		
		[self encodeUInt32:kStreamEncoderCookie];
		[self encodeUInt32:kStreamEncoderVersion];
		[self encodeUInt32:version];
		_version = version;
	}
	
	return self;
}

- (void) dealloc
{
	[_stream close];
	[_stream release];
	
	[super dealloc];
}

- (void) encodeBytes:(const void*)buffer length:(NSInteger)length
{
	if(length && ([_stream write:buffer maxLength:length] != length))
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed writing to stream (status = %i): %@", __FUNCTION__, [_stream streamStatus], [_stream streamError]];
}

- (void) encodeObject:(id<StreamCoding>)object
{
	[self encodeString:NSStringFromClass([(id)object class])];
	[object encodeToStreamEncoder:self];
}

- (void) encodeString:(NSString*)string
{
	NSData*			data;
	UInt32			length;
	
	if(string) {
		data = [string dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
		if(data == nil)
		[NSException raise:NSInternalInconsistencyException format:@"%s: Failed converting string to UTF8: %@", __FUNCTION__, string];
		length = NSSwapHostIntToLittle([data length]);
		[self encodeBytes:&length length:sizeof(UInt32)];
		[self encodeBytes:[data bytes] length:[data length]];
	}
	else {
		length = 0xFFFFFFFF;
		[self encodeBytes:&length length:sizeof(UInt32)];
	}
}

- (void) encodeData:(NSData*)data
{
	UInt32			length = NSSwapHostIntToLittle([data length]);
	
	[self encodeBytes:&length length:sizeof(UInt32)];
	[self encodeBytes:[data bytes] length:[data length]];
}

- (void) encodeUInt32:(UInt32)value
{
	value = NSSwapHostIntToLittle(value);
	[self encodeBytes:&value length:sizeof(UInt32)];
}

@end

@implementation StreamDecoder

@synthesize version=_version;

+ (id) decodeRootObjectFromStream:(NSInputStream*)stream
{
	StreamDecoder*			decoder;
	NSAutoreleasePool*		localPool;
	id						object;
	
	decoder = [[self alloc] initWithStream:stream];
	if(decoder == nil)
	return nil;
	
	localPool = [NSAutoreleasePool new];
	@try {
		object = [decoder decodeObject];
	}
	@catch(id exception) {
		NSLog(@"%@", exception);
		object = nil;
	}
	[localPool drain];
	
	[decoder release];
	
	return object;
}

+ (id) decodeRootObjectFromData:(NSData*)data
{
	return [self decodeRootObjectFromStream:[NSInputStream inputStreamWithData:data]];
}

- (id) initWithStream:(NSInputStream*)stream
{
	if((stream == nil) || ([stream streamStatus] != NSStreamStatusNotOpen)) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_stream = [stream retain];
		[_stream open];
		if([_stream streamStatus] != NSStreamStatusOpen) {
			[self release];
			return nil;
		}
		
		if([self decodeUInt32] != kStreamEncoderCookie)
		[NSException raise:NSInternalInconsistencyException format:@"%s: Invalid stream header", __FUNCTION__];
		if([self decodeUInt32] != kStreamEncoderVersion)
		[NSException raise:NSInternalInconsistencyException format:@"%s: Invalid stream version", __FUNCTION__];
		_version = [self decodeUInt32];
	}
	
	return self;
}

- (void) dealloc
{
	[_stream close];
	[_stream release];
	
	[super dealloc];
}

- (void) decodeBytes:(void*)buffer length:(NSInteger)length
{
	if(length && ([_stream read:buffer maxLength:length] != length))
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed reading from stream (status = %i): %@", __FUNCTION__, [_stream streamStatus], [_stream streamError]];
}

- (id) decodeObject
{
	NSString*		string;
	id				object;
	
	string = [self decodeString];
	if(string == nil)
	return nil;
	
	object = [[NSClassFromString(string) alloc] initWithStreamDecoder:self];
	if(object == nil)
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed creating object: %@", __FUNCTION__, string];
	
	return [object autorelease];
}

- (NSString*) decodeString
{
	UInt32			length;
	NSMutableData*	data;
	NSString*		string;
	
	[self decodeBytes:&length length:sizeof(UInt32)];
	if(length == 0xFFFFFFFF)
	return nil;
	
	data = [[NSMutableData alloc] initWithLength:NSSwapLittleIntToHost(length)];
	if(data == nil)
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed allocating memory: %i bytes", __FUNCTION__, NSSwapLittleIntToHost(length)];
	[self decodeBytes:[data mutableBytes] length:[data length]];
	string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	[data release];
	if(string == nil)
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed creating string from UTF8: %@", __FUNCTION__, data];
	
	return [string autorelease];
}

- (NSData*) decodeData
{
	UInt32			length;
	NSMutableData*	data;
	
	[self decodeBytes:&length length:sizeof(UInt32)];
	data = [NSMutableData dataWithLength:NSSwapLittleIntToHost(length)];
	if(data == nil)
	[NSException raise:NSInternalInconsistencyException format:@"%s: Failed allocating memory: %i bytes", __FUNCTION__, NSSwapLittleIntToHost(length)];
	
	[self decodeBytes:[data mutableBytes] length:[data length]];
	
	return data;
}

- (UInt32) decodeUInt32
{
	UInt32			value;
	
	[self decodeBytes:&value length:sizeof(UInt32)];
	
	return NSSwapLittleIntToHost(value);
}

@end
