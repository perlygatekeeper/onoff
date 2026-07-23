# Name each output file from the subroutine name captured by its start expression.
mkdir -p examples-output/subroutines
./onoff --force --output-dir examples-output/subroutines --rule subs --start-after '^sub (?<name>\S+)$' --end-before '^}$' --output-template '{name}.txt' examples/subroutines.txt
