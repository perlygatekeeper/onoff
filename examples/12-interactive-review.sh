# Script a repeatable review: reject the first candidate range and accept the second.
./onoff --interactive --responses examples/interactive-responses.txt --start '^BEGIN$' --end '^END$' examples/sections.txt
