.PHONY: test test-stratum test-cc clean

test: test-stratum test-cc

test-stratum:
	./scripts/run-tests.sh

test-cc:
	./scripts/run-cc-tests.sh

clean:
	rm -rf build
