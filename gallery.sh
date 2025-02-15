#!/bin/bash

# gallery.sh
# Author: Nils Knieling - https://github.com/Cyclenerd/gallery_shell
# Inspired by: Shapor Naghibzadeh - https://github.com/shapor/bashgal

#########################################################################################
#### Configuration Section
#########################################################################################

MY_HEIGHT_SMALL=187
MY_WIDTH_SMALL=250
MY_HEIGHT_LARGE=833 # correct height for 4:3
MY_QUALITY=85
MY_THUMBDIR="__thumbs"
MY_INDEX_HTML_FILE="index.html"
MY_TITLE=${PWD##*/}
MY_FOOTER='Created with <a href="https://github.com/vjay82/gallery_shell">gallery.sh</a>'

# Use convert from ImageMagick
MY_CONVERT_COMMAND="convert" 
# Use JHead for EXIF Information
MY_EXIF_COMMAND="jhead"
HEIC_EXIF_COMMAND="exiftool"

HEIC_TO_JPG_QUALITY=96

# Bootstrap 4
MY_CSS="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.6.0/css/bootstrap.min.css"

# Debugging output
# true=enable, false=disable 
MY_DEBUG=true

#########################################################################################
#### End Configuration Section
#########################################################################################


MY_SCRIPT_NAME=$(basename "$0")
MY_DATETIME=$(date -u "+%Y-%m-%d %H:%M:%S")
MY_DATETIME+=" UTC"

function max6 {
   while [ `jobs | wc -l` -ge 6 ]
   do
      sleep 1
   done
}

function usage {
	MY_RETURN_CODE="$1"
	echo -e "Usage: $MY_SCRIPT_NAME [-t <title>] [-d <thumbdir>] [-h]:
	[-t <title>]\\t sets the title (default: $MY_TITLE)
	[-d <thumbdir>]\\t sets the thumbdir (default: $MY_THUMBDIR)
	[-h]\\t\\t displays help (this message)"
	exit "$MY_RETURN_CODE"
}

function debugOutput(){
	if [[ "$MY_DEBUG" == true ]]; then
		echo "$*" # if debug variable is true, echo whatever's passed to the function
	fi
}

function getFileSize(){
	# Be aware that BSD stat doesn't support --version and -c
	if stat --version &>/dev/null; then
		# GNU
		MY_FILE_SIZE=$(stat -c %s "$1" | awk '{$1/=1000000;printf "%.2fMB\n",$1}')
	else
		# BSD
		MY_FILE_SIZE=$(stat -f %z "$1" | awk '{$1/=1000000;printf "%.2fMB\n",$1}')
	fi
	echo "$MY_FILE_SIZE"
}

while getopts ":t:d:h" opt; do
	case $opt in
	t)
		MY_TITLE="$OPTARG"
		;;
	d)
		MY_THUMBDIR="$OPTARG"
		;;
	h)
		usage 0
		;;
	*)
		echo "Invalid option: -$OPTARG"
		usage 1
		;;
	esac
done

debugOutput "- $MY_SCRIPT_NAME : $MY_DATETIME"

### Check Commands
command -v $MY_CONVERT_COMMAND >/dev/null 2>&1 || { echo >&2 "!!! $MY_CONVERT_COMMAND it's not installed.  Aborting."; exit 1; }
command -v $MY_EXIF_COMMAND >/dev/null 2>&1 || { echo >&2 "!!! $MY_EXIF_COMMAND it's not installed.  Aborting."; exit 1; }
command -v rename >/dev/null 2>&1 || { echo >&2 "!!! rename it's not installed.  Aborting."; exit 1; }

### Clean thumbs dir
rm -rf "$MY_THUMBDIR"

### Create Folders
[[ -d "$MY_THUMBDIR" ]] || mkdir "$MY_THUMBDIR" || exit 2

MY_HEIGHTS[0]=$MY_HEIGHT_SMALL
MY_HEIGHTS[1]=$MY_HEIGHT_LARGE
for MY_RES in ${MY_HEIGHTS[*]}; do
	[[ -d "$MY_THUMBDIR/$MY_RES" ]] || mkdir -p "$MY_THUMBDIR/$MY_RES" || exit 3
done

