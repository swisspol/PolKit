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

#import "GameServer.h"
#import "TCPServer.h"
#import "UDPSocket.h"
#import "NetUtilities.h"
#import "Game_Internal.h"

//CLASS INTERFACES:

@interface GameServer (Internal) <GamePeerDelegate, TCPServerDelegate, UDPSocketDelegate>
@end

//CLASS IMPLEMENTATIONS:

@implementation GameServer

@synthesize delegate=_delegate, name=_name, infoPlist=_plist, advertising=_advertising;

- (id) init
{
	return [self initWithName:nil infoPlist:nil port:0];
}

- (id) initWithName:(NSString*)name infoPlist:(id)plist port:(UInt16)port
{
	if(![name length])
	name = HostGetName();
	
	if((self = [super init])) {
		_name = [name copy];
		_plist = [plist retain];
		_activeClients = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		_connectedClients = [NSMutableSet new];
		
		_server = [[TCPServer alloc] initWithPort:port];
		[_server setDelegate:self];
		if(![_server startUsingRunLoop:[NSRunLoop currentRunLoop]]) {
			[self release];
			return nil;
		}
		
		_socket = [[UDPSocket alloc] initWithPort:[_server localPort]];
		[_socket setDelegate:self];
		if(_socket == nil) {
			[self release];
			return nil;
		}
	}
	
	return self;
}

- (void) dealloc
{
	GamePeer*			peer;
	
	[self stopAdvertisingToClients];
	
	[_socket setDelegate:nil];
	[_socket release];
	
	[_server stop];
	[_server setDelegate:nil];
	[_server release];
	
	for(peer in _connectedClients) {
		[peer setDelegate:nil];
		[peer disconnect];
	}
	[_connectedClients release];
	
	if(_activeClients)
	CFRelease(_activeClients);
	
	[_plist release];
	[_name release];
	
	[super dealloc];
}

- (void) setDelegate:(id<GameServerDelegate>)delegate
{
	_delegate = delegate;
	
	SET_DELEGATE_METHOD_BIT(0, gameServerDidStartAdvertisingToClients:);
	SET_DELEGATE_METHOD_BIT(1, gameServerWillStopAdvertisingToClients:);
	SET_DELEGATE_METHOD_BIT(2, gameServer:shouldAllowConnectionToClient:);
	SET_DELEGATE_METHOD_BIT(3, gameServer:didFailConnectingToClient:);
	SET_DELEGATE_METHOD_BIT(4, gameServer:didConnectToClient:);
	SET_DELEGATE_METHOD_BIT(5, gameServer:didReceiveData:fromClient:immediate:);
	SET_DELEGATE_METHOD_BIT(6, gameServer:didDisconnectFromClient:);
}

- (UInt16) port
{
	return [_server localPort];
}

