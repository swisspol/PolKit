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

#import "NetServiceBrowser.h"
#import "Networking_Internal.h"

//CLASS IMPLEMENTATION:

@implementation NetServiceBrowser

static void _BrowserCallBack(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService, CFStreamError* error, void* info)
{
	NSAutoreleasePool*		pool = [NSAutoreleasePool new];
	NetServiceBrowser*		self = (NetServiceBrowser*)info;
	
	if(!(flags & kCFNetServiceFlagIsDomain)) {
		if(flags & kCFNetServiceFlagRemove) {
			if(TEST_DELEGATE_METHOD_BIT(2))
			[self->_delegate browser:self didRemoveService:(CFNetServiceRef)domainOrService];
		}
		else {
			if(TEST_DELEGATE_METHOD_BIT(1))
			[self->_delegate browser:self didAddService:(CFNetServiceRef)domainOrService];
		}
	}
	
	[pool release];
}

@synthesize delegate=_delegate, running=_running;

- (id) initWithDomain:(NSString*)domain type:(NSString*)type
{
	if(![domain length])
	domain = @""; //NOTE: Equivalent to "local."
	
	if((self = [super init])) {
		_domain = [domain copy];
		_type = [type copy];
	}
	
	return self;
}

- (id) initTCPBrowserWithDomain:(NSString*)domain applicationProtocol:(NSString*)protocol
{
	return [self initWithDomain:domain type:_MakeServiceType(protocol, @"tcp")];
}

- (id) initUDPBrowserWithDomain:(NSString*)domain applicationProtocol:(NSString*)protocol
{
	return [self initWithDomain:domain type:_MakeServiceType(protocol, @"udp")];
}

- (void) dealloc
{
	[self stop];
	
	[_domain release];
	[_type release];

	[super dealloc];
}

- (void) setDelegate:(id<NetServiceBrowserDelegate>)delegate
{
	_delegate = delegate;
	
	SET_DELEGATE_METHOD_BIT(0, browserDidStart:);
	SET_DELEGATE_METHOD_BIT(1, browser:didAddService:);
	SET_DELEGATE_METHOD_BIT(2, browser:didRemoveService:);
	SET_DELEGATE_METHOD_BIT(3, browserWillStop:);
}

- (BOOL) startUsingRunLoop:(NSRunLoop*)runLoop
{
    CFNetServiceClientContext	context = {0, self, NULL, NULL, NULL};
	
	if(_runLoop)
	return NO;
	_runLoop = [runLoop getCFRunLoop];
	if(!_runLoop)
	return NO;
	CFRetain(_runLoop);
	
	_netBrowser = CFNetServiceBrowserCreate(kCFAllocatorDefault, _BrowserCallBack, &context);
	if(_netBrowser == NULL) {
		[self stop];
		return NO;
	}
	CFNetServiceBrowserScheduleWithRunLoop(_netBrowser, _runLoop, kCFRunLoopCommonModes);
	
	if(!CFNetServiceBrowserSearchForServices(_netBrowser, (CFStringRef)_domain, (CFStringRef)_type, NULL)) {
		[self stop];
		return NO;
	}
	
	_running = YES;
	if(TEST_DELEGATE_METHOD_BIT(0))
	[_delegate browserDidStart:self];
	
	return YES;
}

- (void) stop
{
	if(_running) {
		if(TEST_DELEGATE_METHOD_BIT(3))
		[_delegate browserWillStop:self];
		_running = NO;
	}
	
	if(_netBrowser) {
		CFNetServiceBrowserInvalidate(_netBrowser);
		CFNetServiceBrowserUnscheduleFromRunLoop(_netBrowser, _runLoop, kCFRunLoopCommonModes);
		CFRelease(_netBrowser);
		_netBrowser = NULL;
	}
	if(_runLoop) {
		CFRelease(_runLoop);
		_runLoop = NULL;
	}
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = 0x%08X | running = %i>", [self class], (long)self, [self isRunning]];
}

@end
