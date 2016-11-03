# Usage:
# `make` or `make test` runs all the tests

SHELL := /bin/bash
.PHONY: test

TESTS=$(shell cd test && ls *.coffee | sed s/\.coffee$$//)

build: index.js

index.js: lib/index.coffee
	node_modules/coffee-script/bin/coffee --bare -o . -c lib/index.coffee

test: $(TESTS)

$(TESTS):
	NODE_ENV=test node_modules/mocha/bin/mocha --timeout 60000 --compilers coffee:coffee-script/register
