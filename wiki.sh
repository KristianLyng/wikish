#!/bin/sh
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


# Should probably >&2
usage()
{
	cat <<_EOF_
On a happier note:

Configure stuff in wikish.config, then: 
 ./wiki.sh GET Some_Page
 ./wiki.sh POST Some_Page
 ./wiki.sh EDIT Some_Page
 ./wiki.sh CLEAN
(Any trailing .wiki in the page-name is stripped)

wiki.sh will (hopefully) not overwrite anything, but back it up for you.

Configurations can be local (.wikish.config) or global (typically
~/.config/wikish.config). See README for details.

Oh yeah, and so far wikish only supports basic http auth
... and no conflict-handling.
_EOF_
}

debug() {
	if [ -z "$DEBUG" ]; then
		true;
	else
		echo $*
	fi
}

################
# "Global variables" that are not really affected by configuration
################

TIM=$(date +%s)
ME=$(basename $0)
ACTION=""
PAGE=""

################
# Configuration
################
# Borrowed from compiz-manager: XDG base dirs is an ugly beast but I like
# to do this just to remind people that you do not need a library to handle
# this ugly mess. (I'm looking at you, awesome).

# Read configuration from XDG paths
NAME=wikish.config
if [ -z "$XDG_CONFIG_DIRS" ]; then
	test -f /etc/xdg/$NAME && . /etc/xdg/$NAME
else
	test -f $XDG_CONFIG_DIRS/$NAME && . $XDG_CONFIG_DIRS/$NAME
fi

if [ -z "$XDG_CONFIG_HOME" ]; then
	test -f $HOME/.config/$NAME && . $HOME/.config/$NAME
else
	test -f $XDG_CONFIG_HOME/$NAME && .  $XDG_CONFIG_HOME/$NAME
fi

if [ -z "$API" ] || [ -z "$USER" ] || [ -z "$HOST" ] || \
	[ -z "$PASSWORD" ] || [ -z "$PROTO" ]; then
	echo "Insufficient or missing configuration."
	echo "Copy $NAME to an xdg-path (typically ~/.config/, see \$XDG_CONFIG_DIRS)"
	exit 1;
fi

# Read local config
test -f .wikish.config && . .wikish.config

################
# Sym-link and argument mapping
################

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


if [ -z "$PAGE" ] && [ ! "x$1" = "xCLEAN" ]; then
	usage;
	exit 1;
fi

# Allows for Main_Page and Main_Page.wiki - ie: tab completion.
PAGE=$(echo $PAGE | sed s/.wiki$//);


# Gets $PAGE and stores it to $PAGE.wiki
# Safely backs up any existing $PAGE.wiki to $PAGE.wiki.$TIM
getit()
{
	if [ -f "$PAGE.wiki" ]; then
		debug "Moving $PAGE.wiki to $PAGE.wiki.$TIM"
		if [ -f $PAGE.wiki.$TIM ]; then
			echo "PANIC! already exist. Stop using loops!";
			sleep 5;
			exit 1;
		fi
		mv "$PAGE.wiki" "$PAGE.wiki.$TIM"
	fi

	GET "${PROTO}://${USER}:${PASSWORD}@${HOST}/index.php?title=${PAGE}&action=raw" > "$PAGE.wiki"
	if [ $? = 0 ]; then
		debug "$PAGE.wiki created seemingly without errors! Phew.";
	else
		echo "$PAGE.wiki GET-operation may have blown apart.  Abandon ship!"
		exit 2;
	fi
}

# Gets an edittoken and session for editing $PAGE and posts the local
# $PAGE.wiki. Note that the awk-script generates a curl-command which is
# piped to sh. Not terribly pretty.
postit()
{
 	BURL="${PROTO}://${USER}:${PASSWORD}@${HOST}/${API}"
	# Welcome to the school of funky shell-nesting.
	{
 		GET -e "${BURL}action=query&format=txt&prop=info&intoken=edit&titles=$PAGE" | awk -v page="$PAGE" -v burl="$BURL" '
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
			title=page
			gsub(" ","%20",title);
			printf "echo | curl -s --post -k --data-urlencode \"text@"
			printf "%s.wiki\" ", page;
			printf "-b wikiToken=" wikiToken " -b wiki_session=" wiki_session;
			printf " \"" burl "format=txt&action=edit&title=%s&token=%s\" \n", title, edittoken
		}
		' | sh
		if [ ! $? = "0" ]; then
			echo "Failed to push. GET returned non-zero" >&2;
			exit 1;
		fi
	
	} | grep result
}


################
# "Proper" execution starts here
################

if [ "x$ACTION" = "xGET" ]; then
	getit
elif [ "x$ACTION" = "xPOST" ]; then
	postit
elif [ "x$ACTION" = "xEDIT" ]; then
	getit
	cp "$PAGE.wiki" "$PAGE.wiki.original.$TIM"
	# Thank Red Hat for the non-vi-clone support: they keep /bin/vi
	# bastardized so you need/want to run 'vim' explicitly. Otherwise
	# there would be no reason to support other editors.
	if [ -z "$EDITOR" ]; then
		vi "$PAGE.wiki"
	else
		$EDITOR "$PAGE.wiki"
	fi
	diff -q "$PAGE.wiki" "$PAGE.wiki.original.$TIM" >/dev/null && {
		echo "Unchanged - not pushing it."
		exit 1;
	}
	postit
elif [ "x$ACTION" = "xCLEAN" ]; then
	# Generate too much crap. One day I will put it in dot-files.
	RMS=*.wiki.*[0-9]*
	echo $RMS
	echo "Shall I kill the above files?"
	echo "[Y]es/No!"
	read yesno
	if [ -z "$yesno" ] || [ "$yesno" = "Y" ] || [ "$yesno" = "y" ] || [ "x$yesno" = "xyes" ]; then
		rm $RMS && echo "Done"
	else
		echo "Bailing!";
	fi
else
	echo "Unknown arguments" >&2
	usage
fi
