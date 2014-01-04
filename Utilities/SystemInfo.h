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

#import <Foundation/Foundation.h>

@interface SystemInfo : NSObject
{
@private
	NSString*					_computerName;
	NSString*					_modelType;
	NSString*					_modelName;
	NSString*					_macAddress;
	NSString*					_buildVersion;
	NSString*					_productVersion;
	BOOL						_has64Bit;
	NSString*					_cpuType;
	NSUInteger					_cpuCount,
								_cpuSpeed,
								_busSpeed;
	unsigned long long			_memorySize;
}
+ (SystemInfo*) sharedSystemInfo;

@property(nonatomic, readonly) NSString* computerName;
@property(nonatomic, readonly) NSString* machineModelType; //E.g. "iMac6,1"
@property(nonatomic, readonly) NSString* machineModelName; //E.g. "iMac"
@property(nonatomic, readonly) NSString* primaryMACAddress; //E.g. "00:00:00:00:00:00"
@property(nonatomic, readonly) NSString* systemBuildVersion; //E.g. "9A25"
@property(nonatomic, readonly) NSString* systemProductVersion; //E.g. "10.5.4"
@property(nonatomic, readonly) NSString* cpuType; //E.g. "PowerPC" or "Intel"
@property(nonatomic, readonly) NSUInteger cpuCount;
@property(nonatomic, readonly) NSUInteger cpuFrequency;
@property(nonatomic, readonly) NSUInteger busFrequency;
@property(nonatomic, readonly) unsigned long long physicalMemory;
@property(nonatomic, readonly) BOOL supports64Bit;

@property(nonatomic, readonly, getter=isBatteryPresent) BOOL batteryPresent;
@property(nonatomic, readonly, getter=isRunningOnBattery) BOOL runningOnBattery;
@property(nonatomic, readonly, getter=isBatteryCharging) BOOL batteryCharging;
@end
