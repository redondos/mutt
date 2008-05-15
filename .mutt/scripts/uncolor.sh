rm uncolor; for file in colors.*; do cat $file |sed 's/^color/uncolor/' >> uncolor; done
