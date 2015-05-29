#!/bin/bash
DEBUGFILE="createaudio.log"
TMPDIR="/tmp"
MAINDIR=`pwd`

#'tee' logs to $DEBUGFILE *and* prints to stdout.
log ()
{
echo `date` $1 | tee -a $MAINDIR/$DEBUGFILE
}

cd $TMPDIR

#READ PARAMETERS VALUE
while getopts v:nqu:s:e:t: OPTION
do
        case "$OPTION"
        in
                v) VID="$OPTARG";;
                n) NRD="YES";;
                q) QND="YES";;
				u) UPLOAD_SSH_LOCATION="$OPTARG";;
				s) SEASON="$OPTARG";;
				e) EPISODE="$OPTARG";;
				t) TITLE="$OPTARG";;
        esac
done

log "Parameters: v=$VID, n=$NRD" 
if [ "$VID" == "" ]; then echo "Link to the video missing..."; exit; fi

EX="x"
NAME="AstronautiCAST_$SEASON$EX$EPISODE.mp3"
log "Name will be $NAME"
log "Upload will be $UPLOAD_SSH_LOCATION"


# DOWNLOAD AUDIO TRACK FROM YOUTUBE VIDEO PASSED AS PARAMETER
#FILEID=$(echo "$VID" | grep -i -o -e "=[a-z0-9\-]*" | grep  -i -o -e "[a-z0-9\-]*")
FILEID=$(echo "$VID" | cut -d= -f2)
log  "Dowloading $VID ($FILEID)"
youtube-dl -v -k --id -x --audio-format 'wav' --audio-quality 0 -f bestaudio $VID


# Detect quindar tones and cut, if selected with the command line option.
if [ "$QND" == "YES" ]
then
	# APPLY PASSBAND AND NORMALIZE FILTERS WITH CENTER FREQUENCY OF 2500Hz
	log "Looking for Quindar Tones..."
	sox $FILEID.wav tmp.01.quindar.wav band 2.5k 50h norm 2> $DEBUGFILE

	# DETERMINE THE PEAK RMS LEVEL
	PEAK=$(sox tmp.01.quindar.wav -n stats 2>&1 | grep "RMS Pk" | awk -F' ' '{print $4}')
	SLEVEL=$(echo $PEAK-5 | bc)
	log "PEAK=$PEAK, SLEVEL=$SLEVEL"

	# FIND THE BEGINNING OF VALID AUDIO
	BEG_A=$(aubioquiet -s $SLEVEL tmp.01.quindar.wav | grep -e "QUIET" | grep -m 1 -o -e "[0-9\.]*")
	if [ "$BEG_A" == "" ]; then BEG_A="-0.250"; fi
	BEG_B=$(echo $BEG_A+0.250 | bc)

	# FIND THE END OF VALID AUDIO
	END_A=$(aubioquiet -s $SLEVEL tmp.01.quindar.wav | grep -e "NOISY" | tac | grep -m 1 -o -e "[0-9\.]*")
	if [ "$END_A" == "" ]; then END_A="-0.250"; fi
	END_B=$(echo $END_A+0.250 | bc)

	# CALCULATING THE TOTAL LENGTH OF VALID AUDIO
	LEN=$(echo $END_B-$BEG_B | bc)

	# CUTTING THE AUDIO
	if [ "$LEN" == "0" ]
	then
		cp $TMPDIR/$FILEID.wav tmp.02.cutted.wav
		log "Quindar Tones not found..."
	else
		log "Quindar Tones found at $BEG_B and $END_B (duration $LEN)"
		log "Cutting audio..."
		sox $TMPDIR/$FILEID.wav tmp.02.cutted.wav trim $BEG_B $LEN
	fi
else
	log "Skipping Quindar detection"
	log "FILEID = $FILEID"
	mv "$TMPDIR/$FILEID.wav" "$TMPDIR/tmp.02.cutted.wav"
fi


# FILTERING NOISE
if [ "$NRD" == "YES" ]
then
	log "Cleaning background noise..."
	sox $TMPDIR/$FILEID.wav -n trim 0 0.5 noiseprof tmp.noiseprofile # WE USE THE ORIGINAL FILE FOR HAVING EXTRA NOISE
	sox $TMPDIR/tmp.02.cutted.wav tmp.03.cleaned.wav noisered tmp.noiseprofile 0.3 # BUT WE CLEAN THE CUTTED FILE
else
	log "Skipping cleaning background noise..."
	mv $TMPDIR/tmp.02.cutted.wav $TMPDIR/tmp.03.cleaned.wav

fi


# FILTERING WITH NORMALIZER AND COMPRESSION/ENHANCMENT
log "Compressing and expanding..."
sox $TMPDIR/tmp.03.cleaned.wav $TMPDIR/tmp.04.compand.wav compand 0.3,0.8 6:-70,-60,-20 -13 -90 0.2 2>> $DEBUGFILE

# LAME MP3 ENCODING
log "Encoding in mp3 @ 96 kbps"
lame -b 96 $TMPDIR/tmp.04.compand.wav $TMPDIR/$NAME


#ID3tag settings
eyeD3 --force-update --itunes -2 \
-a "AstronautiCAST Media Production" \
-A "AstronautiCAST Season $SEASON" \
-t "AstronautiCAST $EPISODE - $TITLE" \
-n 30 \
-Y `date +%Y` \
-G "Podcast" \
--add-image=$MAINDIR/ACAST.jpg:FRONT_COVER \
$TMPDIR/$NAME

chown .www-data $TMPDIR/$NAME 
log "The file to be uploaded is ready: -> $NAME <-"


if [ $UPLOAD_SSH_LOCATION != "" ] 
then
	log "uploading $NAME to $UPLOAD_SSH_LOCATION"
	scp "$TMPDIR/$NAME" $UPLOAD_SSH_LOCATION
else
	log "Filename  (-n) or upload location (-u) not set"
fi


# CLEANUP OF THE TEMPORARY FILES
rm $TMPDIR/tmp.*
rm $TMPDIR/*.wav
