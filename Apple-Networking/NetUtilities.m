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

#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>
#import <netinet/in.h>
#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#import <netinet6/in6.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/network/IOEthernetInterface.h>
#import <IOKit/network/IONetworkInterface.h>
#import <IOKit/network/IOEthernetController.h>
#import <CommonCrypto/CommonDigest.h>
#endif

#include "NetUtilities.h"

//FUNCTIONS:

#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR

static NSString* _GetPrimaryMACAddress()
{
	NSString*					string = nil;
	CFMutableDictionaryRef		matchingDictionary;
	CFMutableDictionaryRef		propertyMatchingDictionary;
	io_iterator_t				intfIterator;
	io_object_t					intfService;
    io_object_t					controllerService;
    CFDataRef					addressData;
	unsigned char*				address;
	
	if((matchingDictionary = IOServiceMatching(kIOEthernetInterfaceClass))) {
		if((propertyMatchingDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks))) {
			CFDictionarySetValue(propertyMatchingDictionary, CFSTR(kIOPrimaryInterface), kCFBooleanTrue); 
			CFDictionarySetValue(matchingDictionary, CFSTR(kIOPropertyMatchKey), propertyMatchingDictionary);
            if(IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDictionary, &intfIterator) == KERN_SUCCESS) { //NOTE: This consumes a reference of "matchingDictionary"
				if((intfService = IOIteratorNext(intfIterator))) {
					if(IORegistryEntryGetParentEntry(intfService, kIOServicePlane, &controllerService) == KERN_SUCCESS) {
						if((addressData = IORegistryEntryCreateCFProperty(controllerService, CFSTR(kIOMACAddress), kCFAllocatorDefault, 0))) {
							address = (unsigned char*)CFDataGetBytePtr(addressData);
							string = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", address[0], address[1], address[2], address[3], address[4], address[5]];
							CFRelease(addressData);
						}
						IOObjectRelease(controllerService);
					}
					IOObjectRelease(intfService);
				}
				IOObjectRelease(intfIterator);
			}
			CFRelease(propertyMatchingDictionary);
		}
	}
	
	return string;
}

#endif

NSString* HostGetUniqueID()
{
	static NSString*			uniqueID = nil;
#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
	unsigned char				md5[CC_MD5_DIGEST_LENGTH];
	const char*					buffer;
#endif
	
	if(uniqueID == nil) {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		uniqueID = [[UIDevice currentDevice] uniqueIdentifier];
		uniqueID = [[[uniqueID uppercaseString] stringByReplacingOccurrencesOfString:@":" withString:@"-"] copy];
#else
		uniqueID = _GetPrimaryMACAddress(); //NOTE: We hash the MAC address to preserve privacy
		if((buffer = [uniqueID UTF8String])) {
			bzero(md5, CC_MD5_DIGEST_LENGTH);
			CC_MD5(buffer, strlen(buffer), md5);
			uniqueID = [[NSString alloc] initWithFormat:@"%08X-%08X-%08X-%08X", *((unsigned int*)&md5[0]), *((unsigned int*)&md5[4]), *((unsigned int*)&md5[8]), *((unsigned int*)&md5[12])];
		}
		else
		uniqueID = nil;
#endif
		
		if(uniqueID == nil)
		[NSException raise:NSInternalInconsistencyException format:@"Unable to retrieve unique ID"];
	}
	
	return uniqueID;
}

NSString* HostGetName()
{
	static NSString*				name = nil;
	
	if(name == nil) {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		name = [[UIDevice currentDevice] name];
#else
		name = [[NSHost currentHost] name];
#endif
		
		name = [name copy];
	}

	return name;
}

const struct sockaddr* IPAddressGetCurrent()
{
	NSData*							data = nil;
	struct ifaddrs*					list;
	struct ifaddrs*					ifap;
	
	if(getifaddrs(&list) < 0)
	return NULL;
	
	for(ifap = list; ifap; ifap = ifap->ifa_next) {
		if((ifap->ifa_name[0] == 'l') && (ifap->ifa_name[1] == 'o')) //Ignore loopback
		continue;
		
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		if(ifap->ifa_addr->sa_family == AF_INET)
#else
		if((ifap->ifa_addr->sa_family == AF_INET) || (ifap->ifa_addr->sa_family == AF_INET6))
#endif
		{
			data = [NSData dataWithBytes:ifap->ifa_addr length:ifap->ifa_addr->sa_len];
			break;
		}
	}
	
	freeifaddrs(list);
	
	return [data bytes];
}

