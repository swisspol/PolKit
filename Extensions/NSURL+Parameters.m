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

#import "NSURL+Parameters.h"

/* See http://www.faqs.org/rfcs/rfc1738.html */
#define ESCAPE_USER_PASSWORD(_STRING_) [NSMakeCollectable(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)_STRING_, NULL, CFSTR(":@/?"), kCFStringEncodingUTF8)) autorelease]
#define ESCAPE_STRING(_STRING_) [NSMakeCollectable(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)_STRING_, NULL, NULL, kCFStringEncodingUTF8)) autorelease]
#define UNESCAPE_STRING(_STRING_) [NSMakeCollectable(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)_STRING_, CFSTR(""), kCFStringEncodingUTF8)) autorelease]

@implementation NSURL (Parameters)

+ (NSURL*) URLWithScheme:(NSString*)scheme host:(NSString*)host path:(NSString*)path
{
	return [self URLWithScheme:scheme user:nil password:nil host:host port:0 path:path query:nil];
}

+ (NSURL*) URLWithScheme:(NSString*)scheme user:(NSString*)user password:(NSString*)password host:(NSString*)host port:(UInt16)port path:(NSString*)path
{
	return [self URLWithScheme:scheme user:user password:password host:host port:port path:path query:nil];
}

+ (NSURL*) URLWithScheme:(NSString*)scheme user:(NSString*)user password:(NSString*)password host:(NSString*)host port:(UInt16)port path:(NSString*)path query:(NSString*)query
{
	NSMutableString*				string = [NSMutableString string];
	
	if(![scheme length] || ![host length])
	return nil;
	
	[string appendFormat:@"%@://", scheme];
	
	if([user length]) {
		user = ESCAPE_USER_PASSWORD(user);
		if([password length])
		password = ESCAPE_USER_PASSWORD(password);
		else
		password = nil;
		
		if(user && password)
		[string appendFormat:@"%@:%@@", user, password];
		else
		[string appendFormat:@"%@@", user];
	}
	
	[string appendString:host];
	
	if(port)
	[string appendFormat:@":%i", port];
	
	if([path length]) {
		if([path characterAtIndex:0] != '/')
		[string appendString:@"/"];
		[string appendString:ESCAPE_STRING(path)];
	}
	
	if([query length]) {
		[string appendString:@"?"];
		[string appendString:ESCAPE_STRING(query)];
	}
	
	return [[[self class] URLWithString:string] standardizedURL];
}

- (NSString*) passwordByReplacingPercentEscapes
{
	NSString*						string = [self password];
	
	return ([string length] ? UNESCAPE_STRING(string) : nil);
}

- (NSString*) queryByReplacingPercentEscapes
{
	NSString*						string = [self query];
	
	return ([string length] ? UNESCAPE_STRING(string) : nil);
}

- (NSURL*) URLByDeletingPassword
{
	return [[self class] URLWithScheme:[self scheme] user:[self user] password:nil host:[self host] port:[[self port] unsignedShortValue] path:[self path]];
}

- (NSURL*) URLByDeletingUserAndPassword
{
	return [[self class] URLWithScheme:[self scheme] user:nil password:nil host:[self host] port:[[self port] unsignedShortValue] path:[self path]];
}

@end
