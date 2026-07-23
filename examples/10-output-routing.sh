# Route each paired rule to its own output file.
mkdir -p examples-output
./onoff --force --output-dir examples-output --rule errors --start '^BEGIN ERROR$' --end '^END ERROR$' --output errors.txt --rule reports --start-after '^BEGIN REPORT$' --end-before '^END REPORT$' --output reports.txt examples/paired-sections.txt
