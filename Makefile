.PHONY: verify github-sdk github-sdk-live unit e2e bench

verify:
	./scripts/verify.sh

unit:
	nvim --headless -u tests/minimal_init.lua -l tests/run_unit.lua

github-sdk:
	nvim --headless -u tests/minimal_init.lua -l tests/run_github_sdk.lua

github-sdk-live:
	nvim --headless -u tests/minimal_init.lua -l tests/run_github_sdk_live.lua

e2e:
	nvim --headless -u tests/minimal_init.lua -l tests/run_e2e.lua

bench:
	nvim --headless -u tests/minimal_init.lua -l bench/run.lua
