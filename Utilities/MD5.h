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

typedef struct {
	unsigned char bytes[16];
} MD5;

extern const MD5 kNullMD5;

static inline BOOL MD5EqualToMD5(const MD5* md5a, const MD5* md5b)
{
	int*					ptrA = (int*)md5a;
	int*					ptrB = (int*)md5b;
	
	return ((ptrA[0] == ptrB[0]) && (ptrA[1] == ptrB[1]) && (ptrA[2] == ptrB[2]) && (ptrA[3] == ptrB[3]));
}

static inline BOOL MD5IsNull(MD5* md5)
{
	return MD5EqualToMD5(md5, &kNullMD5);
}

#ifdef __cplusplus
extern "C"
{
#endif
MD5 MD5WithData(NSData* data);
MD5 MD5WithBytes(const void* bytes, NSUInteger length);

NSString* MD5ToString(MD5* md5);
MD5 MD5FromString(NSString* string);
#ifdef __cplusplus
}
#endif
