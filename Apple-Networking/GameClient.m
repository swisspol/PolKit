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

#import <netinet/in.h>

#import "GameClient.h"
#import "NetServiceBrowser.h"
#import "NetUtilities.h"
#import "Game_Internal.h"

//CLASS INTERFACE:

@interface GameClient (Internal) <GamePeerDelegate, NetServiceBrowserDelegate>
@end

//FUNCTIONS:

static void _DictionaryApplierFunction(const void* key, const void* value, void* context)
{
	GamePeer*				server = (GamePeer*)value;
	NSMutableArray*			array = (NSMutableArray*)context;
	GamePeer*				peer;
	
	for(peer in array) {
		if(![[peer uniqueID] isEqualToString:[server uniqueID]])
		continue;
		
		if(([peer isConnecting] || [peer isConnected]) && ([server isConnecting] || [server isConnected]))
		[NSException raise:NSInternalInconsistencyException format:@""];
		if([peer isService] == [server isService])
		[NSException raise:NSInternalInconsistencyException format:@""];
		
		if([server isConnecting] || [server isConnected] || [server isService]) {
			[array removeObject:peer];
			break;
		}
		else
		return;
	}
	
	[array addObject:server];
}

//CLASS IMPLEMENTATIONS:

@implementation GameClient

@synthesize delegate=_delegate, name=_name, infoPlist=_plist;

+ (GamePeer*) serverWithAddress:(NSString*)address
{
	return [[[GamePeer alloc] initWithName:nil address:IPAddressFromString(address)] autorelease];
}

+ (GamePeer*) serverWithIPv4Address:(UInt32)address port:(UInt16)port
{
	struct sockaddr_in		ipAddress;
	
	bzero(&ipAddress, sizeof(ipAddress));
	ipAddress.sin_len = sizeof(ipAddress);
	ipAddress.sin_family = AF_INET;
	ipAddress.sin_port = htons(port);
	ipAddress.sin_addr.s_addr = htonl(address);
	
	return [[[GamePeer alloc] initWithName:nil address:(struct sockaddr*)&ipAddress] autorelease];
}

- (NSArray*) connectingServers
{
	return [_connectingServers allObjects];
}

- (NSArray*) connectedServers
{
	return [_connectedServers allObjects];
}

- (id) init
{
	return [self initWithName:nil infoPlist:nil];
}

- (id) initWithName:(NSString*)name infoPlist:(id)plist
{
	if(![name length])
	name = HostGetName();
	
	if((self = [super init])) {
		_name = [name copy];
		_plist = [plist retain];
		_connectingServers = [NSMutableSet new];
		_connectedServers = [NSMutableSet new];
	}
	
	return self;
}

- (void) dealloc
{
	GamePeer*			peer;
	
	[self stopDiscoveringServers];
	
	for(peer in _connectingServers) {
		[peer setDelegate:nil];
		[peer disconnect];
	}
	[_connectingServers release];
	
	for(peer in _connectedServers) {
		[peer setDelegate:nil];
		[peer disconnect];
	}
	[_connectedServers release];
	
	[_plist release];
	
	[super dealloc];
}

- (void) setDelegate:(id<GameClientDelegate>)delegate
{
	_delegate = delegate;
	
	SET_DELEGATE_METHOD_BIT(0, gameClientDidStartDiscoveringServers:);
	SET_DELEGATE_METHOD_BIT(1, gameClientDidUpdateOnlineServers:);
	SET_DELEGATE_METHOD_BIT(2, gameClientWillStopDiscoveringServers:);
	SET_DELEGATE_METHOD_BIT(3, gameClient:didFailConnectingToServer:);
	SET_DELEGATE_METHOD_BIT(4, gameClient:didConnectToServer:);
	SET_DELEGATE_METHOD_BIT(5, gameClient:didReceiveData:fromServer:immediate:);
	SET_DELEGATE_METHOD_BIT(6, gameClient:didDisconnectFromServer:);
}

- (BOOL) startDiscoveringServersWithIdentifier:(NSString*)identifier
{
	if(_onlineServers || ![identifier length])
	return NO;
	
	_onlineServers = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	
	_browser = [[NetServiceBrowser alloc] initTCPBrowserWithDomain:nil applicationProtocol:_ApplicationProtocolFromGameIdentifier(identifier)];
	[_browser setDelegate:self];
	if(![_browser startUsingRunLoop:[NSRunLoop currentRunLoop]]) {
		[_browser release];
		_browser = nil;
		CFRelease(_onlineServers);
		_onlineServers = NULL;
		return NO;
	}
	
	if(TEST_DELEGATE_METHOD_BIT(0))
	[_delegate gameClientDidStartDiscoveringServers:self];
	
	return YES;
}