#### Create Startpage
debugOutput "$MY_INDEX_HTML_FILE"
cat > "$MY_INDEX_HTML_FILE" << EOF
<!DOCTYPE HTML>
<html lang="en">
<head>
	<meta charset="utf-8">
	<title>$MY_TITLE</title>
	<meta name="viewport" content="width=device-width">
	<meta name="robots" content="noindex, nofollow">
	<link rel="stylesheet" href="$MY_CSS">
<style>
.btn {
    margin-bottom: 5px;
}
a>img {
	height: ${MY_HEIGHT_SMALL}px;
	width: ${MY_WIDTH_SMALL}px;
	object-fit: contain;
}
</style>
</head>
<body>
<header>
	<div class="navbar navbar-dark bg-dark shadow-sm">
		<div class="container">
			<a href="#" class="navbar-brand">
				<strong>$MY_TITLE</strong>
			</a>
		</div>
	</div>
</header>
<main class="container">
EOF

### Rename all files to their correct extensions
rename 's/\.jpeg/\.jpg/' *.jpeg 2> /dev/null
rename 's/\.JPG/\.JPGTMP/' *.JPG 2> /dev/null
rename 's/\.JPGTMP/\.jpg/' *.JPGTMP 2> /dev/null
rename 's/\.HEIC/\.HEICTMP/' *.HEIC 2> /dev/null
rename 's/\.HEICTMP/\.heic/' *.HEICTMP 2> /dev/null
rename 's/\.MOV/\.MOVTMP/' *.MOV 2> /dev/null
rename 's/\.MOVTMP/\.mov/' *.MOVTMP 2> /dev/null

### Convert heic to jpg
if [[ $(find . -maxdepth 1 -type f -iname \*.heic | wc -l) -gt 0 ]]; then
    for MY_FILENAME in *.heic; do
        JPG_FILENAME=${MY_FILENAME%.heic}.jpg
        if [ -f "$JPG_FILENAME" ]; then
            debugOutput "Skipping converting heic to jpg: $MY_FILENAME"
        else
            debugOutput "Converting heic to jpg: $MY_FILENAME"
            max6 ; $MY_CONVERT_COMMAND -auto-orient -quality $HEIC_TO_JPG_QUALITY -format jpg "$MY_FILENAME" "$JPG_FILENAME" &
        fi
    done
    wait
fi

### Photos (JPG)
if [[ $(find . -maxdepth 1 -type f -iname \*.jpg | wc -l) -gt 0 ]]; then

echo '<div class="row row-cols-sm-1 row-cols-md-2 row-cols-lg-3 row-cols-xl-4 py-5">' >> "$MY_INDEX_HTML_FILE"
### Generate Thumbnail Images
MY_NUM_FILES=0
for MY_FILENAME in *.jpg; do
	MY_FILELIST[$MY_NUM_FILES]=$MY_FILENAME
	(( MY_NUM_FILES++ ))
	for MY_RES in ${MY_HEIGHTS[*]}; do
		if [[ ! -s $MY_THUMBDIR/$MY_RES/$MY_FILENAME ]]; then
			# prefer converting from the original if it has not been the jpg
            MY_BASE_FILENAME=${MY_FILENAME%.jpg}
	        HEIC_FILENAME=${MY_BASE_FILENAME}.heic
			READ_FROM_FILE=$MY_FILENAME
            if [ -f "$HEIC_FILENAME" ]; then
                READ_FROM_FILE=$HEIC_FILENAME
            fi
            debugOutput converting "$READ_FROM_FILE" to "$MY_THUMBDIR/$MY_RES/$MY_FILENAME"
            max6 ; $MY_CONVERT_COMMAND -auto-orient -strip -quality $MY_QUALITY -resize x$MY_RES "$READ_FROM_FILE" "$MY_THUMBDIR/$MY_RES/$MY_FILENAME" &
		fi
	done
	cat >> "$MY_INDEX_HTML_FILE" << EOF
<div class="col">
	<p>
		<a href="$MY_THUMBDIR/$MY_FILENAME.html"><img src="$MY_THUMBDIR/$MY_HEIGHT_SMALL/$MY_FILENAME" alt="Thumbnail: $MY_FILENAME" class="rounded mx-auto d-block"></a>
	</p>
</div>
EOF
done
echo '</div>' >> "$MY_INDEX_HTML_FILE"

