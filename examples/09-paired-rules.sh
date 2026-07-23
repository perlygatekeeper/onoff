# Extract error and report ranges using their own paired end markers.
./onoff --rule errors --start '^BEGIN ERROR$' --end '^END ERROR$' --rule reports --start-after '^BEGIN REPORT$' --end-before '^END REPORT$' examples/paired-sections.txt
