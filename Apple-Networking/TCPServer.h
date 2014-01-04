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

#import "TCPService.h"
#import "TCPConnection.h"

//CLASSES:

@class TCPServer, TCPServerConnection;

//PROTOCOLS:

@protocol TCPServerDelegate <NSObject>
@optional
- (void) serverDidStart:(TCPServer*)server;
- (void) serverDidEnableBonjour:(TCPServer*)server;

- (BOOL) server:(TCPServer*)server shouldAcceptConnectionFromAddress:(const struct sockaddr*)address;
- (void) server:(TCPServer*)server didOpenConnection:(TCPServerConnection*)connection; //From this method, you typically set the delegate of the connection to be able to send & receive data through it
- (void) server:(TCPServer*)server didCloseConnection:(TCPServerConnection*)connection;

- (void) serverWillDisableBonjour:(TCPServer*)server;
- (void) serverWillStop:(TCPServer*)server;
@end

//CLASS INTERFACES:

/*
This subclass of TCPService implements a full TCP server which automatically maintains the list of active connections.
See TCPService.h for other methods.
*/
@interface TCPServer : TCPService
{
@private
	pthread_mutex_t				_connectionsMutex;
	NSMutableSet*				_connections;
	id<TCPServerDelegate>		_delegate;
	NSUInteger					_delegateMethods;
}
+ (BOOL) useConnectionThreads; //Use a separate thread for each connection - NO by default
+ (Class) connectionClass; //Must be a subclass of "TCPServerConnection"

@property(nonatomic, readonly) NSArray* allConnections;

@property(nonatomic, assign) id<TCPServerDelegate> delegate;
@end

/*
Subclass of TCPConnection used by TCPServer for its connections.
*/
@interface TCPServerConnection : TCPConnection
{
@private
	TCPServer*			_server; //Not retained
}
@property(nonatomic, readonly) TCPServer* server;
@end
