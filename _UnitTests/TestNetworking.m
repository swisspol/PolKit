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
#import	"MiniUDPSocket.h"
#import "NetworkReachability.h"
#import "NetworkConfiguration.h"

@interface UnitTests_Networking : UnitTest
@end

@implementation UnitTests_Networking

- (void) testUDP
{
	MiniUDPSocket*			socket;
	
	socket = [MiniUDPSocket new];
	AssertNotNil(socket, nil);
	
	AssertTrue([socket sendData:[@"PolKit" dataUsingEncoding:NSUTF8StringEncoding] toRemoteIPv4Address:(127 << 24 | 0 << 16 | 0 << 8 | 1) port:10000], nil);
	
	[socket release];
}

- (void) testReachability
{
	NetworkReachability*	reachability;
	
	reachability = [[NetworkReachability alloc] init];
	AssertTrue([reachability isReachable], nil);
	[reachability release];
	
	reachability = [[NetworkReachability alloc] initWithHostName:@"apple.com"];
	AssertTrue([reachability isReachable], nil);
	[reachability release];
}

- (void) testConfiguration
{
	NetworkConfiguration*	configuration;
	
	configuration = [NetworkConfiguration sharedNetworkConfiguration];
	AssertNotNil(configuration, nil);
	
	AssertNotNil([configuration locationName], nil);
	//AssertNotNil([configuration dnsDomainName], nil);
	AssertNotEquals([[configuration dnsServerAddresses] count], 0, nil);
	AssertNotEquals([[configuration networkAddresses] count], 0, nil);
	AssertNotNil([configuration airportNetworkName], nil);
	AssertNotNil([configuration airportNetworkSSID], nil);
	AssertNotEquals([[configuration allInterfaces] count], 0, nil);
}

@end