### Generate the HTML Files for Images in thumbdir
MY_FILE=0
while [[ $MY_FILE -lt $MY_NUM_FILES ]]; do
	MY_FILENAME=${MY_FILELIST[$MY_FILE]}
	MY_BASE_FILENAME=${MY_FILENAME%.jpg}
	HEIC_FILENAME=${MY_BASE_FILENAME}.heic
	MY_PREV=""
	MY_NEXT=""
	[[ $MY_FILE -ne 0 ]] && MY_PREV=${MY_FILELIST[$((MY_FILE - 1))]}
	[[ $MY_FILE -ne $((MY_NUM_FILES - 1)) ]] && MY_NEXT=${MY_FILELIST[$((MY_FILE + 1))]}
	MY_IMAGE_HTML_FILE="$MY_THUMBDIR/$MY_FILENAME.html"
	MY_EXIF_INFO=$($MY_EXIF_COMMAND "$MY_FILENAME")
	MY_FILESIZE=$(getFileSize "$MY_FILENAME")
	debugOutput "$MY_IMAGE_HTML_FILE"
	cat > "$MY_IMAGE_HTML_FILE" << EOF
<!DOCTYPE HTML>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$MY_FILENAME</title>
<meta name="viewport" content="width=device-width">
<meta name="robots" content="noindex, nofollow">
<link rel="stylesheet" href="$MY_CSS">
</head>
<body>
<header>
	<div class="navbar navbar-dark bg-dark shadow-sm">
		<div class="container">
			<a href="../index.html" class="navbar-brand">
				<strong>$MY_TITLE</strong>
			</a>
		</div>
	</div>
</header>
<main class="container">
EOF

	# Pager
	echo '<div class="row py-3"><div class="col text-left">' >> "$MY_IMAGE_HTML_FILE"
	if [[ $MY_PREV ]]; then
		echo '<a href="'"$MY_PREV"'.html" accesskey="p" title="⌨️ PC: [Alt]+[Shift]+[P] / MAC: [Control]+[Option]+[P]" class="btn btn-secondary " role="button">&laquo; Previous</a>' >> "$MY_IMAGE_HTML_FILE"
	else
		echo '<a href="#" class="btn btn-secondary  disabled" role="button" aria-disabled="true">&laquo; Previous</a>' >> "$MY_IMAGE_HTML_FILE"
	fi
	cat >> "$MY_IMAGE_HTML_FILE" << EOF
</div>
<div class="col d-none d-md-block text-center"><h3>$MY_BASE_FILENAME</h3></div>
<div class="col text-right">
EOF
	if [[ $MY_NEXT ]]; then
		echo '<a href="'"$MY_NEXT"'.html" accesskey="n" title="⌨️ PC: [Alt]+[Shift]+[N] / MAC: [Control]+[Option]+[N]" class="btn btn-secondary ">Next &raquo;</a>' >> "$MY_IMAGE_HTML_FILE"
	else
		echo '<a href="#" class="btn btn-secondary  disabled" role="button" aria-disabled="true">Next &raquo;</a>' >> "$MY_IMAGE_HTML_FILE"
	fi
	echo '</div></div>' >> "$MY_IMAGE_HTML_FILE"

	cat >> "$MY_IMAGE_HTML_FILE" << EOF
<div class="row">
	<div class="col">
		<p><img src="$MY_HEIGHT_LARGE/$MY_FILENAME" style="width:100%; max-height: ${MY_HEIGHT_LARGE}px; object-fit: contain" class="img-fluid" alt="Image: $MY_FILENAME"></p>
	</div>
</div>
<div class="row" style="flex-direction: column">
EOF

	JPG_DOWNLOAD_TITLE="Download Original (JPEG Format)"
	if [ -f "$HEIC_FILENAME" ]; then
		JPG_DOWNLOAD_TITLE="Download Converted to JPEG Format"
		HEIC_FILESIZE=$(getFileSize "$HEIC_FILENAME")
		cat >> "$MY_IMAGE_HTML_FILE" << EOF
	<div class="col">
		<p><a class="btn btn-primary" style="width:100%" href="../$HEIC_FILENAME">Download Original (HEIC Format) ($HEIC_FILESIZE)</a></p>
	</div>
EOF
	fi

	cat >> "$MY_IMAGE_HTML_FILE" << EOF
	<div class="col">
		<p><a class="btn btn-primary" style="width:100%" href="../$MY_FILENAME">$JPG_DOWNLOAD_TITLE ($MY_FILESIZE)</a></p>
	</div>
