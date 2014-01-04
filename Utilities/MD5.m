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

#import <CommonCrypto/CommonDigest.h>

#import "MD5.h"

const MD5 kNullMD5 = {{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}};

MD5 MD5WithData(NSData* data)
{
	return MD5WithBytes([data bytes], [data length]);
}

MD5 MD5WithBytes(const void* bytes, NSUInteger length)
{
	MD5						md5;
	unsigned char*			src;
	unsigned char*			dst;
	NSUInteger				i;
	
	if(bytes == NULL)
	return kNullMD5;
	
	if(length > 16) {
		CC_MD5(bytes, length, md5.bytes);
		return md5;
	}
	
	src = (unsigned char*)bytes;
	dst = md5.bytes;
	for(i = 0; i < length / 4; ++i) {
		*((int*)dst) = *((int*)src);
		src += 4;
		dst += 4;
	}
	for(i = 0; i < length % 4; ++i)
	*dst++ = *src++;
	for(i = 0; i < 16 - length; ++i)
	*dst++ = 0x00;
	
	return md5;
}

NSString* MD5ToString(MD5* md5)
{
	unsigned char*		ptr = (unsigned char*)md5;
	
	if(ptr == NULL)
	return nil;
	
	return [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X", ptr[0], ptr[1], ptr[2], ptr[3], ptr[4], ptr[5], ptr[6], ptr[7], ptr[8], ptr[9], ptr[10], ptr[11], ptr[12], ptr[13], ptr[14], ptr[15]];
}

MD5 MD5FromString(NSString* string)
{
	MD5					md5;
	NSUInteger			i;
	unsigned char		num;
	
	if([string length] != 32)
	return kNullMD5;
	
	for(i = 0; i < 16; ++i) {
		num = [string characterAtIndex:(2 * i)];
		if((num >= 'A') && (num <= 'F'))
		num = num - 'A' + 10;
		else if((num >= 'a') && (num <= 'f'))
		num = num - 'a' + 10;
		else if((num >= '0') && (num <= '9'))
		num = num - '0';
		else
		return kNullMD5;
		md5.bytes[i] = 16 * num;
		
		num = [string characterAtIndex:(2 * i + 1)];
		if((num >= 'A') && (num <= 'F'))
		num = num - 'A' + 10;
		else if((num >= 'a') && (num <= 'f'))
		num = num - 'a' + 10;
		else if((num >= '0') && (num <= '9'))
		num = num - '0';
		else
		return kNullMD5;
		md5.bytes[i] += num;
	}
	
	return md5;
}
