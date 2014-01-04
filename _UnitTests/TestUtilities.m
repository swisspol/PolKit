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
#import "Keychain.h"
#import "MD5.h"
#import "Task.h"
#import "DiskImageController.h"
#import "LoginItems.h"
#import "SystemInfo.h"
#import "WorkerThread.h"
#import "MiniXMLParser.h"

#define kKeychainService @"unit-testing"
#define kLogin @"polkit"
#define kPassword @"info@pol-online.net"
#define kURLWithoutPassword @"ftp://foo@example.com/path"
#define kURLWithPassword @"ftp://foo:bar@example.com/path"

@interface UnitTests_Utilities : UnitTest
@end

@implementation UnitTests_Utilities

- (void) testDataStream
{
	; //DataStream class is tested through FileTransferController class
}

- (void) testKeychain
{
	AssertTrue([[Keychain sharedKeychain] addGenericPassword:kPassword forService:kKeychainService account:kLogin], nil);
	AssertEqualObjects([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kLogin], kPassword, nil);
	AssertTrue([[Keychain sharedKeychain] removeGenericPasswordForService:kKeychainService account:kLogin], nil);
	AssertNil([[Keychain sharedKeychain] genericPasswordForService:kKeychainService account:kLogin], nil);
	
	AssertTrue([[Keychain sharedKeychain] addPasswordForURL:[NSURL URLWithString:kURLWithPassword]], nil);
	AssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithPassword], nil);
	AssertTrue([[Keychain sharedKeychain] removePasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], nil);
	AssertEqualObjects([[Keychain sharedKeychain] URLWithPasswordForURL:[NSURL URLWithString:kURLWithoutPassword]], [NSURL URLWithString:kURLWithoutPassword], nil);
}

