# FILE PATH: Makefile
.PHONY: install lint syntax test
install:
	python3 -m pip install -r requirements-dev.txt
lint:
	yamllint .
	ansible-lint
syntax:
	ansible-playbook playbooks/system-init.yml --syntax-check
test: lint syntax
