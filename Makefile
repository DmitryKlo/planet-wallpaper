.PHONY: build check test native install
build:
	python3 scripts/build.py
check:
	python3 scripts/audit.py --history
	python3 -m unittest discover -s tests -v
test: check build
native:
	python3 scripts/run_native.py --full
	python3 scripts/run_atmospheres.py --no-build
install: build
	python3 scripts/install.py --start