- (void) testLoginItems
{
	AssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
	AssertFalse([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
	AssertTrue([[LoginItems sharedLoginItems] addItemWithDisplayName:@"Pol-Online" url:[NSURL fileURLWithPath:@"/Applications/Safari.app"] hidden:NO], nil);
	AssertTrue([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
	AssertTrue([[LoginItems sharedLoginItems] removeItemWithDisplayName:@"Pol-Online"], nil);
	AssertFalse([[LoginItems sharedLoginItems] hasItemWithDisplayName:@"Pol-Online"], nil);
}

- (void) testMD5Computation
{
	NSData*					data;
	MD5						dataMD5,
							expectedMD5;
	NSString*				string;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Resources/Image.jpg"];
	AssertNotNil(data, nil);
	dataMD5 = MD5WithData(data);
	[data release];
	
	//Generated with 'openssl dgst -md5 Image.jpg'
	string = [NSString stringWithContentsOfFile:@"Resources/Image.md5" encoding:NSUTF8StringEncoding error:NULL];
	AssertTrue([string isEqualToString:[MD5ToString(&dataMD5) lowercaseString]], nil);
	expectedMD5 = MD5FromString(string);
	AssertTrue(MD5EqualToMD5(&dataMD5, &expectedMD5), nil);
}

- (void) testMD5StringConversion
{
	NSString*				string = @"f430e8d7a52c4fc38fef381ec6ffe594";
	MD5						md5;
	
	md5 = MD5FromString(string);
	
	AssertTrue([MD5ToString(&md5) isEqualToString:[string uppercaseString]], nil);
}

- (void) testTask
{
	NSString*	result;
	
	result = [Task runWithToolPath:@"/usr/bin/grep" arguments:[NSArray arrayWithObject:@"france"] inputString:@"bonjour!\nvive la france!\nau revoir!" timeOut:0.0];
	AssertEqualObjects(result, @"vive la france!\n", nil);
	
	result = [Task runWithToolPath:@"/bin/sleep" arguments:[NSArray arrayWithObject:@"2"] inputString:nil timeOut:1.0];
	AssertNil(result, nil);
}

- (void) testDiskImage
{
	DiskImageController*	controller = [DiskImageController sharedDiskImageController];
	NSString*				imagePath = [@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	NSString*				imagePath2 = [[@"/tmp" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] stringByAppendingPathExtension:@"dmg"];
	NSFileManager*			manager = [NSFileManager defaultManager];
	NSString*				sourcePath;
	NSError*				error;
	NSString*				mountPoint;
	
	sourcePath = @".";
	imagePath = [imagePath stringByAppendingPathExtension:@"dmg"];
	AssertTrue([controller makeCompressedDiskImageAtPath:imagePath withName:nil contentsOfDirectory:sourcePath password:kPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	AssertNil(mountPoint, nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kPassword private:NO verify:YES];
	AssertNotNil(mountPoint, nil);
	if(mountPoint) {
		AssertTrue([[manager contentsOfDirectoryAtPath:mountPoint error:NULL] count] >= [[manager contentsOfDirectoryAtPath:sourcePath error:NULL] count], nil);
		AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
		sleep(1);
	}
	AssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:kPassword], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Resources/Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"dmg"];
	AssertTrue([controller makeDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:NO];
	AssertNotNil(mountPoint, nil);
	if(mountPoint) {
		AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
		AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
		sleep(1);
	}
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertTrue([controller makeCompressedDiskImageAtPath:imagePath2 withDiskImage:imagePath password:nil], nil);
	AssertTrue([manager removeItemAtPath:imagePath2 error:&error], [error localizedDescription]);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Resources/Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparseimage"];
	AssertTrue([controller makeSparseDiskImageAtPath:imagePath withName:nil size:(10 * 1024) password:nil], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:nil private:NO verify:YES];
	AssertNotNil(mountPoint, nil); //FIXME: This fails on 10.6.1 because of fsck (Radar 7312247)
	if(mountPoint) {
		AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
		AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
		sleep(1);
	}
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
	
	sourcePath = @"Resources/Image.jpg";
	imagePath = [[imagePath stringByDeletingPathExtension] stringByAppendingPathExtension:@"sparsebundle"];
	AssertTrue([controller makeSparseBundleDiskImageAtPath:imagePath withName:nil password:kPassword], nil);
	mountPoint = [controller mountDiskImage:imagePath atPath:nil usingShadowFile:nil password:kPassword private:NO verify:NO];
	AssertNotNil(mountPoint, nil); //FIXME: This fails on 10.6.1 because of fsck (Radar 7312247)
	if(mountPoint) {
		AssertTrue([manager copyItemAtPath:sourcePath toPath:[mountPoint stringByAppendingPathComponent:[sourcePath lastPathComponent]] error:&error], [error localizedDescription]);
		AssertTrue([controller unmountDiskImageAtPath:mountPoint force:NO], nil);
		sleep(1);
	}
	AssertNil([controller infoForDiskImageAtPath:imagePath password:nil], nil);
	AssertNotNil([controller infoForDiskImageAtPath:imagePath password:kPassword], nil);
	AssertTrue([manager removeItemAtPath:imagePath error:&error], [error localizedDescription]);
}

- (void) testSystemInfo
{
	AssertNotNil([SystemInfo sharedSystemInfo], nil);
}

- (void) _thread:(id)argument
{
	sleep(2);
}

- (void) testWorkerThread
{
	WorkerThread*		worker;
	
	worker = [WorkerThread new];
	
	AssertNotNil(worker, nil);
	AssertFalse([worker isRunning], nil);
	[worker startWithTarget:self selector:@selector(_thread:) argument:nil];
	AssertTrue([worker isRunning], nil);
	[worker waitUntilDone];
	AssertFalse([worker isRunning], nil);
	
	[worker release];
}

- (void) testMiniXMLParser
{
	NSData*				data;
	MiniXMLParser*		parser;
	NSArray*			array;
	
	data = [[NSData alloc] initWithContentsOfFile:@"Resources/WebDAV.xml"];
	
	parser = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:@"DAV:"];
	AssertNotNil(parser, nil);
	AssertEqualObjects([parser firstValueAtPath:@"multistatus:response:propstat:prop:creationdate"], @"2009-11-12T03:21:52Z", nil);
	AssertEqualObjects([[parser firstNodeAtPath:@"multistatus:response:propstat:status"] value], @"HTTP/1.1 200 OK", nil);
	AssertNil([parser firstValueAtPath:@"multistatus:response:propstat:prop:resourcetype:collection"], nil);
	array = [[parser firstNodeAtPath:@"multistatus"] children];
	AssertTrue([array count] == 3, nil);
	AssertEqualObjects([[array objectAtIndex:0] firstValueAtSubpath:@"propstat:status"], @"HTTP/1.1 200 OK", nil);
	[parser release];
	
	parser = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:@"foobar"];
	AssertNotNil(parser, nil);
	AssertNil([parser firstValueAtPath:@"multistatus:response:propstat:prop:creationdate"], nil);
	AssertNil([parser firstNodeAtPath:@"multistatus"], nil);
	[parser release];
	
	parser = [[MiniXMLParser alloc] initWithXMLData:data nodeNamespace:nil];
	AssertNotNil(parser, nil);
	AssertEqualObjects([parser firstValueAtPath:@"multistatus:response:propstat:prop:creationdate"], @"2009-11-12T03:21:52Z", nil);
	AssertEqualObjects([[parser firstNodeAtPath:@"multistatus:response:propstat:status"] value], @"HTTP/1.1 200 OK", nil);
	[parser release];
	
	[data release];
}

@end