//FIXME: Handle IPv6 addresses
BOOL IPAddressIsLocal(const struct sockaddr* address)
{
	BOOL							local = NO;
	struct ifaddrs*					list;
	struct ifaddrs*					ifap;
	
	if((address == NULL) || (address->sa_family != AF_INET))
	return NO;
	
	if(getifaddrs(&list) < 0)
	return NO;
	
	for(ifap = list; ifap; ifap = ifap->ifa_next) {
		if((ifap->ifa_name[0] == 'l') && (ifap->ifa_name[1] == 'o')) //Ignore loopback
		continue;
		
		if((ifap->ifa_addr->sa_family == AF_INET) && (ifap->ifa_netmask->sa_family == AF_INET)) {
			if((((struct sockaddr_in*)(ifap->ifa_addr))->sin_addr.s_addr & ((struct sockaddr_in*)(ifap->ifa_netmask))->sin_addr.s_addr) == (((struct sockaddr_in*)address)->sin_addr.s_addr & ((struct sockaddr_in*)(ifap->ifa_netmask))->sin_addr.s_addr)) {
				local = YES;
				break;
			}
		}
	}
	
	freeifaddrs(list);
	
	return local;
}

NSString* IPAddressToString(const struct sockaddr* address, BOOL numericHost, BOOL numericService)
{
	char							hostBuffer[NI_MAXHOST] = {0};
	char							serviceBuffer[NI_MAXSERV] = {0};
	
	if(address) {
		if(getnameinfo(address, address->sa_len, hostBuffer, NI_MAXHOST, serviceBuffer, NI_MAXSERV, (numericHost ? NI_NUMERICHOST : 0) | (numericService ? NI_NUMERICSERV : 0) | NI_NOFQDN) < 0)
		return nil;
		if(!numericService && !serviceBuffer[0]) { //NOTE: Check if there is no service name for this port
			if(getnameinfo(address, address->sa_len, NULL, 0, serviceBuffer, NI_MAXSERV, NI_NUMERICSERV) < 0)
			return nil;
		}
		
		return (serviceBuffer[0] != '0' ? [NSString stringWithFormat:@"%s:%s", hostBuffer, serviceBuffer] : [NSString stringWithFormat:@"%s", hostBuffer]);
	}
	
	return nil;
}

const struct sockaddr* IPAddressFromString(NSString* string)
{
	NSRange							range;
	NSData*							data;
	struct addrinfo*				info;
	in_port_t						port;
	
	if(![string length])
	return NULL;
	
	//NOTE: getaddrinfo() cannot handle service strings that are plain numerical e.g. "22" instead of "ssh"
	range = [string rangeOfString:@":" options:0 range:NSMakeRange(0, [string length])];
	if(range.location != NSNotFound) {
		if(getaddrinfo([[string substringToIndex:range.location] UTF8String], [[string substringFromIndex:(range.location + 1)] UTF8String], NULL, &info) != 0) {
			port = htons([[string substringFromIndex:(range.location + 1)] intValue]);
			if(port == 0)
			return NULL;
			
			if(getaddrinfo([[string substringToIndex:range.location] UTF8String], NULL, NULL, &info) != 0)
			return NULL;
			
			switch(info->ai_addr->sa_family) {
				
				case AF_INET:
				((struct sockaddr_in*)info->ai_addr)->sin_port = port;
				break;
				
#if !TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
				case AF_INET6:
				((struct sockaddr_in6*)info->ai_addr)->sin6_port = port;
				break;
#endif
				
				default:
				freeaddrinfo(info);
				return NULL;
				break;
				
			}
		}
	}
	else {
		if(getaddrinfo([string UTF8String], NULL, NULL, &info) != 0)
		return NULL;
	}
	
	data = [NSData dataWithBytes:info->ai_addr length:info->ai_addr->sa_len];
	
	freeaddrinfo(info);
	
	return (struct sockaddr*)[data bytes];
}
