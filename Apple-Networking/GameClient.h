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

#import <Foundation/Foundation.h>

#import "GamePeer.h"

//CLASSES:

@class GameClient, NetServiceBrowser;

//PROTOCOLS:

@protocol GameClientDelegate <NSObject>
@optional
- (void) gameClientDidStartDiscoveringServers:(GameClient*)client;
- (void) gameClientDidUpdateOnlineServers:(GameClient*)client;
- (void) gameClientWillStopDiscoveringServers:(GameClient*)client;

- (void) gameClient:(GameClient*)client didFailConnectingToServer:(GamePeer*)server;
- (void) gameClient:(GameClient*)client didConnectToServer:(GamePeer*)server;
- (void) gameClient:(GameClient*)client didReceiveData:(NSData*)data fromServer:(GamePeer*)server immediate:(BOOL)immediate; //UDP delivery was used instead of TCP if "immediate" is YES
- (void) gameClient:(GameClient*)client didDisconnectFromServer:(GamePeer*)server;
@end

//CLASS INTERFACES:

/*
This class implements the client side of a multiplayer game.
It can be connected to one or more servers which are represented as instances of the GamePeer class.
You can then communicate with the servers using either TCP (for reliability) or UDP (for speed) protocols.
Servers can be automatically found on the local network using Bonjour.
*/
@interface GameClient : NSObject
{
@private
	NSString*					_name;
	id							_plist;
	id<GameClientDelegate>		_delegate;
	NSUInteger					_delegateMethods;
	NSMutableSet*				_connectingServers;
	NSMutableSet*				_connectedServers;
	
	CFMutableDictionaryRef		_onlineServers;
	NetServiceBrowser*			_browser;
}
+ (GamePeer*) serverWithAddress:(NSString*)address; //For instance: @"games.apple.com:123"
+ (GamePeer*) serverWithIPv4Address:(UInt32)address port:(UInt16)port; //The "address" is assumed to be in host-endian

- (id) initWithName:(NSString*)name infoPlist:(id)plist; //The "name" and "plist" can be "nil"
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) id infoPlist;

@property(nonatomic, assign) id<GameClientDelegate> delegate;

- (BOOL) startDiscoveringServersWithIdentifier:(NSString*)identifier; //The "identifier" must be unique to your game
@property(nonatomic, readonly, getter=isDiscoveringServers) BOOL discoveringServers;
@property(nonatomic, readonly) NSArray* onlineServers; //Returns nil when not discovering servers
- (void) stopDiscoveringServers;

- (BOOL) connectToServer:(GamePeer*)server;
@property(nonatomic, readonly) NSArray* connectingServers;
@property(nonatomic, readonly) NSArray* connectedServers;
- (void) disconnectFromServer:(GamePeer*)server;

- (NSTimeInterval) measureRoundTripLatencyToServer:(GamePeer*)server; //Returns < 0.0 on error
- (BOOL) sendData:(NSData*)data toServer:(GamePeer*)server immediate:(BOOL)immediate; //UDP will be used instead of TCP if "immediate" is YES
@end
