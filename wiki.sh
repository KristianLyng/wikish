#!/bin/bash
# Wiki.sh - shell/awk-interface to mediawiki
# Copyright (C) 2010 Redpill Linpro AS
# Copyright (C) 2010 Kristian Lyngstol
# Author: Kristian Lyngstøl <kristian@bohemians.org>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


# Order matters - 'cause I'm lazy.


# Strictly speaking we should evaluate a handful of environmental
# variables, check for a global configuration in a couple of different
# places, then fall back to where everyone keeps it anyway. I've done that
# crap once in a shell script (See compiz-manager), and it's no fun to
# repeat.
if [ ! -f ~/.config/wikish.config ]; then
	echo "You need to move wikish.config to ~/.config/ and edit it";
	echo "(see, we're XDG-basedir-compliant without needing a huge library!)"
	echo "((((sort of.....))))"
	exit 1;
fi

. ~/.config/wikish.config

test -f .wikish.config && . .wikish.config

TIM=$(date +%s)

# Should probably >&2
function usage
{
	echo "RTFS!";
	echo "On a happier note:"
	echo " Configure stuff in wikish.config, then: "
	echo " ./wiki.sh GET Some_Page"
	echo " ./wiki.sh POST Some_Page"
	echo " ./wiki.sh EDIT Some_Page"
	echo " ./wiki.sh CLEAN (some random text because my argument-checking is lazy)"
	echo " (Any trailing .wiki in the page-name is stripped)"
	echo " Existing versions are not overwritten locally, but backed up."
	echo " and are safe to remove."
	echo " Oh yeah, and so far we/I/wikish only supports basich http auth"
	echo " ... and no conflict-handling."
}

# Yeah, the placement is ugly. This script doesn't read nicely anymore.
ME=$(basename $0)
ACTION=""
PAGE=""
if [ $ME = "wikiedit" ]; then
	ACTION="EDIT"
	PAGE=$1
elif [ $ME = "wikiget" ]; then
	ACTION="GET"
	PAGE=$1
elif [ $ME = "wikipost" ]; then
	ACTION="POST"
	PAGE=$1
else
	ACTION=$1
	PAGE=$2
fi

if [ -z "$PAGE" ]; then
	usage;
	exit 1;
fi

# Allows for Main_Page and Main_Page.wiki - ie: tab completion.
PAGE=$(echo $PAGE | sed s/.wiki$//);

# Gets $PAGE and stores it to $PAGE.wiki
function getit
{
	if [ -f $PAGE.wiki ]; then
		echo "Moving $PAGE.wiki to $PAGE.wiki.$TIM"
		if [ -f $PAGE.wiki.$TIM ]; then
			echo "PANIC! already exist. Stop using loops!";
			sleep 5;
			exit 1;
		fi
		mv $PAGE.wiki $PAGE.wiki.$TIM
	fi

	GET "${PROTO}://${USER}:${PASSWORD}@${HOST}/index.php?title=${PAGE}&action=raw" > $PAGE.wiki
	if [ $? == 0 ]; then
		echo "$PAGE.wiki created seemingly without errors! Phew.";
	else
		echo "$PAGE.wiki GET-operation may have blown apart.  Abandon ship!"
		exit 2;
	fi
}

# Gets an edittoken and session for editing $PAGE and posts the local
# $PAGE.wiki
function postit
{
 	BURL="${PROTO}://${USER}:${PASSWORD}@${HOST}/${API}"
 	GET -USse "${BURL}action=query&format=txt&prop=info&intoken=edit&titles=$PAGE" | awk -v page="$PAGE" -v burl="$BURL" '
		BEGIN {
			wiki_session = "";
			wikiToken = "";
			edittoken="";
		}
		/^Set-Cookie: wiki_session=/ {
			gsub("^Set-Cookie: wiki_session=","");
			gsub(";.*$","");
			wiki_session=$0;
		}
		/^Set-Cookie: wikiToken=/ {
			gsub("^Set-Cookie: wikiToken=","");
			gsub(";.*$","");
			wikiToken=$0;
		}
		/\[edittoken\] => / {
			edittoken = $3;
		}
		END {
			gsub("\\\\","\\\\",edittoken);
			gsub("+","%2B",edittoken);
			printf "echo | curl --post -k --data-urlencode text@"
			printf "%s.wiki ", page;
			printf "-b wikiToken=" wikiToken " -b wiki_session=" wiki_session;
			printf " \"" burl "format=txt&action=edit&title=%s&token=%s\" \n", page, edittoken
		}
		' | sh
}


if [ x$ACTION == "xGET" ]; then
	getit
elif [ x$ACTION == "xPOST" ]; then
	postit
elif [ x$ACTION == "xEDIT" ]; then
	getit
	cp $PAGE.wiki $PAGE.wiki.original.$TIM
	# Thank Red Hat for the non-vi-clone support: they keep /bin/vi
	# bastardized so you need/want to run 'vim' explicitly. Otherwise
	# there would be no reason to support other editors.
	if [ -z "$EDITOR" ]; then
		vi $PAGE.wiki
	else
		$EDITOR $PAGE.wiki
	fi
	diff -q $PAGE.wiki $PAGE.wiki.original.$TIM && {
		echo "No diff between original and new version... I think."
		echo "(so no posting it)"
		exit 1;
	}
	postit
elif [ x$ACTION == "xCLEAN" ]; then
	# Generate too much crap. One day I will put it in dot-files.
	RMS=*.wiki.*[0-9]*
	echo "About to kill: "
	echo $RMS
	echo "[Y]es/NOOOOOOOO!"
	read yesno
	if [ -z "$yesno" ] || [ "$yesno" == "Y" ] || [ "$yesno" == "y" ] || [ "$yesno" == "all work and no play makes jack a dull boy" ]; then
		rm $RMS
	else
		echo "Bailing!";
	fi
else
	echo "Unknown arguments" >&2
	usage
fi
