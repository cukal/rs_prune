#!/bin/sh
# Check for inconsistencies in xsitools-repository
# Find and delete unused files
# Prune old backups

# Setup
TEMP_DIR=`mktemp -d -t`
HASHES="$TEMP_DIR/hashes"
HASHES_SORTED="$TEMP_DIR/hashes_sorted"
FILES="$TEMP_DIR/files"
FILES_SORTED="$TEMP_DIR/files_sorted"
DELETE_CANDIDATES="$TEMP_DIR/delete_candidates"
MISSING_FILES="$TEMP_DIR/missing_files"
DIFF_OUTPUT="$TEMP_DIR/diff_output"
HASHES_COUNT=0
FILES_COUNT=0

# Functions
logaline() { #Streamline logging
    echo `date +"%d-%m-%y %H:%M:%S"` " - " $@
    # Also log to /scratch/log/syslog
    logger $@
}

collect_hashes() { #Get all hashes from the vmdk files
    logaline "Collecting hashes of all .vmdk files in $1"
    find $1/ -path $1/data -prune -o -name *.vmdk | grep -v '\delta.vmdk$' | grep -v '\sesparse.vmdk$' | grep -v $1/data | while read LINE; do cat "$LINE" ; done | grep -o '^\b[0-9a-f]\{40\}\+\b' > $HASHES
    logaline "Sorting hashes and removing duplicates."
    cat $HASHES | sort | uniq > $HASHES_SORTED
    HASHES_COUNT=`wc -l $HASHES_SORTED | awk '{print $1}'`
    logaline "Total Hashes in vmdks: $HASHES_COUNT"
}

collect_data_file_chunks() { #Get all file chunks from data
    logaline "Generating list of files in ./data."
    #Find took 20 minutes for a big repo
    #find $1/data -type f -exec basename {} \; > $FILES
    #ls took 6 min for the same repo, but I think the fs might be cache-hot
    ls -1R $1/data | grep -o '\b[0-9a-f]\{40\}\+\b' > $FILES
    logaline "Sorting list of files."
    sort $FILES > $FILES_SORTED
    FILES_COUNT=`wc -l $FILES_SORTED | awk '{print $1}'`
    logaline "Files: $FILES_COUNT"
}


# Main
{

# usage examples
if [ -e $1/.xsitools ]
  then
  echo
  logaline "Start rs_prune"
  logaline "$1 seems to be an xsitools-Repository, using it."
  else
  echo "$1 doesn't seem to be an xsitools-Repository."
  echo "Use \"$0 [xsitools-repo-directory]\""
  exit 1
fi

if [ "$2" != "--delete" ]
  then
  echo
  echo "Use \"$0 [xsitools-repo-directory] [--delete]\" to remove unused files (be careful)."
  echo
  else
  echo "\"--delete\" is set, will remove unused files."
fi

if echo $3 | egrep -q '^[0-9]+$';
  then
  logaline "Searching for backup-folders older than $3 days."
  BKPFOLDERS=`find $1/ -maxdepth 1 -type d -mtime +$3 | grep -v data`
  if [ ! -z "$BKPFOLDERS" ]
    then
    logaline "$BKPFOLDERS found, deleting"
    rm -vrf $BKPFOLDERS
    else
    logaline "No backup-folders found."
  fi
  else
  echo
  echo "3rd option can be a number: Delete backup-folders older than ... days."
  echo "You can use this to prune older backups (be careful)."
  echo
fi


collect_hashes $1
collect_data_file_chunks $1


# some checks if everything is valid
echo "Using diff for comparing .vmdk-hashes with filenames in ./data."
diff $HASHES_SORTED $FILES_SORTED -U 0 > $DIFF_OUTPUT

if [ $? -eq 0 ];
  then
  logaline "No unused files found. Every hash in the .vmdk files has a proper file in data-directory. Good."
  logaline "Removing temporary files."
  rm -rf "$TEMP_DIR"
  logaline "End"
  exit 0
  else
  logaline "Checking if hashes in .vmdk files have a file in the data-directory."
  grep "^-[a-f0-9]" $DIFF_OUTPUT | sed 's/^.//' > $MISSING_FILES
  if [ `cat $MISSING_FILES | wc -l` -eq 0 ];
    then
    logaline "Every hash contained in the .vmdk files has a proper file in data-directory. Good."
    grep "^+[a-f0-9]" $DIFF_OUTPUT | sed 's/^.//' > $DELETE_CANDIDATES
    UNUSED_COUNT=`cat $DELETE_CANDIDATES | wc -l`
    logaline "There are $UNUSED_COUNT unused files in ./data:"
    if [ "$2" != "--delete" ];
      then
      cat $DELETE_CANDIDATES
    fi
    else
    logaline "The following `cat $MISSING_FILES | wc -l | awk '{print $1}'` data files are missing:"
    cat $MISSING_FILES
    logaline "Repository is damaged. Leaving everything untouched. Exiting."
    logaline "Removing temporary files."
    rm -rf "$TEMP_DIR"
    logaline "End"
    exit 1
  fi
fi

if [ "$2" == "--delete" ]
  then
  logaline "Counting space used of $1/data."
  logaline "Repo-size before pruning: `du $1/data/ -h -s | awk '{print $1;}'`"
  cat $DELETE_CANDIDATES | while read file
    do
    RMPATH="$1/data/`echo $file | cut -c1`/`echo $file | cut -c2`/`echo $file |cut -c3`/$file"
    logaline "Deleting $RMPATH"
    rm -rf $RMPATH
    done;
  logaline "Counting space used of $1/data."
  logaline "Repo-size after pruning: `du $1/data/ -h -s | awk '{print $1;}'`"
  logaline "Removing empty directories."
  # Busybox find doesnt know -empty.
  find $1/data -type d -depth -exec rmdir -p --ignore-fail-on-non-empty {} \;
  logaline "Counting files in data-directory again."
  # no sort needed here
  # find $1/data -type f -exec basename {} \; > $FILES
  ls -1R $1/data | grep -o '\b[0-9a-f]\{40\}\+\b' > $FILES
  FILES_COUNT=`wc -l $FILES | awk '{print $1}'`
  if [ $FILES_COUNT == $HASHES_COUNT ]
    then
    logaline "Number of files and hashes ($FILES_COUNT) are equal, everything went right."
    else
    logaline "Number of files ($FILES_COUNT) and hashes ($HASHES_COUNT) are different."
    logaline "Perhaps not every file could be deleted. Check it using the logfile."
    logaline "Removing temporary files."
    rm -rf "$TEMP_DIR"
    logaline "End"
    exit 1
  fi
  logaline "Updating Bcnt in .xsitools-file:"
  BCNT=`grep Bcnt $1/.xsitools | awk -F ': ' '{print $2}'`
  echo "Old value of Bcnt: $BCNT."
  echo "Setting actual number of files ($FILES_COUNT) as new value of Bcnt."
  sed -i -e "s/$BCNT/$FILES_COUNT/g" $1/.xsitools
fi

logaline "Removing temporary files."
rm -rf "$TEMP_DIR"
logaline "End: `date`"
} 2>&1 | tee -a $0-`date +"%Y-%m-%d"`.log