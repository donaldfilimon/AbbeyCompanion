# Convenience targets — always use Xcode Swift via scripts/.
.PHONY: check smoke run build test

check:
	./scripts/check.sh

smoke:
	./scripts/smoke.sh

run:
	./scripts/run.sh

build:
	./scripts/check.sh

test:
	./scripts/check.sh
