/*

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc.
("Apple") in consideration of your agreement to the following terms, and your
use, installation, modification or redistribution of this Apple software
constitutes acceptance of these terms.  If you do not agree with these terms,
please do not use, install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and subject
to these terms, Apple grants you a personal, non-exclusive license, under
Apple's copyrights in this original Apple software (the "Apple Software"), to
use, reproduce, modify and redistribute the Apple Software, with or without
modifications, in source and/or binary forms; provided that if you redistribute
the Apple Software in its entirety and without modifications, you must retain
this notice and the following text and disclaimers in all such redistributions
of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may be used
to endorse or promote products derived from the Apple Software without specific
prior written permission from Apple.  Except as expressly stated in this notice,
no other rights or licenses, express or implied, are granted by Apple herein,
including but not limited to any patent rights that may be infringed by your
derivative works or by other works in which the Apple Software may be
incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR
DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF
CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF
APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2008 Apple Inc. All Rights Reserved.

*/

#import <pthread.h>
#import <unistd.h>

#import "TCPServer.h"
#import "Networking_Internal.h"

//STRUCTURES:

typedef struct {
	NSUInteger					depth;
	NSAutoreleasePool*			pool;
} ObserverData;

//FUNCTIONS:

static void _ObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void* info)
{
	ObserverData*				data = (ObserverData*)info;
	
	if(activity & kCFRunLoopEntry)
	data->depth += 1;
	
	if((activity & kCFRunLoopAfterWaiting) && (data->depth == 1)) {
		if(data->pool == nil)
		data->pool = [NSAutoreleasePool new];
	}
	
	if((activity & kCFRunLoopBeforeWaiting) && (data->depth == 1)) {
		[data->pool drain];
		data->pool = nil;
	}
	
	if(activity & kCFRunLoopExit)
	data->depth -= 1;
}

//CLASS INTERFACES:

@interface TCPServerConnection (Private)
- (void) _setServer:(TCPServer*)server;
@end

@interface TCPServer (Internal)
- (void) _removeConnection:(TCPServerConnection*)connection;
@end

//CLASS IMPLEMENTATIONS:

@implementation TCPServerConnection

@synthesize server=_server;

- (void) _setServer:(TCPServer*)server
{
	_server = server;
}

- (void) _invalidate
{
	CFRunLoopRef		runLoop = [self CFRunLoop]; //NOTE: We don't need to retain it as we know it will still be valid
	TCPServer*			server;
	
	server = [_server retain];
	
	[super _invalidate]; //NOTE: The server delegate may destroy the server when notified this connection was invalidated
	
	if([[server class] useConnectionThreads])
	CFRunLoopStop(runLoop);
	else
	[server _removeConnection:self];
	
	[server release];
}

@end

@implementation TCPServer

@synthesize delegate=_delegate;

+ (BOOL) useConnectionThreads
{
	return NO;
}

+ (Class) connectionClass
{
	return [TCPServerConnection class];
}

- (id) initWithPort:(UInt16)port
{
	if((self = [super initWithPort:port])) {
		_connections = [NSMutableSet new];
		pthread_mutex_init(&_connectionsMutex, NULL);
	}
	
	return self;
}

- (void) dealloc
{
	[self stop]; //NOTE: Make sure our -stop is executed immediately
	
	pthread_mutex_destroy(&_connectionsMutex);
	
	[_connections release];
	
	[super dealloc];
}

- (void) setDelegate:(id<TCPServerDelegate>)delegate
{
	_delegate = delegate;
	
	SET_DELEGATE_METHOD_BIT(0, serverDidStart:);
	SET_DELEGATE_METHOD_BIT(1, serverDidEnableBonjour:);
	SET_DELEGATE_METHOD_BIT(2, server:shouldAcceptConnectionFromAddress:);
	SET_DELEGATE_METHOD_BIT(3, server:didOpenConnection:);
	SET_DELEGATE_METHOD_BIT(4, server:didCloseConnection:);
	SET_DELEGATE_METHOD_BIT(5, serverWillDisableBonjour:);
	SET_DELEGATE_METHOD_BIT(6, serverWillStop:);
}

- (BOOL) startUsingRunLoop:(NSRunLoop*)runLoop
{
	if(![super startUsingRunLoop:runLoop])
	return NO;
	
	if(TEST_DELEGATE_METHOD_BIT(0))
	[_delegate serverDidStart:self];
	
	return YES;
}

