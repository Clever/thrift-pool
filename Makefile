.PHONY: test

test:
	node_modules/mocha/bin/mocha --timeout 60000 --compilers coffee:coffee-script/register
