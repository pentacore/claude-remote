.PHONY: test test-unit test-cap test-stack lint-ci

test: test-unit

test-unit:
	docker build -q -f tests/Dockerfile -t claude-remote-tests . >/dev/null
	docker run --rm claude-remote-tests tests/unit

test-cap:
	tests/integration/dind-cap.sh

test-stack:
	tests/integration/stack.sh

lint-ci:
	docker run --rm -v "$(CURDIR):/repo" -w /repo rhysd/actionlint:latest -color
