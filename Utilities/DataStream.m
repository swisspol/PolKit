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

#import "DataStream.h"

#define kDataStreamErrorDomain	@"DataStreamErrorDomain"

@implementation DataReadStream

@synthesize dataSource=_source;

- (id) initWithDataSource:(id<DataStreamSource>)source userInfo:(id)info
{
	if(source == nil) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_source = [source retain];
		_info = [info retain];
		_status = NSStreamStatusNotOpen;
	}
	
	return self;
}

- (void) _cleanUp_DataReadStream
{
	if((_status == NSStreamStatusOpen) || (_status == NSStreamStatusAtEnd))
	[_source closeDataStream:_info];
}

- (void) finalize
{
	[self _cleanUp_DataReadStream];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_DataReadStream];
	
	[_error release];
	[_info release];
	[_source release];
	
	[super dealloc];
}

- (void) open
{
	if(_status == NSStreamStatusNotOpen) {
		if([_source openDataStream:_info])
		_status = NSStreamStatusOpen;
		else if(_error == nil)
		_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
	}
	else if(_error == nil)
	_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
}

- (void) close
{
	if((_status == NSStreamStatusOpen) || (_status == NSStreamStatusAtEnd)) {
		[_source closeDataStream:_info];
		_status = NSStreamStatusClosed;
	}
	else if(_error == nil)
	_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
}

- (id) delegate
{
	return nil;
}

- (void) setDelegate:(id)delegate
{
	;
}

- (id) propertyForKey:(NSString*)key
{
	return nil;
}

- (BOOL) setProperty:(id)property forKey:(NSString*)key
{
	return NO;
}

- (void) scheduleInRunLoop:(NSRunLoop*)aRunLoop forMode:(NSString*)mode
{
	;
}

- (void) removeFromRunLoop:(NSRunLoop*)aRunLoop forMode:(NSString*)mode
{
	;
}

- (NSStreamStatus) streamStatus
{
	return _status;
}

- (NSError*) streamError
{
	return _error;
}

- (NSInteger) read:(uint8_t*)buffer maxLength:(NSUInteger)len
{
	NSInteger				numBytes;
	
	if(_status == NSStreamStatusOpen) {
		numBytes = [_source readDataFromStream:_info buffer:buffer maxLength:len];
		if(numBytes < -1) {
			if(_error == nil)
			_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:numBytes userInfo:nil] retain];
		}
		else if(numBytes == 0)
		_status = NSStreamStatusAtEnd;
	}
	else if(_status == NSStreamStatusAtEnd)
	numBytes = 0;
	else
	numBytes = -1;
	
	return numBytes;
}

- (BOOL) getBuffer:(uint8_t**)buffer length:(NSUInteger*)len
{
	return NO;
}

- (BOOL) hasBytesAvailable
{
	return (_status == NSStreamStatusOpen ? YES : NO);
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (BOOL) _setCFClientFlags:(CFOptionFlags)streamEvents callback:(CFReadStreamClientCallBack)clientCB context:(CFStreamClientContext*)clientContext
{
   return NO;
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (void) _scheduleInCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)runLoopMode
{
   ;
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (void) _unscheduleFromCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)runLoopMode
{
	;
}

@end

@implementation DataWriteStream

@synthesize dataDestination=_destination;

- (id) initWithDataDestination:(id<DataStreamDestination>)destination userInfo:(id)info
{
	if(destination == nil) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_destination = [destination retain];
		_info = [info retain];
		_status = NSStreamStatusNotOpen;
	}
	
	return self;
}

- (void) _cleanUp_DataWriteStream
{
	if((_status == NSStreamStatusOpen) || (_status == NSStreamStatusAtEnd))
	[_destination closeDataStream:_info];
}

- (void) finalize
{
	[self _cleanUp_DataWriteStream];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_DataWriteStream];
	
	[_error release];
	[_info release];
	[_destination release];
	
	[super dealloc];
}

- (void) open
{
	if(_status == NSStreamStatusNotOpen) {
		if([_destination openDataStream:_info])
		_status = NSStreamStatusOpen;
		else if(_error == nil)
		_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
	}
	else if(_error == nil)
	_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
}

- (void) close
{
	if((_status == NSStreamStatusOpen) || (_status == NSStreamStatusAtEnd)) {
		[_destination closeDataStream:_info];
		_status = NSStreamStatusClosed;
	}
	else if(_error == nil)
	_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:-1 userInfo:nil] retain];
}

- (id) delegate
{
	return nil;
}

- (void) setDelegate:(id)delegate
{
	;
}

- (id) propertyForKey:(NSString*)key
{
	return nil;
}

- (BOOL) setProperty:(id)property forKey:(NSString*)key
{
	return NO;
}

- (void) scheduleInRunLoop:(NSRunLoop*)aRunLoop forMode:(NSString*)mode
{
	;
}

- (void) removeFromRunLoop:(NSRunLoop*)aRunLoop forMode:(NSString*)mode
{
	;
}

- (NSStreamStatus) streamStatus
{
	return _status;
}

- (NSError*) streamError
{
	return _error;
}

- (NSInteger) write:(const uint8_t*)buffer maxLength:(NSUInteger)len
{
	NSInteger				numBytes;
	
	if(_status == NSStreamStatusOpen) {
		numBytes = [_destination writeDataToStream:_info buffer:buffer maxLength:len];
		if(numBytes < -1) {
			if(_error == nil)
			_error = [[NSError errorWithDomain:kDataStreamErrorDomain code:numBytes userInfo:nil] retain];
		}
		else if(numBytes == 0)
		_status = NSStreamStatusAtEnd;
	}
	else if(_status == NSStreamStatusAtEnd)
	numBytes = 0;
	else
	numBytes = -1;
	
	return numBytes;
}

- (BOOL) hasSpaceAvailable
{
	return (_status == NSStreamStatusOpen ? YES : NO);
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (BOOL) _setCFClientFlags:(CFOptionFlags)streamEvents callback:(CFReadStreamClientCallBack)clientCB context:(CFStreamClientContext*)clientContext
{
   return NO;
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (void) _scheduleInCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)runLoopMode
{
   ;
}

/* Internal SPI required to be implemented for subclasses of NSStream to work */
- (void) _unscheduleFromCFRunLoop:(CFRunLoopRef)runLoop forMode:(CFStringRef)runLoopMode
{
	;
}

@end
