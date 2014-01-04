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

#import <sys/sysctl.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/network/IOEthernetInterface.h>
#import <IOKit/network/IONetworkInterface.h>
#import <IOKit/network/IOEthernetController.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "SystemInfo.h"

#if __BIG_ENDIAN__
#define k64BitSupportSelector	"hw.optional.64bitops"
#else
#define k64BitSupportSelector	"hw.optional.x86_64"
#endif

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
		else
		CFRelease(matchingDictionary);
	}
	
	return string;
}

@implementation SystemInfo

@synthesize computerName=_computerName, machineModelType=_modelType, machineModelName=_modelName, primaryMACAddress=_macAddress;
@synthesize systemBuildVersion=_buildVersion, systemProductVersion=_productVersion;
@synthesize cpuType=_cpuType, cpuCount=_cpuCount, cpuFrequency=_cpuSpeed, busFrequency=_busSpeed, physicalMemory=_memorySize, supports64Bit=_has64Bit;

+ (SystemInfo*) sharedSystemInfo
{
	static SystemInfo*		systemInfo = nil;
	
	if(systemInfo == nil)
	systemInfo = [SystemInfo new];
	
	return systemInfo;
}

- (id) init
{
	size_t					length;
	char					buffer[1024];
	NSDictionary*			plist;
	uint32_t				value32;
	uint64_t				value64;
	NSString*				path;
	
	if((self = [super init])) {
		_computerName = (NSString*)SCDynamicStoreCopyComputerName(NULL, NULL);
		if(_computerName == nil)
		[NSException raise:NSInternalInconsistencyException format:@"Unable to retrieve computer name"];
		
		length = sizeof(buffer);
		if(sysctlbyname("hw.model", &buffer, &length, NULL, 0) == 0) {
			_modelType = [[NSString alloc] initWithBytes:buffer length:strlen(buffer) encoding:NSASCIIStringEncoding];
			if(_modelType) {
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
				if(kCFCoreFoundationVersionNumber < 500.0)
				path = @"/System/Library/SystemProfiler/SPPlatformReporter.spreporter/Contents/Resources/SPMachineTypes.plist";
				else
#endif
				path = @"/System/Library/CoreServices/Resources/SPMachineTypes.plist";
				plist = [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:path] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
				_modelName = [[plist objectForKey:_modelType] copy];
				if(plist && !_modelName)
				_modelName = [_modelType copy];
			}
			if(_modelName == nil)
			[NSException raise:NSInternalInconsistencyException format:@"Unable to read \"SPMachineTypes.plist\""];
		}
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.model' from sysctlbyname()"];
		
		_macAddress = [_GetPrimaryMACAddress() copy];
		if(_macAddress == nil)
		[NSException raise:NSInternalInconsistencyException format:@"Unable to retrieve primary MAC address from IOKit"];
		
		plist = [NSPropertyListSerialization propertyListFromData:[NSData dataWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"] mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
		_buildVersion = [[plist objectForKey:@"ProductBuildVersion"] copy];
		_productVersion = [[plist objectForKey:@"ProductVersion"] copy];
		if((_buildVersion == nil) || (_productVersion == nil))
		[NSException raise:NSInternalInconsistencyException format:@"Unable to read \"SystemVersion.plist\""];
		
		length = sizeof(value32);
		if(sysctlbyname("hw.cputype", &value32, &length, NULL, 0) == 0) {
			switch(value32) {
				case CPU_TYPE_POWERPC: case CPU_TYPE_POWERPC64: _cpuType = @"PowerPC"; break;
				case CPU_TYPE_X86: case CPU_TYPE_X86_64: _cpuType = @"Intel"; break;
			}
		}
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.cputype' from sysctlbyname()"];
		
		length = sizeof(value32);
		if(sysctlbyname("hw.activecpu", &value32, &length, NULL, 0) == 0)
		_cpuCount = value32;
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.activecpu' from sysctlbyname()"];
		
		length = sizeof(value64);
		if(sysctlbyname("hw.memsize", &value64, &length, NULL, 0) == 0)
		_memorySize = value64;
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.memsize' from sysctlbyname()"];
		
		length = sizeof(value64);
		if(sysctlbyname("hw.cpufrequency", &value64, &length, NULL, 0) == 0)
		_cpuSpeed = value64;
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.cpufrequency' from sysctlbyname()"];
		
		length = sizeof(value64);
		if(sysctlbyname("hw.busfrequency", &value64, &length, NULL, 0) == 0)
		_busSpeed = value64;
		else
		[NSException raise:NSInternalInconsistencyException format:@"Unable to get 'hw.busfrequency' from sysctlbyname()"];
		
		length = sizeof(value32);
		if((sysctlbyname(k64BitSupportSelector, &value32, &length, NULL, 0) == 0) && value32)
		_has64Bit = YES;
	}
	
	return self;
}

- (id) _getPowerSourceKey:(id)key
{
	id						result = nil;
	CFTypeRef				info;
	CFArrayRef				list;
	CFIndex					count,
							i;
	CFDictionaryRef			description;
	
	if((info = IOPSCopyPowerSourcesInfo())) {
		if((list = IOPSCopyPowerSourcesList(info))) {
			for(i = 0, count = CFArrayGetCount(list); i < count; ++i) {
				description = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
				if(description == NULL)
				continue;
				result = [[[(NSDictionary*)description objectForKey:key] retain] autorelease];
				if(result)
				break;
			}
			CFRelease(list);
		}
		CFRelease(info);
	}
	
	return result;
}

- (BOOL) isBatteryPresent
{
	return [[self _getPowerSourceKey:@kIOPSIsPresentKey] boolValue];
}

- (BOOL) isRunningOnBattery
{
	return [[self _getPowerSourceKey:@kIOPSPowerSourceStateKey] isEqualToString:@kIOPSBatteryPowerValue];
}

- (BOOL) isBatteryCharging
{
	return [[self _getPowerSourceKey:@kIOPSIsChargingKey] boolValue];
}

@end