- (BOOL) enableBonjourWithDomain:(NSString*)domain applicationProtocol:(NSString*)protocol name:(NSString*)name
{
	if(![super enableBonjourWithDomain:domain applicationProtocol:protocol name:name])
	return NO;
	
	if(TEST_DELEGATE_METHOD_BIT(1))
	[_delegate serverDidEnableBonjour:self];
	
	return YES;
}

- (void) disableBonjour
{
	if([self isBonjourEnabled] && TEST_DELEGATE_METHOD_BIT(5))
	[_delegate serverWillDisableBonjour:self];
	
	[super disableBonjour];
}

- (void) stop
{
	NSArray*			connections;
	TCPConnection*		connection;
	
	if([self isRunning] && TEST_DELEGATE_METHOD_BIT(6))
	[_delegate serverWillStop:self];
	
	[super stop];
	
	//NOTE: To avoid dead-locks in the connection threads, we need to work on a copy
	connections = [self allConnections];
	for(connection in connections)
	[connection invalidate];
}

- (NSArray*) allConnections
{
	NSArray*				connections;
	
	pthread_mutex_lock(&_connectionsMutex);
	connections = [_connections allObjects];
	pthread_mutex_unlock(&_connectionsMutex);
	
	return connections;
}

- (void) _addConnection:(TCPServerConnection*)connection
{
	pthread_mutex_lock(&_connectionsMutex);
	[_connections addObject:connection];
	[connection _setServer:self];
	pthread_mutex_unlock(&_connectionsMutex);
	
	if(TEST_DELEGATE_METHOD_BIT(3))
	[_delegate server:self didOpenConnection:connection];
}

- (void) _removeConnection:(TCPServerConnection*)connection
{
	if(TEST_DELEGATE_METHOD_BIT(4))
	[_delegate server:self didCloseConnection:connection];
	
	pthread_mutex_lock(&_connectionsMutex);
	[connection _setServer:nil];
	[_connections removeObject:connection];
	pthread_mutex_unlock(&_connectionsMutex);
}

- (void) _connectionThread:(NSNumber*)socketNumber
{
	NSAutoreleasePool*			pool = [NSAutoreleasePool new];
	ObserverData				data = {0, nil};
	CFRunLoopObserverContext	context = {0, &data, NULL, NULL, NULL};
	TCPServerConnection*		connection;
	CFRunLoopObserverRef		observerRef;
	
	connection = [[[[self class] connectionClass] alloc] initWithSocketHandle:[socketNumber intValue]];
	if(connection) {
		[self _addConnection:connection];
		
		observerRef = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopEntry | kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting | kCFRunLoopExit, true, 0, _ObserverCallBack, &context);
		CFRunLoopAddObserver(CFRunLoopGetCurrent(), observerRef, kCFRunLoopCommonModes);
		CFRunLoopRun();
		CFRunLoopObserverInvalidate(observerRef);
		CFRelease(observerRef);
		[data.pool drain];
		
		[self _removeConnection:connection];
		[connection release];
	}
	else
	REPORT_ERROR(@"Failed creating TCPServerConnection for socket #%i", [socketNumber intValue]);
	
	[pool drain];
}

- (void) handleNewConnectionWithSocket:(NSSocketNativeHandle)socket fromRemoteAddress:(const struct sockaddr*)address
{
	TCPServerConnection*		connection;
	
	if(!TEST_DELEGATE_METHOD_BIT(2) || [_delegate server:self shouldAcceptConnectionFromAddress:address]) {
		if([[self class] useConnectionThreads])
		[NSThread detachNewThreadSelector:@selector(_connectionThread:) toTarget:self withObject:[NSNumber numberWithInt:socket]];
		else {
			connection = [[[[self class] connectionClass] alloc] initWithSocketHandle:socket];
			if(connection) {
				[self _addConnection:connection];
				[connection release];
			}
			else
			REPORT_ERROR(@"Failed creating TCPServerConnection for socket #%i", socket);
		}
	}
	else
	close(socket);
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | running = %i | local address = %@ | %i connections>", [self class], (long)self, [self isRunning], [self localAddress], [_connections count]];
}

@end
