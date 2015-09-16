# OASIS_START
# OASIS_STOP

OPTIONS = -use-ocamlfind -I _build

DONTTEST=myocamlbuild.ml setup.ml $(wildcard src/**/*.cppo.*)
QTESTABLE=$(filter-out $(DONTTEST), \
	$(wildcard src/*.ml) \
	$(wildcard src/*.mli) \
	)

qtest-clean:
	@rm -rf qtest/

QTEST_PREAMBLE='open CCFun;; '

qtest-gen:
	@mkdir -p qtest/
	@if which qtest > /dev/null ; then \
		qtest extract --preamble $(QTEST_LWT_PREAMBLE) \
			-o qtest/run_qtest.ml \
			$(QTESTABLE) 2> /dev/null ; \
	else touch qtest/run_qtest.ml ; \
	fi

clean-generated:
	rm **/*.{mldylib,mlpack,mllib} myocamlbuild.ml -f

run-test: build
	./run_qtest.native

test-all: run-test

VERSION=$(shell awk '/^Version:/ {print $$2}' _oasis)

update_next_tag:
	@echo "update version to $(VERSION)..."
	zsh -c 'sed -i "s/NEXT_VERSION/$(VERSION)/g" **/*.ml **/*.mli'
	zsh -c 'sed -i "s/NEXT_RELEASE/$(VERSION)/g" **/*.ml **/*.mli'

.PHONY: examples push_doc tags qtest-gen qtest-clean devel update_next_tag
