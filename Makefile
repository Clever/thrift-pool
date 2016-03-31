# Usage:
# `make` or `make test` runs all the tests

SHELL := /bin/bash
.PHONY: test lint

TESTS=$(shell cd test && ls *.coffee | sed s/\.coffee$$//)

test: $(TESTS) lint

lint:
	node_modules/.bin/lint

$(TESTS):
	NODE_ENV=test node_modules/mocha/bin/mocha --timeout 60000 --compilers coffee:coffee-script/register
