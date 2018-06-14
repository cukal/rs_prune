#!/bin/sh

# Check for inconsistencies in xsitools-repository
# Find and delete unused files
# Prune old backups

{
echo "Begin: `date`"
# usage
if [ -e $1/.xsitools ]
  then
  echo "$1 seems to be an xsitools-Repository, using it."
  else
  echo "$1 doesn't seem to be an xsitools-Repository."
  echo "Use \"$0 [xsitools-repo-directory]\""
  exit 1
fi

if [ "$2" != "--delete" ]
  then
  echo "Use \"$0 [xsitools-repo-directory] [--delete]\" to remove unused files (be careful)."
  else
  echo "\"--delete\" is set, will remove unused files."
fi

if echo $3 | egrep -q '^[0-9]+$';
  then
  echo "Searching for backup-folders older than $3 days."
  bkpfolders=`find $1 -type d -maxdepth 1 -regex ".*/[0-9\-]\{14\}" -mtime +$3`
  if [ ! -z "$bkpfolders" ]
    then
    echo "$bkpfolders found, deleting"
    rm -rf $bkpfolders
    else
    echo "No backup-folders found."
  fi
  else
  echo "3rd option can be a number: Delete backup-folders older than ... days."
  echo "You can use this to prune older backups (be careful)."
fi

# Temporary files and variables
temp_dir=`mktemp -d -t`
hashes="$temp_dir/hashes"
hashes_sorted="$temp_dir/hashes_sorted"
files="$temp_dir/files"
files_sorted="$temp_dir/files_sorted"
delete_candidates="$temp_dir/delete_candidates"
missing_files="$temp_dir/missing_files"
diff_output="$temp_dir/diff_output"
hashes_count=0
files_count=0

echo "Collecting hashes of all .vmdk files."
# my old version to exclude delta files:
# find $1/ -path data -prune -o -name *.vmdk -maxdepth 3 | grep -v '\delta.vmdk$' | grep -v '\sesparse.vmdk$' | while read line; do cat "$line" ; done | grep -o '\b[0-9a-f]\{40\}\+\b' > $hashes
# wile-loop inserted for handling filenames with spaces, exclude delta files (snapshots), faster search (thanks to wowbagger)
find $1/ -path $1/data -prune -o -name *.vmdk | grep -v '\delta.vmdk$' | grep -v '\sesparse.vmdk$' | grep -v $1/data | while read LINE; do cat "$LINE" ; done | grep -o '^\b[0-9a-f]\{40\}\+\b' > $hashes
echo "Sorting hashes and removing duplicates."
sort $hashes | uniq > $hashes_sorted
hashes_count=`wc -l $hashes_sorted`
echo "Hashes in vmdks: $hashes_count"

echo "Generating list of files in ./data."
find $1/data -type f -exec basename {} \; > $files
#ls -1R $1/data | grep -o '\b[0-9a-f]\{40\}\+\b' > $files

echo "Sorting list of files."
sort $files > $files_sorted
files_count=`wc -l $files_sorted`

echo "Files: $files_count"

# some checks if everything is valid
echo "Using diff for comparing .vmdk-hashes with filenames in ./data."
diff $hashes_sorted $files_sorted -U 0 > $diff_output

if [ $? -eq 0 ];
  then
  echo "No unused files found. Every hash in the .vmdk files"
  echo "has a proper file in data-directory. Good."
  echo "Removing temporary files."
  rm -rf "$temp_dir"
  echo "End: `date`"
  exit 0
  else
  echo "Checking if hashes in .vmdk files have a file in the data-directory."
  grep "^-[a-f0-9]" $diff_output | sed 's/^.//' > $missing_files
  if [ `cat $missing_files | wc -l` -eq 0 ];
    then
    echo "Every hash contained in the .vmdk files has a proper file in data-directory. Good."
    grep "^+[a-f0-9]" $diff_output | sed 's/^.//' > $delete_candidates
    unused_count=`cat $delete_candidates | wc -l`
    echo "There are $unused_count unused files in ./data:"
    if [ "$2" != "--delete" ];
      then
      cat $delete_candidates
    fi
    else
    echo "The following `cat $missing_files | wc -l` data files are missing:"
    cat $missing_files
    echo "Repository is damaged. Leaving everything untouched. Exiting."
    echo "Removing temporary files."
    rm -rf "$temp_dir"
    echo "End: `date`"
    exit 1
  fi
fi

if [ "$2" == "--delete" ]
  then
  echo "Counting space used of $1/data."
  echo "Repo-size before pruning: `du $1/data/ -h -s | awk '{print $1;}'`"
  cat $delete_candidates | while read file
    do
    rmpath="$1/data/`echo $file | cut -c1-1`/`echo $file | cut -c2-1`/`echo $file |cut -c3-1`/$file"
    echo "Deleting $rmpath"
    rm -rf $rmpath
    done;
  echo "Counting space used of $1/data."
  echo "Repo-size after pruning: `du $1/data/ -h -s | awk '{print $1;}'`"
  echo "Removing empty directories."
  # Busybox find doesnt know -empty.
  find $1/data -type d -depth -exec rmdir -p --ignore-fail-on-non-empty {} \;
  echo "Counting files in data-directory again."
  # no sort needed here
  # find $1/data -type f -exec basename {} \; > $files
  ls -1R $1/data | grep -o '\b[0-9a-f]\{40\}\+\b' > $files
  files_count=`cat $files | wc -l`
  if [ $files_count == $hashes_count ]
    then
    echo "Number of files and hashes ($files_count) are same, everything went right."
    else
    echo "Number of files ($files_count) and hashes ($hashes_count) are different."
    echo "Perhaps not every file could be deleted. Check it using the logfile."
    echo "End: `date`"
    echo "Removing temporary files."
    rm -rf "$temp_dir"
    exit 1
  fi
  echo "Updating Bcnt in .xsitools-file:"
  bcnt=`grep Bcnt $1/.xsitools | awk -F ': ' '{print $2}'`
  echo "Old value of Bcnt: $bcnt."
  echo "Setting actual number of files ($files_count) as new value of Bcnt."
  sed -i -e "s/$bcnt/$files_count/g" $1/.xsitools
fi

echo "Removing temporary files."
rm -rf "$temp_dir"
echo "End: `date`"
} 2>&1 | tee -a $0-`date +"%Y-%m-%d"`.log