#
#	This file is part of the PolKit library.
#	Copyright (C) 2008-2009 Pierre-Olivier Latour <info@pol-online.net>
#	
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#	
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#	
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

#####
#
# This script replaces __NAME__, __VERSION__ and __SVN_REVISION__ by their actual values in the Info.plist and InfoPlist.strings files for the target
# 
# The project file must have a "version" SVN property defined as such:
# > svn propset version 1.0b1 Myproject.xcodeproj/project.pbxproj
#
# To use in a target, add a script phase with this single line:
# ${SRCROOT}/PolKit/Scripts/ProcessInfoPlists.sh
#
#####

# Retrieve version and revision from SVN
REVISION=`svn info "${PROJECT_DIR}"`
if [[ $? -ne 0 ]]
then
	VERSION="(undefined)"
	REVISION="0"
else
	VERSION=`svn propget version "${PROJECT_FILE_PATH}/project.pbxproj"`
	REVISION=`svn info "${PROJECT_DIR}" | grep "Revision:" | awk '{ print $2 }'`
fi
NAME="$PRODUCT_NAME"

# Patch Info.plist
PATH="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
/usr/bin/perl -p -e "s/__NAME__/$NAME/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"
/usr/bin/perl -p -e "s/__VERSION__/$VERSION/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"
/usr/bin/perl -p -e "s/__SVN_REVISION__/$REVISION/g" "$PATH" > "$PATH~"
/bin/mv "$PATH~" "$PATH"

# Patch InfoPlist.strings
cd "${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
for LANGUAGE in *.lproj;
do
	PATH="$LANGUAGE/InfoPlist.strings"
	/usr/bin/textutil -format txt -inputencoding UTF-16 -convert txt -encoding UTF-8 "$PATH" -output "$PATH"
	/usr/bin/perl -p -e "s/__NAME__/$NAME/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/perl -p -e "s/__VERSION__/$VERSION/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/perl -p -e "s/__SVN_REVISION__/$REVISION/g" "$PATH" > "$PATH~"
	/bin/mv "$PATH~" "$PATH"
	/usr/bin/textutil -format txt -inputencoding UTF-8 -convert txt -encoding UTF-16 "$PATH" -output "$PATH"
done
