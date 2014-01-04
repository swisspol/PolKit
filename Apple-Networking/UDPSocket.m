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

#import <unistd.h>
#import <netinet/in.h>
#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#import <netinet6/in6.h>
#endif

#import "UDPSocket.h"
#import "NetUtilities.h"
#import "Networking_Internal.h"

//CLASS INTERFACES:

@interface UDPSocket (Internal)
- (CFSocketRef) _socket;
@end

//FUNCTIONS:

NSString* _MakeServiceType(NSString* applicationProtocol, NSString* transportProtocol)
{
	NSString*		type = nil;
	
	if([applicationProtocol length] && [transportProtocol length])
	type = [NSString stringWithFormat:@"_%@._%@.", applicationProtocol, transportProtocol];
	
	return type;
}

//CLASS IMPLEMENTATION:

@implementation UDPSocket

static void _SocketCallBack(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void* data, void *info)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	UDPSocket*				self = (UDPSocket*)info;
	
	if(TEST_DELEGATE_METHOD_BIT(3))
	[self->_delegate socket:self didReceiveData:(NSData*)data fromRemoteAddress:(struct sockaddr*)CFDataGetBytePtr(address)];
	
	[pool release];
}

@synthesize delegate=_delegate;

- (id) _initWithAddress:(const struct sockaddr*)address
{
	CFSocketContext			context = {0, self, NULL, NULL, NULL};
	int						value = 1;
	CFRunLoopSourceRef		source;
	struct ip_mreq			membership;
	socklen_t				length;
	struct sockaddr_in		multicastAddress;
	
	if(address == NULL) {
		[self release];
		return nil;
	}
	
	if((self = [super init])) {
		_socket = CFSocketCreate(kCFAllocatorDefault, address->sa_family, SOCK_DGRAM, IPPROTO_IP, kCFSocketDataCallBack, _SocketCallBack, &context);
		if(_socket == NULL) {
			[self release];
			return nil;
		}
		
		if((address->sa_family == AF_INET) && (((struct sockaddr_in*)address)->sin_addr.s_addr >= (224 << 24)) && (((struct sockaddr_in*)address)->sin_addr.s_addr < (240 << 24))) {
			bzero(&membership, sizeof(struct ip_mreq));
			membership.imr_multiaddr.s_addr = ((struct sockaddr_in*)address)->sin_addr.s_addr;
			membership.imr_interface.s_addr = htonl(INADDR_ANY);
			if(setsockopt(CFSocketGetNative(_socket), IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, sizeof(struct ip_mreq)) < 0) {
				[self release];
				return nil;
			}
			
			bcopy(address, &multicastAddress, sizeof(struct sockaddr));
			multicastAddress.sin_addr.s_addr = htonl(INADDR_ANY);
			address = (struct sockaddr*)&multicastAddress;
		}
		
		if(setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &value, sizeof(value)) || setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEPORT, &value, sizeof(value))) {
			[self release];
			return nil;
		}
		
		if(CFSocketSetAddress(_socket, (CFDataRef)[NSData dataWithBytes:(void*)address length:address->sa_len]) != kCFSocketSuccess) {
			[self release];
			return nil;
		}
		
		length = SOCK_MAXADDRLEN;
		_localAddress = malloc(length);
		if(getsockname(CFSocketGetNative(_socket), _localAddress, &length) < 0)
		[NSException raise:NSInternalInconsistencyException format:@"Unable to retrieve socket address"];
		
		_runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
		
		source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
		if(source == NULL) {
			[self release];
			return nil;
		}
		CFRunLoopAddSource(_runLoop, source, kCFRunLoopCommonModes);
		CFRelease(source);
	}
	
	return self;
}

- (id) initWithPort:(UInt16)port
{
	struct sockaddr_in		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin_len = sizeof(ipAddress);
	ipAddress.sin_family = AF_INET;
	ipAddress.sin_port = htons(port);
	ipAddress.sin_addr.s_addr = htonl(INADDR_ANY);
	
	return [self _initWithAddress:(struct sockaddr*)&ipAddress];
}

- (void) dealloc
{
	[self invalidate];
	
	if(_localAddress)
	free(_localAddress);
	
	[super dealloc];
}

- (void) setDelegate:(id<UDPSocketDelegate>)delegate
{
	_delegate = delegate;
	
	SET_DELEGATE_METHOD_BIT(0, socketDidEnableBonjour:);
	SET_DELEGATE_METHOD_BIT(1, socketWillDisableBonjour:);
	SET_DELEGATE_METHOD_BIT(2, socketDidInvalidate:);
	SET_DELEGATE_METHOD_BIT(3, socket:didReceiveData:fromRemoteAddress:);
}

