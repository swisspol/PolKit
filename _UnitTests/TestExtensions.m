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

#import "UnitTesting.h"
#import "NSData+Encryption.h"
#import "NSData+GZip.h"
#import "NSURL+Parameters.h"
#import "NSFileManager+LockedItems.h"

@interface UnitTests_Extensions : UnitTest
@end

@implementation UnitTests_Extensions

- (void) testMD5
{
	NSMutableString*		md5String;
	NSData*					md5Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data, nil);
	md5Data = [data md5Digest];
	AssertEquals([md5Data length], (NSUInteger)16, nil);
	[data release];
	
	md5String = [NSMutableString string];
	for(i = 0; i < 16; ++i)
	[md5String appendFormat:@"%02x", *((unsigned char*)[md5Data bytes] + i)];
	AssertNotNil(md5String, nil);
	
	//Generated with 'openssl dgst -md5 Image.jpg'
	string = [NSString stringWithContentsOfFile:@"Resources/Image.md5" encoding:NSUTF8StringEncoding error:NULL];
	AssertEqualObjects(md5String, string, nil);
}

- (void) testSHA1
{
	NSMutableString*		sha1String;
	NSData*					sha1Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data, nil);
	sha1Data = [data sha1Digest];
	AssertEquals([sha1Data length], (NSUInteger)20, nil);
	[data release];
	
	sha1String = [NSMutableString string];
	for(i = 0; i < 20; ++i)
	[sha1String appendFormat:@"%02x", *((unsigned char*)[sha1Data bytes] + i)];
	AssertNotNil(sha1String, nil);
	
	//Generated with 'openssl dgst -sha1 Image.jpg'
	string = [NSString stringWithContentsOfFile:@"Resources/Image.sha1" encoding:NSUTF8StringEncoding error:NULL];
	AssertEqualObjects(sha1String, string, nil);
}

- (void) testSHA1HMac
{
	NSMutableString*		sha1String;
	NSData*					sha1Data;
	NSData*					data;
	NSUInteger				i;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data, nil);
	sha1Data = [data sha1HMacWithKey:@"info@pol-online.net"];
	AssertEquals([sha1Data length], (NSUInteger)20, nil);
	[data release];
	
	sha1String = [NSMutableString string];
	for(i = 0; i < [sha1Data length]; ++i)
	[sha1String appendFormat:@"%02x", *((unsigned char*)[sha1Data bytes] + i)];
	AssertNotNil(sha1String, nil);
	
	//Generated with 'openssl sha1 -hmac info@pol-online.net Image.jpg'
	string = [NSString stringWithContentsOfFile:@"Resources/Image.hmac-sha1" encoding:NSUTF8StringEncoding error:NULL];
	AssertEqualObjects(sha1String, string, nil);
}

- (void) testBase64
{
	NSData*					data1;
	NSData*					data2;
	NSString*				string1;
	NSString*				string2;
	NSError*				error;
	
	data1 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data1, nil);
	string1 = [data1 encodeBase64];
	AssertNotNil(string1, nil);
	
	//Generated with 'openssl base64 -e -in Unit-Testing/Image.jpg -out Image.b64'
	string2 = [NSString stringWithContentsOfFile:@"Resources/Image.b64" encoding:NSASCIIStringEncoding error:&error];
	AssertNotNil(string2, [error localizedDescription]);
	
	AssertEqualObjects(string1, [string2 stringByReplacingOccurrencesOfString:@"\n" withString:@""], nil);
	
	data2 = [string1 decodeBase64];
	AssertEqualObjects(data2, data1, nil);
	
	[data1 release];
}

