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

#import <Security/Security.h>

#import "Keychain.h"
#import "NSURL+Parameters.h"

@implementation Keychain

+ (Keychain*) sharedKeychain
{
	static Keychain*		keychain = nil;
	
	if(keychain == nil)
	keychain = [Keychain new];
	
	return keychain;
}

- (NSString*) genericPasswordForService:(NSString*)service account:(NSString*)account
{
	const char*			utf8Service = [service UTF8String];
	const char*			utf8Account = [account UTF8String];
	NSString*			password = nil;
	UInt32				length;
	void*				data;
	OSStatus			error;
	
	error = SecKeychainFindGenericPassword(NULL, strlen(utf8Service), utf8Service, strlen(utf8Account), utf8Account, &length, &data, NULL);
	if(error == noErr) {
		password = [[[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding] autorelease];
		SecKeychainItemFreeContent(NULL, data);
	}
	else if(error != errSecItemNotFound)
	NSLog(@"%s: Failed retrieving generic password for \"%@\" @ \"%@\" (error %i: \"%@\")", __FUNCTION__, service, account, error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
	
	return password;
}

- (BOOL) addGenericPassword:(NSString*)password forService:(NSString*)service account:(NSString*)account
{
	const char*			utf8Service = [service UTF8String];
	const char*			utf8Account = [account UTF8String];
	NSData*				data = [password dataUsingEncoding:NSUTF8StringEncoding];
	OSStatus			error;
	
	if(![data length])
	return NO;
	
	error = SecKeychainAddGenericPassword(NULL, strlen(utf8Service), utf8Service, strlen(utf8Account), utf8Account, [data length], [data bytes], NULL);
	if((error != noErr) && (error != errSecDuplicateItem)) {
		NSLog(@"%s: Failed adding generic password for \"%@\" @ \"%@\" (error %i: \"%@\")", __FUNCTION__, service, account, error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
		return NO;
	}
	
	return YES;
}

- (BOOL) removeGenericPasswordForService:(NSString*)service account:(NSString*)account
{
	const char*			utf8Service = [service UTF8String];
	const char*			utf8Account = [account UTF8String];
	OSStatus			error;
	SecKeychainItemRef	item;
	
	error = SecKeychainFindGenericPassword(NULL, strlen(utf8Service), utf8Service, strlen(utf8Account), utf8Account, NULL, NULL, &item);
	if(error == noErr)
	error = SecKeychainItemDelete(item); //FIXME: Should we call CFRelease() on the item as well?
	if((error != noErr) && (error != errSecItemNotFound)) {
		NSLog(@"%s: Failed deleting generic password for \"%@\" @ \"%@\" (error %i: \"%@\")", __FUNCTION__, service, account, error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
		return NO;
	}
	
	return YES;
}

static SecProtocolType _ProtocolFromURLScheme(NSString* scheme)
{
	scheme = [scheme lowercaseString];
	
	if([scheme isEqualToString:@"afp"])
	return kSecProtocolTypeAFP;
	else if([scheme isEqualToString:@"smb"])
	return kSecProtocolTypeSMB;
	else if([scheme isEqualToString:@"http"])
	return kSecProtocolTypeHTTP;
	else if([scheme isEqualToString:@"https"])
	return kSecProtocolTypeHTTPS;
	else if([scheme isEqualToString:@"ftp"])
	return kSecProtocolTypeFTP;
	else if([scheme isEqualToString:@"ftps"])
	return kSecProtocolTypeFTPS;
	else if([scheme isEqualToString:@"ssh"])
	return kSecProtocolTypeSSH;
	
	return kSecProtocolTypeAny;
}

- (BOOL) setPasswordForURL:(NSURL*)url
{
	if([[url password] length])
	return [self addPasswordForURL:url];
	else
	return [self removePasswordForURL:url];
}

- (BOOL) addPasswordForURL:(NSURL*)url
{
	const char*			utf8Host = [[url host] UTF8String];
	const char*			utf8Account = [[url user] UTF8String];
	const char*			utf8Path = [[url path] UTF8String];
	const char*			utf8Password = [[url passwordByReplacingPercentEscapes] UTF8String];
	UInt16				port = [[url port] unsignedShortValue];
	SecProtocolType		protocol = _ProtocolFromURLScheme([url scheme]);
	OSStatus			error;
	
	if(!utf8Account || !utf8Password)
	return NO;
	
	error = SecKeychainAddInternetPassword(NULL, strlen(utf8Host), utf8Host, 0, NULL, strlen(utf8Account), utf8Account, strlen(utf8Path), utf8Path, port, protocol, kSecAuthenticationTypeDefault, strlen(utf8Password), utf8Password, NULL);
	if((error != noErr) && (error != errSecDuplicateItem)) {
		NSLog(@"%s: Failed adding Internet password for \"%@@%@%@\" (error %i: \"%@\")", __FUNCTION__, [url user], [url host], [url path], error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
		return NO;
	}
	
	return YES;
}

- (BOOL) removePasswordForURL:(NSURL*)url
{
	const char*			utf8Host = [[url host] UTF8String];
	const char*			utf8Account = [[url user] UTF8String];
	const char*			utf8Path = [[url path] UTF8String];
	UInt16				port = [[url port] unsignedShortValue];
	SecProtocolType		protocol = _ProtocolFromURLScheme([url scheme]);
	OSStatus			error;
	SecKeychainItemRef	item;
	
	if(!utf8Account)
	return NO;
		
	error = SecKeychainFindInternetPassword(NULL, strlen(utf8Host), utf8Host, 0, NULL, strlen(utf8Account), utf8Account, strlen(utf8Path), utf8Path, port, protocol, kSecAuthenticationTypeAny, NULL, NULL, &item);
	if(error == noErr)
	error = SecKeychainItemDelete(item); //FIXME: Should we call CFRelease() on the item as well?
	if((error != noErr) && (error != errSecItemNotFound)) {
		NSLog(@"%s: Failed deleting Internet password for \"%@@%@%@\" (error %i: \"%@\")", __FUNCTION__, [url user], [url host], [url path], error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
		return NO;
	}
	
	return YES;
}

- (NSURL*) URLWithPasswordForURL:(NSURL*)url
{
	const char*			utf8Host = [[url host] UTF8String];
	const char*			utf8Account = [[url user] UTF8String];
	const char*			utf8Path = [[url path] UTF8String];
	const char*			utf8Password = [[url passwordByReplacingPercentEscapes] UTF8String];
	UInt16				port = [[url port] unsignedShortValue];
	SecProtocolType		protocol = _ProtocolFromURLScheme([url scheme]);
	UInt32				length;
	void*				data;
	OSStatus			error;
	NSString*			password;
	
	if(!utf8Account || utf8Password)
	return url;
	
	error = SecKeychainFindInternetPassword(NULL, strlen(utf8Host), utf8Host, 0, NULL, strlen(utf8Account), utf8Account, strlen(utf8Path), utf8Path, port, protocol, kSecAuthenticationTypeAny, &length, &data, NULL);
	if(error == noErr) {
		password = [[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding];
		url = [NSURL URLWithScheme:[url scheme] user:[url user] password:password host:[url host] port:port path:[url path]];
		[password release];
		SecKeychainItemFreeContent(NULL, data);
	}
	else if(error != errSecItemNotFound)
	NSLog(@"%s: Failed retrieving Internet password for \"%@@%@%@\" (error %i: \"%@\")", __FUNCTION__, [url user], [url host], [url path], error, [NSMakeCollectable(SecCopyErrorMessageString(error, NULL)) autorelease]);
	
	return url;
}

@end