- (BOOL) enableBonjourWithDomain:(NSString*)domain applicationProtocol:(NSString*)protocol name:(NSString*)name
{
	protocol = _MakeServiceType(protocol, @"udp");
	if(![domain length])
	domain = @""; //NOTE: Equivalent to "local."
	if(![name length])
	name = HostGetName();
	
	if(!protocol || _invalidating)
	return NO;
	
	_netService = CFNetServiceCreate(kCFAllocatorDefault, (CFStringRef)domain, (CFStringRef)protocol, (CFStringRef)name, [self localPort]);
	if(_netService == NULL)
	return NO;
	
	CFNetServiceScheduleWithRunLoop(_netService, _runLoop, kCFRunLoopCommonModes);
	if(!CFNetServiceRegisterWithOptions(_netService, 0, NULL)) {
		CFNetServiceCancel(_netService);
		CFNetServiceUnscheduleFromRunLoop(_netService, _runLoop, kCFRunLoopCommonModes);
		CFRelease(_netService);
		_netService = NULL;
		return NO;
	}
	
	if(TEST_DELEGATE_METHOD_BIT(0))
	[_delegate socketDidEnableBonjour:self];
	
	return YES;
}

- (BOOL) isBonjourEnabled
{
	return (_netService ? YES : NO);
}

- (void) disableBonjour
{
	if(_netService) {
		if(TEST_DELEGATE_METHOD_BIT(1))
		[_delegate socketWillDisableBonjour:self];
		
		CFNetServiceCancel(_netService);
		CFNetServiceUnscheduleFromRunLoop(_netService, _runLoop, kCFRunLoopCommonModes);
		CFRelease(_netService);
		_netService = NULL;
	}
}

#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR

/*
- (id) initWithPort:(UInt16)port
{
	struct sockaddr_in6		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin6_len = sizeof(ipAddress);
	ipAddress.sin6_family = AF_INET6;
	ipAddress.sin6_port = htons(port);
	bcopy(&in6addr_any, &ipAddress.sin6_addr, sizeof(struct in6_addr));
	
	return [self _initWithAddress:(struct sockaddr*)&ipAddress];
}
*/

#endif

- (BOOL) isValid
{
	return !_invalidating;
}

- (void) invalidate
{
	if(_invalidating == NO) {
		_invalidating = YES;
		
		[self disableBonjour];
		
		if(_runLoop) {
			CFRelease(_runLoop);
			_runLoop = NULL;
		}
		
		if(_socket) {
			CFSocketInvalidate(_socket); //NOTE: This also calls CFRunLoopSourceInvalidate()
			CFRelease(_socket);
			_socket = NULL;
		}
		
		if(TEST_DELEGATE_METHOD_BIT(2))
		[_delegate socketDidInvalidate:self];
	}
}

- (UInt16) localPort
{
	if(_localAddress)
	switch(_localAddress->sa_family) {
		case AF_INET: return ntohs(((struct sockaddr_in*)_localAddress)->sin_port);
#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
		case AF_INET6: return ntohs(((struct sockaddr_in6*)_localAddress)->sin6_port);
#endif
	}
	
	return 0;
}

- (UInt32) localIPv4Address
{
	return (_localAddress && (_localAddress->sa_family == AF_INET) ? ntohl(((struct sockaddr_in*)_localAddress)->sin_addr.s_addr) : 0);
}

- (NSString*) localAddress
{
	return (_localAddress ? IPAddressToString(_localAddress, NO, NO) : nil);
}

- (BOOL) sendData:(NSData*)data toRemoteAddress:(const struct sockaddr*)address
{
	return (address && data && _socket && (CFSocketSendData(_socket, (CFDataRef)[NSData dataWithBytes:(void*)address length:address->sa_len], (CFDataRef)data, 0.0) == kCFSocketSuccess) ? YES : NO);
}

- (BOOL) sendData:(NSData*)data toRemoteIPv4Address:(UInt32)address port:(UInt16)port
{
	struct sockaddr_in		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin_len = sizeof(ipAddress);
	ipAddress.sin_family = AF_INET;
	ipAddress.sin_port = htons(port);
	ipAddress.sin_addr.s_addr = htonl(address);
	
	return [self sendData:data toRemoteAddress:(struct sockaddr*)&ipAddress];
}

#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR

- (BOOL) sendData:(NSData*)data toRemoteIPv6Address:(const struct in6_addr*)address port:(UInt16)port
{
	struct sockaddr_in6		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin6_len = sizeof(ipAddress);
	ipAddress.sin6_family = AF_INET6;
	ipAddress.sin6_port = htons(port);
	bcopy(address, &ipAddress.sin6_addr, sizeof(struct in6_addr));
	
	return [self sendData:data toRemoteAddress:(struct sockaddr*)&ipAddress];
}

#endif

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | valid = %i | local address = %@>", [self class], (long)self, [self isValid], [self localAddress]];
}

- (CFSocketRef) _socket
{
	return _socket;
}

@end

@implementation UDPBroadcastSocket

- (id) initWithPort:(UInt16)port
{
	int					value = 1;
	
	if((self = [super initWithPort:port])) {
		if(setsockopt(CFSocketGetNative([self _socket]), SOL_SOCKET, SO_BROADCAST, &value, sizeof(value)) < 0) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (BOOL) sendData:(NSData*)data toPort:(UInt16)port
{
	return [super sendData:data toRemoteIPv4Address:INADDR_BROADCAST port:port];
}

- (BOOL) sendData:(NSData*)data toRemoteAddress:(const struct sockaddr*)address port:(UInt16)port
{
	return NO;
}

@end