- (void) testBlowfish
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data1, nil);
	
	data2 = [data1 encryptBlowfishWithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNotNil(data2, nil);
	data3 = [NSData dataWithContentsOfFile:@"Resources/Image.bf"]; //Generated with 'openssl bf-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.bf'
	AssertNotNil(data3, nil);
	AssertEqualObjects(data2, data3, nil);
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net" useSalt:NO];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNil(data3, nil);
	
	data2 = [NSData dataWithContentsOfFile:@"Resources/Image.bf-salted"]; //Generated with 'openssl bf-cbc -k "info@pol-online.net" -in Image.jpg -out Image.bf-salted'
	AssertNotNil(data2, nil);
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNil(data3, nil);
	
	data2 = [data1 encryptBlowfishWithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNotNil(data2, nil);
	data3 = [data2 decryptBlowfishWithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testAES128
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data1, nil);
	
	data2 = [data1 encryptAES128WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNotNil(data2, nil);
	data3 = [NSData dataWithContentsOfFile:@"Resources/Image.aes128"]; //Generated with 'openssl aes-128-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.aes128'
	AssertNotNil(data3, nil);
	AssertEqualObjects(data2, data3, nil);
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNil(data3, nil);
	
	data2 = [NSData dataWithContentsOfFile:@"Resources/Image.aes128-salted"]; //Generated with 'openssl aes-128-cbc -k "info@pol-online.net" -in Image.jpg -out Image.aes128-salted'
	AssertNotNil(data2, nil);
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNil(data3, nil);
	
	data2 = [data1 encryptAES128WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNotNil(data2, nil);
	data3 = [data2 decryptAES128WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testAES256
{
	NSData*					data1;
	NSData*					data2;
	NSData*					data3;
	
	data1 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data1, nil);
	
	data2 = [data1 encryptAES256WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNotNil(data2, nil);
	data3 = [NSData dataWithContentsOfFile:@"Resources/Image.aes256"]; //Generated with 'openssl aes-256-cbc -k "info@pol-online.net" -nosalt -in Image.jpg -out Image.aes256'
	AssertNotNil(data3, nil);
	AssertEqualObjects(data2, data3, nil);
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNil(data3, nil);
	
	data2 = [NSData dataWithContentsOfFile:@"Resources/Image.aes256-salted"]; //Generated with 'openssl aes-256-cbc -k "info@pol-online.net" -in Image.jpg -out Image.aes256-salted'
	AssertNotNil(data2, nil);
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net" useSalt:NO];
	AssertNil(data3, nil);
	
	data2 = [data1 encryptAES256WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertNotNil(data2, nil);
	data3 = [data2 decryptAES256WithPassword:@"info@pol-online.net" useSalt:YES];
	AssertEqualObjects(data3, data1, nil);
	
	[data1 release];
}

- (void) testGZip
{
	NSString*				path1 = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				path2 = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSData*					data1;
	NSData*					data2;
	NSError*				error;
	
	data1 = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data1, nil);
	AssertTrue([data1 writeToGZipFile:path1], nil);
	data2 = [[NSData alloc] initWithGZipFile:path1];
	AssertNotNil(data2, nil);
	AssertEqualObjects(data1, data2, nil);
	[data2 release];
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path1 error:&error], [error localizedDescription]);
	
	AssertNil([[NSData data] compressGZip], nil);
	AssertNil([[NSData data] decompressGZip], nil);
	data2 = [data1 compressGZip];
	AssertEqualObjects(data1, [data2 decompressGZip], nil);
	
	AssertTrue([data2 writeToFile:path2 atomically:YES], nil);
	data2 = [[NSData alloc] initWithGZipFile:path2];
	AssertNotNil(data2, nil);
	AssertEqualObjects(data1, data2, nil);
	[data2 release];
	AssertTrue([[NSFileManager defaultManager] removeItemAtPath:path2 error:&error], [error localizedDescription]);
	
	[data1 release];
}

- (void) testURL
{
	NSURL*					url;
	
	url = [NSURL URLWithScheme:@"http" user:@"info@pol-online.net" password:@"%1:2@3/4?5%" host:@"www.foo.com" port:8080 path:@"/test file.html"];
	AssertNotNil(url, nil);
	AssertEqualObjects([url scheme], @"http", nil);
	AssertEqualObjects([url user], @"info@pol-online.net", nil);
	AssertEqualObjects([url passwordByReplacingPercentEscapes], @"%1:2@3/4?5%", nil);
	AssertEqualObjects([url host], @"www.foo.com", nil);
	AssertEquals([[url port] unsignedShortValue], (UInt16)8080, nil);
	AssertEqualObjects([url path], @"/test file.html", nil);
	AssertEqualObjects([url URLByDeletingUserAndPassword], [NSURL URLWithString:@"http://www.foo.com:8080/test%20file.html"], nil);
}

- (void) testLockedItems
{
	NSString*				path = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSError*				error;
	
	AssertTrue([path writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error], [error localizedDescription]);
	AssertFalse([manager isItemLockedAtPath:path], nil);
	AssertTrue([manager lockItemAtPath:path error:&error], [error localizedDescription]);
	AssertTrue([manager forceRemoveItemAtPath:path error:&error], [error localizedDescription]);
}

@end
