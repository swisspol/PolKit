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

#import <SystemConfiguration/SystemConfiguration.h>

#import "NetworkConfiguration.h"

NSString* NetworkConfigurationDidChangeNotification = @"NetworkConfigurationDidChangeNotification";

static void _DynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void* info)
{
	NSAutoreleasePool*					localPool = [NSAutoreleasePool new];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:NetworkConfigurationDidChangeNotification object:(id)info];
	
	[localPool drain];
}

@implementation NetworkConfiguration

+ (NetworkConfiguration*) sharedNetworkConfiguration
{
	static NetworkConfiguration*		networkConfiguration = nil;
	
	if(networkConfiguration == nil)
	networkConfiguration = [NetworkConfiguration new];
	
	return networkConfiguration;
}

- (id) init
{
	SCDynamicStoreContext				context = {0, self, NULL, NULL, NULL};
	
	if((self = [super init])) {
		_dynamicStore = (void*)SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("net.pol-online.polkit"), _DynamicStoreCallBack, &context);
		if(_dynamicStore == NULL) {
			NSLog(@"%s: SCDynamicStoreCreate() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
			[self release];
			return nil;
		}
		
		if(SCDynamicStoreSetNotificationKeys(_dynamicStore, NULL, (CFArrayRef)[NSArray arrayWithObject:@".*/Network/.*"])) {
			_runLoopSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, _dynamicStore, 0);
			if(_runLoopSource)
			CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
			else
			NSLog(@"%s: SCDynamicStoreCreateRunLoopSource() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
		}
		else
		NSLog(@"%s: SCDynamicStoreSetNotificationKeys() failed with error \"%s\"", __FUNCTION__, SCErrorString(SCError()));
	}
	
	return self;
}

- (void) _cleanUp_NetworkConfiguration
{
	if(_runLoopSource) {
		CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
		CFRelease(_runLoopSource);
		SCDynamicStoreSetNotificationKeys(_dynamicStore, NULL, NULL);
	}
	if(_dynamicStore)
	CFRelease(_dynamicStore);
}

- (void) finalize
{
	[self _cleanUp_NetworkConfiguration];
	
	[super finalize];
}

- (void) dealloc
{
	[self _cleanUp_NetworkConfiguration];
	
	[super dealloc];
}

- (NSString*) locationName
{
	return [[NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, CFSTR("Setup:/"))) autorelease] objectForKey:(id)kSCPropUserDefinedName];
}

- (NSString*) dnsDomainName
{
	return [[NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, CFSTR("State:/Network/Global/DNS"))) autorelease] objectForKey:(id)kSCPropNetDNSDomainName];
}

- (NSArray*) dnsServerAddresses
{
	return [[NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, CFSTR("State:/Network/Global/DNS"))) autorelease] objectForKey:(id)kSCPropNetDNSServerAddresses];
}

- (NSArray*) networkAddresses
{
	NSArray*						list = [NSMakeCollectable(SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR("State:/Network/Service/.*/IPv4"))) autorelease];
	NSMutableArray*					array = [NSMutableArray array];
	NSString*						key;
	
	for(key in list)
	[array addObjectsFromArray:[[NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)key)) autorelease] objectForKey:(id)kSCPropNetIPv4Addresses]];
	
	return array;
}

- (NSDictionary*) _airportInfo
{
	NSArray*						list = [NSMakeCollectable(SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR("State:/Network/Interface/.*/AirPort"))) autorelease];
	
	return ([list count] ? [NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)[list objectAtIndex:0])) autorelease] : nil);
}

- (NSString*) airportNetworkName
{
	return [[self _airportInfo] objectForKey:@"SSID_STR"];
}

- (NSData*) airportNetworkSSID
{
	return [[self _airportInfo] objectForKey:@"BSSID"];
}

- (NSString*) description
{
	NSArray*						list = [NSMakeCollectable(SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR(".*/Network/.*"))) autorelease];
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	NSString*						key;
	
	for(key in list)
	[dictionary setValue:[NSMakeCollectable(SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)key)) autorelease] forKey:key];
	
	return [dictionary description];
}

- (NSDictionary*) allInterfaces
{
	NSArray*						list = [NSMakeCollectable(SCDynamicStoreCopyKeyList(_dynamicStore, CFSTR("Setup:/Network/Service/.*/Interface"))) autorelease];
	NSMutableDictionary*			dictionary = [NSMutableDictionary dictionary];
	NSString*						key;
	CFDictionaryRef					info;
	CFDictionaryRef					subInfo;
	BOOL							active;
	
	for(key in list) {
		info = SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)key);
		if(info) {
			if(CFDictionaryContainsKey(info, kSCPropUserDefinedName) && CFDictionaryContainsKey(info, kSCPropNetInterfaceDeviceName)) {
				subInfo = SCDynamicStoreCopyValue(_dynamicStore, (CFStringRef)[NSString stringWithFormat:@"State:/Network/Interface/%@/Link", CFDictionaryGetValue(info, kSCPropNetInterfaceDeviceName)]);
				if(subInfo) {
					active = [[(NSDictionary*)subInfo objectForKey:(id)kSCPropNetLinkActive] boolValue];
					CFRelease(subInfo);
				}
				else
				active = NO;
				[dictionary setObject:[NSNumber numberWithBool:active] forKey:(id)CFDictionaryGetValue(info, kSCPropUserDefinedName)];
			}
			CFRelease(info);
		}
	}
	
	return dictionary;
}

@end
