.PHONY: test clean

test:
	./scripts/run-tests.sh

clean:
	rm -rf build