- (id) _downloadPlistWithRequest:(NSURLRequest*)request
{
	NSError*					error = nil;
	NSData*						data;
	NSURLResponse*				response;
	
	data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	if(data && [response isKindOfClass:[NSHTTPURLResponse class]] && ([(NSHTTPURLResponse*)response statusCode] == 200))
	return [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
	else
	REPORT_ERROR(@"Failed communicating with tracker at %@:\n%@", request, error);
	
	return nil;
}

- (BOOL) startAdvertisingToClientsWithIdentifier:(NSString*)identifier
{
	NSString*					uniqueName = [NSString stringWithFormat:@"%@:%@", HostGetUniqueID(), _name];
	
	if(_advertising || ![identifier length])
	return NO;
	
	if(![_server enableBonjourWithDomain:nil applicationProtocol:_ApplicationProtocolFromGameIdentifier(identifier) name:uniqueName])
	return NO;
	
	_advertising = YES;
	
	if(TEST_DELEGATE_METHOD_BIT(0))
	[_delegate gameServerDidStartAdvertisingToClients:self];
	
	return YES;
}

- (void) stopAdvertisingToClients
{
	if(_advertising) {
		if(TEST_DELEGATE_METHOD_BIT(1))
		[_delegate gameServerWillStopAdvertisingToClients:self];
		
		[_server disableBonjour];
		
		_advertising = NO;
	}
}

- (NSArray*) connectedClients
{
	return [_connectedClients allObjects];
}

- (void) disconnectFromClient:(GamePeer*)client
{
	if(client && [_connectedClients containsObject:client])
	[client disconnect];
}

- (NSTimeInterval) measureRoundTripLatencyToClient:(GamePeer*)client
{
	return (client && [_connectedClients containsObject:client] ? [client measureRoundTripLatency] : -1.0);
}

- (BOOL) sendDataToAllClients:(NSData*)data immediate:(BOOL)immediate
{
	GamePeer*			peer;
	BOOL				success = YES;
	
	for(peer in _connectedClients) {
		if(immediate) {
			if(![_socket sendData:data toRemoteAddress:[peer socketAddress]])
			success = NO;
		}
		else {
			if(![peer sendData:data immediate:NO])
			success = NO;
		}
	}
	
	return success;
}

- (BOOL) sendData:(NSData*)data toClient:(GamePeer*)client immediate:(BOOL)immediate
{
	if(!client || ![_connectedClients containsObject:client])
	return NO;
	
	if(immediate)
	return [_socket sendData:data toRemoteAddress:[client socketAddress]];
	else
	return [client sendData:data immediate:NO];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | advertising = %i | connected clients = %i>", [self class], (long)self, [self isAdvertising], [[self connectedClients] count]];
}

@end

@implementation GameServer (TCPServerDelegate)

- (void) server:(TCPServer*)server didOpenConnection:(TCPServerConnection*)connection
{
	GamePeer*			peer;
	
	peer = [[GamePeer alloc] initWithConnection:connection];
	if(peer) {
		[peer setDelegate:self];
		CFDictionaryAddValue(_activeClients, connection, peer);
		[peer release];
	}
	else {
		REPORT_ERROR(@"Failed creating GamePeer from %@", connection);
		[connection invalidate];
	}
}

- (void) server:(TCPServer*)server didCloseConnection:(TCPServerConnection*)connection
{
	GamePeer*			peer = (GamePeer*)CFDictionaryGetValue(_activeClients, connection);
	
	[peer retain];
	CFDictionaryRemoveValue(_activeClients, connection);
	[peer autorelease]; //NOTE: We need the GamePeer instance not to be de-alloced until -[GamePeer disconnect] has completed
}

@end

@implementation GameServer (GamePeerDelegate)

- (NSString*) gamePeerWillSendName:(GamePeer*)peer
{
	return _name;
}

- (id) gamePeerWillSendInfoPlist:(GamePeer*)peer
{
	return _plist;
}

- (void) gamePeerDidFailConnecting:(GamePeer*)peer
{
	[peer retain];
	
	if(TEST_DELEGATE_METHOD_BIT(3))
	[_delegate gameServer:self didFailConnectingToClient:peer];
	
	[peer setDelegate:nil];
	[peer release];
}

- (void) gamePeerDidConnect:(GamePeer*)peer
{
	if(!TEST_DELEGATE_METHOD_BIT(2) || [_delegate gameServer:self shouldAllowConnectionToClient:peer]) {
		[_connectedClients addObject:peer];
		
		if(TEST_DELEGATE_METHOD_BIT(4))
		[_delegate gameServer:self didConnectToClient:peer];
	}
	else {
		[peer setDelegate:nil];
		
		[peer disconnect];
	}
}

- (void) gamePeerDidDisconnect:(GamePeer*)peer
{
	if([_connectedClients containsObject:peer]) {
		[peer retain];
		
		[_connectedClients removeObject:peer];
		
		if(TEST_DELEGATE_METHOD_BIT(6))
		[_delegate gameServer:self didDisconnectFromClient:peer];
		
		[peer setDelegate:nil];
		[peer release];
	}
}

- (void) gamePeer:(GamePeer*)peer didReceiveData:(NSData*)data immediate:(BOOL)immediate
{
	if(TEST_DELEGATE_METHOD_BIT(5))
	[_delegate gameServer:self didReceiveData:data fromClient:peer immediate:NO];
}

@end

@implementation GameServer (UDPSocketDelegate)

- (void) socket:(UDPSocket*)socket didReceiveData:(NSData*)data fromRemoteAddress:(const struct sockaddr*)address
{
	GamePeer*				peer;
	const struct sockaddr*	peerAddress;
	
	if(TEST_DELEGATE_METHOD_BIT(5)) {
		for(peer in _connectedClients) {
			peerAddress = [peer socketAddress];
			if((address->sa_family == peerAddress->sa_family) && (address->sa_len == peerAddress->sa_len) && (bcmp(address, peerAddress, address->sa_len) == 0)) {
				[_delegate gameServer:self didReceiveData:data fromClient:peer immediate:YES];
				return;
			}
		}
		
		REPORT_ERROR(@"Received UDP data from unknown client at \"%@\"", IPAddressToString(address, NO, NO));
	}
}

@end