- (BOOL) isDiscoveringServers
{
	return (_onlineServers ? YES : NO);
}

- (NSArray*) onlineServers
{
	NSMutableArray*			array = nil;
	
	if(_onlineServers) {
		array = [NSMutableArray array];
		CFDictionaryApplyFunction(_onlineServers, _DictionaryApplierFunction, array);
	}
	
	return array;
}

- (void) stopDiscoveringServers
{
	if(_onlineServers) {
		if(TEST_DELEGATE_METHOD_BIT(2))
		[_delegate gameClientWillStopDiscoveringServers:self];
		
		[_browser stop];
		[_browser release];
		_browser = nil;
		
		CFRelease(_onlineServers);
		_onlineServers = NULL;
	}
}

- (BOOL) connectToServer:(GamePeer*)server
{
	if(!server || [server isConnected] || [server isConnecting])
	return NO;
	
	if(![server connect])
	return NO;
	
	[server setDelegate:self];
	[_connectingServers addObject:server];
	
	return YES;
}

- (void) disconnectFromServer:(GamePeer*)server
{
	if(server && ([_connectingServers containsObject:server] || [_connectedServers containsObject:server]))
	[server disconnect];
}

- (NSTimeInterval) measureRoundTripLatencyToServer:(GamePeer*)server
{
	return (server && [_connectedServers containsObject:server] ? [server measureRoundTripLatency] : -1.0);
}

- (BOOL) sendData:(NSData*)data toServer:(GamePeer*)server immediate:(BOOL)immediate
{
	if(!server || ![_connectedServers containsObject:server])
	return NO;
	
	return [server sendData:data immediate:immediate];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | discovering = %i | connected servers = %i>", [self class], (long)self, [self isDiscoveringServers], [[self connectedServers] count]];
}

@end

@implementation GameClient (GamePeerDelegate)

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
	
	[_connectingServers removeObject:peer];
	
	if(TEST_DELEGATE_METHOD_BIT(3))
	[_delegate gameClient:self didFailConnectingToServer:peer];
	
	[peer setDelegate:nil];
	[peer release];
}

- (void) gamePeerDidConnect:(GamePeer*)peer
{
	[_connectingServers removeObject:peer];
	[_connectedServers addObject:peer];
	
	if(TEST_DELEGATE_METHOD_BIT(4))
	[_delegate gameClient:self didConnectToServer:peer];
}

- (void) gamePeerDidDisconnect:(GamePeer*)peer
{
	[peer retain];
	
	if([_connectedServers containsObject:peer]) {
		[_connectedServers removeObject:peer];
		
		if(TEST_DELEGATE_METHOD_BIT(6))
		[_delegate gameClient:self didDisconnectFromServer:peer];
	}
	
	[peer setDelegate:nil];
	[peer release];
}

- (void) gamePeer:(GamePeer*)peer didReceiveData:(NSData*)data immediate:(BOOL)immediate
{
	if(TEST_DELEGATE_METHOD_BIT(5))
	[_delegate gameClient:self didReceiveData:data fromServer:peer immediate:immediate];
}

@end

@implementation GameClient (NetServiceBrowserDelegate)

- (void) browser:(NetServiceBrowser*)server didAddService:(CFNetServiceRef)service
{
	GamePeer*						peer;
	
	peer = [[GamePeer alloc] initWithCFNetService:service];
	if(peer) {
		CFDictionarySetValue(_onlineServers, service, peer);
		[peer release];
		
		if(TEST_DELEGATE_METHOD_BIT(1))
		[_delegate gameClientDidUpdateOnlineServers:self];
	}
	else
	REPORT_ERROR(@"Failed creating GamePeer from %@", [(id)CFCopyDescription(service) autorelease]);
}

- (void) browser:(NetServiceBrowser*)server didRemoveService:(CFNetServiceRef)service
{
	CFDictionaryRemoveValue(_onlineServers, service);
	
	if(TEST_DELEGATE_METHOD_BIT(1))
	[_delegate gameClientDidUpdateOnlineServers:self];
}

@end