</div>
EOF

	# EXIF
	if [[ $MY_EXIF_INFO ]]; then
		cat >> "$MY_IMAGE_HTML_FILE" << EOF
<div class="row">
EOF

		if [ -f "$HEIC_FILENAME" ]; then
			HEIC_EXIF_INFO=$($HEIC_EXIF_COMMAND "$HEIC_FILENAME")
			cat >> "$MY_IMAGE_HTML_FILE" << EOF
<div class="col">
<pre>
<b>HEIC Exif:</b>
$HEIC_EXIF_INFO
</pre>
</div>
EOF
		fi
		cat >> "$MY_IMAGE_HTML_FILE" << EOF
<div class="col">
<pre>
<b>JPEG Exif:</b>
$MY_EXIF_INFO
</pre>
</div>
</div>
EOF
	fi

	# Footer
	cat >> "$MY_IMAGE_HTML_FILE" << EOF
</main> <!-- // main container -->
<br>
<footer class="footer mt-auto py-3 bg-light">
	<div class="container">
		<span class="text-muted">$MY_FOOTER - $MY_DATETIME</span>
	</div>
</footer>
</body>
</html>
EOF
	(( MY_FILE++ ))
done

fi

### Movies (MOV or MP4)
if [[ $(find . -maxdepth 1 -type f -iname \*.mov  -o -iname '*.mp4' | wc -l) -gt 0 ]]; then
	cat >> "$MY_INDEX_HTML_FILE" << EOF
	<div class="row">
		<div class="col">
			<div class="page-header"><h2>Movies</h2></div>
		</div>
	</div>
	<div class="row">
	<div class="col">
EOF
	if [[ $(find . -maxdepth 1 -type f -iname \*.mov | wc -l) -gt 0 ]]; then
	for MY_FILENAME in *.[mM][oO][vV]; do
		MY_FILESIZE=$(getFileSize "$MY_FILENAME")
		cat >> "$MY_INDEX_HTML_FILE" << EOF
<a href="$MY_FILENAME" class="btn btn-primary" role="button">$MY_FILENAME ($MY_FILESIZE)</a>
EOF
	done
	fi
	if [[ $(find . -maxdepth 1 -type f -iname \*.mp4 | wc -l) -gt 0 ]]; then
	for MY_FILENAME in *.[mM][pP]4; do
		MY_FILESIZE=$(getFileSize "$MY_FILENAME")
		cat >> "$MY_INDEX_HTML_FILE" << EOF
<a href="$MY_FILENAME" class="btn btn-primary" role="button">$MY_FILENAME ($MY_FILESIZE)</a>
EOF
	done
	fi
	echo '</div></div>' >> "$MY_INDEX_HTML_FILE"
fi

### Downloads (ZIP)
rm "Images in HEIC Format.zip" "Images in JPEG Format.zip" "Movies in MOV Format.zip" 2> /dev/null
zip "Images in HEIC Format.zip" *.heic &
zip "Images in JPEG Format.zip" *.jpg &
zip "Movies in MOV Format.zip" *.mov &
wait
if [[ $(find . -maxdepth 1 -type f -iname \*.zip | wc -l) -gt 0 ]]; then
	cat >> "$MY_INDEX_HTML_FILE" << EOF
	<div class="row" style="margin-top:30px">
		<div class="col">
			<div class="page-header"><h2>Downloads</h2></div>
		</div>
	</div>
	<div class="row">
	<div class="col">
EOF
	for MY_FILENAME in *.[zZ][iI][pP]; do
		MY_FILESIZE=$(getFileSize "$MY_FILENAME")
		cat >> "$MY_INDEX_HTML_FILE" << EOF
<a href="$MY_FILENAME" class="btn btn-primary" role="button">$MY_FILENAME ($MY_FILESIZE)</a>
EOF
	done
	echo '</div></div>' >> "$MY_INDEX_HTML_FILE"
fi

### Footer
cat >> "$MY_INDEX_HTML_FILE" << EOF
</main> <!-- // main container -->
<br>
<footer class="footer mt-auto py-3 bg-light">
	<div class="container">
		<span class="text-muted">$MY_FOOTER - $MY_DATETIME</span>
	</div>
</footer>
</body>
</html>
EOF

debugOutput "= done"
