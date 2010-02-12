#!/bin/bash

PROTO="https"
HOST="wiki.varnish-software.com"
API="mediawiki/api.php?"
USER="kristian"
echo password:
read PASSWORD
TIM=$(date +%s)

function usage
{
	echo "RTFS!";
}

PAGE=$2
if [ -z "$2" ]; then
	usage;
	exit 1;
fi

if [ x$1 == "xGET" ]; then
	if [ -f $PAGE.wiki ]; then
		echo "Moving $PAGE.wiki to $PAGE.wiki.$TIM"
		if [ -f $PAGE.wiki.$TIM ]; then
			echo "PANIC! already exist. Stop using loops!";
			sleep 5;
			exit 1;
		fi
		mv $PAGE.wiki $PAGE.wiki.$TIM
	fi

	GET "${PROTO}://${USER}:${PASSWORD}@${HOST}/${API}action=query&titles=${PAGE}&export&format=txt" | awk \
	 'BEGIN {
		 got_text=0;
		 text_end=0;
		 lines=0;
		 buffer[0]="";
	 }
	 / *<text/ {
		 got_text=1;
	 }
	 {
		if (got_text == 1) {
			if (lines == 0) {
				gsub("^ *<text[^>]*>","");
			}
			 buffer[lines++] = $0;
		}
	 }
	 / *<\/text>/ {
		 text_end=lines;
	 }
	 END {
		 for(i = 0; i < text_end; i++) {
			 if (i == text_end-1) {
				 gsub("</text>$","",buffer[i])
			 }
			 print buffer[i];
		}
	 }' > $PAGE.wiki
	if [ $? == 0 ]; then
		echo "$PAGE.wiki created seemingly without errors! Phew.";
	else
		echo "$PAGE.wiki GET-operation may have blown apart.  Abandon ship!"
		exit 2;
	fi
	sed -i 's/\&quot;/"/g' $PAGE.wiki
	sed -i 's/\&amp;/&/g' $PAGE.wiki
	sed -i "s/\&apos;/\\'/g" $PAGE.wiki
	sed -i 's/&lt;/</g' $PAGE.wiki
	sed -i 's/&gt;/>/g' $PAGE.wiki

 elif [ x$1 == "xPOST" ]; then
 	PAGE=$(echo $PAGE | sed s/.wiki$//);
 	BURL="${PROTO}://${USER}:${PASSWORD}@${HOST}/${API}"
 	GET -USse "${BURL}action=query&format=txt&prop=info&intoken=edit&titles=$PAGE" | awk -v page="$PAGE" -v burl="$BURL" '
		BEGIN {
			base = "GET -e \"" burl "\"";
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
		' > .$PAGE.commitcmd
		. .$PAGE.commitcmd
fi
