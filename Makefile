.PHONY: help check syntax test examples status clean

PERL     ?= perl
PROVE    ?= prove
SCRIPT   := onoff
TESTDIR  := test/
EXAMPLES := examples/*.sh

help:
	@echo "onoff Makefile"
	@echo ""
	@echo "  make check     check syntax and run tests"
	@echo "  make syntax    check the Perl script syntax"
	@echo "  make test      run tests with prove"
	@echo "  make examples  run the example commands"
	@echo "  make status    show concise Git status"
	@echo "  make clean     remove editor backup files"

check: syntax test

syntax:
	$(PERL) -c $(SCRIPT)

test:
	$(PROVE) $(TESTDIR)

examples:
	@for example in $(EXAMPLES); do \
		echo "== $$example =="; \
		sh "$$example" || exit 1; \
		echo ""; \
	done

status:
	git status --short

clean:
	find . -name '*~' -delete
	find . -name '*.bak' -delete
	find . -name '.DS_Store' -delete
