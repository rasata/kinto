SERVER_CONFIG = config/kinto.ini

VIRTUALENV = virtualenv --python=python3
SPHINX_BUILDDIR = docs/_build
VENV := $(shell echo $${VIRTUAL_ENV-.venv})
PYTHON = $(VENV)/bin/python3
DEV_STAMP = $(VENV)/.dev_env_installed.stamp
DOC_STAMP = $(VENV)/.doc_env_installed.stamp
INSTALL_STAMP = $(VENV)/.install.stamp
TEMPDIR := $(shell mktemp -d)

.IGNORE: clean distclean maintainer-clean
.PHONY: all install virtualenv tests

OBJECTS = .venv .coverage

help:
	@echo "Please use 'make <target>' where <target> is one of"
	@echo "  install                     install dependencies and prepare environment"
	@echo "  install-monitoring          enable monitoring features like StatsD and Newrelic"
	@echo "  install-postgres            install postgresql support"
	@echo "  install-dev                 install dependencies and everything needed to run tests"
	@echo "  build-requirements          install all requirements and freeze them in requirements.txt"
	@echo "  update-kinto-admin          update the built-in admin plugin to the last Kinto Admin UI version"
	@echo "  serve                       start the kinto server on default port"
	@echo "  migrate                     run the kinto migrations"
	@echo "  flake8                      run the flake8 linter"
	@echo "  tests                       run all the tests with all the supported python interpreters (same as travis)"
	@echo "  tests-once                  only run the tests once with the default python interpreter"
	@echo "  functional                  run functional test against a real kinto"
	@echo "  clean                       remove *.pyc files and __pycache__ directory"
	@echo "  distclean                   remove *.egg-info files and *.egg, build and dist directories"
	@echo "  maintainer-clean            remove the .tox and the .venv directories"
	@echo "  docs                        build the docs"
	@echo "Check the Makefile to know exactly what each target is doing."

all: install
install: $(INSTALL_STAMP)
$(INSTALL_STAMP): $(PYTHON) setup.py
	$(VENV)/bin/pip install -U pip
	$(VENV)/bin/pip install -Ue .
	touch $(INSTALL_STAMP)

install-monitoring: $(INSTALL_STAMP)
	$(VENV)/bin/pip install -Ue ".[monitoring]"

install-postgres: $(INSTALL_STAMP) $(DEV_STAMP)
	$(VENV)/bin/pip install -Ue ".[postgresql]"

install-dev: $(INSTALL_STAMP) $(DEV_STAMP)
$(DEV_STAMP): $(PYTHON) dev-requirements.txt
	$(VENV)/bin/pip install -Ur dev-requirements.txt
	touch $(DEV_STAMP)

install-docs: $(DOC_STAMP)
$(DOC_STAMP): $(PYTHON) docs/requirements.txt
	$(VENV)/bin/pip install -Ur docs/requirements.txt
	touch $(DOC_STAMP)

virtualenv: $(PYTHON)
$(PYTHON):
	$(VIRTUALENV) $(VENV)

build-requirements:
	$(VIRTUALENV) $(TEMPDIR)
	$(TEMPDIR)/bin/pip install -U pip
	$(TEMPDIR)/bin/pip install -Ue ".[monitoring,postgresql]"
	$(TEMPDIR)/bin/pip freeze | grep -v -- '-e' > requirements.txt

update-kinto-admin:
	rm -fr kinto/plugins/admin/build
	rm -fr kinto/plugins/admin/node_modules
	cd kinto/plugins/admin/; npm install && export REACT_APP_VERSION="$$(npm list | egrep kinto-admin | cut -d @ -f 2)" && npm run build
	cd kinto/plugins/admin/; sed -i "s/ version=\".*\"/ version=\"$$(npm list | egrep kinto-admin | cut -d @ -f 2)\"/g" __init__.py
	git add kinto/plugins/admin/build/static/js/main.*
	git add kinto/plugins/admin/build/static/css/main.*

$(SERVER_CONFIG):
	$(VENV)/bin/kinto --ini $(SERVER_CONFIG) init

NAME := kinto
SOURCE := $(shell git config remote.origin.url | sed -e 's|git@|https://|g' | sed -e 's|github.com:|github.com/|g')
VERSION := $(shell git describe --always --tag)
COMMIT := $(shell git log --pretty=format:'%H' -n 1)
version-file:
	echo '{"name":"$(NAME)","version":"$(VERSION)","source":"$(SOURCE)","commit":"$(COMMIT)"}' > version.json

serve: install-dev $(SERVER_CONFIG) migrate version-file
	$(VENV)/bin/kinto --ini $(SERVER_CONFIG) start --reload

migrate: install $(SERVER_CONFIG)
	$(VENV)/bin/kinto --ini $(SERVER_CONFIG) migrate

tests-once: install-dev version-file install-postgres install-monitoring
	$(VENV)/bin/py.test --cov-report term-missing --cov-fail-under 100 --cov kinto

flake8: install-dev
	$(VENV)/bin/flake8 kinto tests

tests: version-file
	$(VENV)/bin/tox

need-kinto-running:
	@curl http://localhost:8888/v0/ 2>/dev/null 1>&2 || (echo "Run 'make runkinto' before starting tests." && exit 1)

runkinto: install-dev
	$(VENV)/bin/kinto --ini tests/functional.ini start

functional: install-dev need-kinto-running
	$(VENV)/bin/py.test tests/functional.py

clean:
	find . -name '*.pyc' -delete
	find . -name '__pycache__' -type d | xargs rm -fr
	rm -fr docs/_build/

distclean: clean
	rm -fr *.egg *.egg-info/ dist/ build/

maintainer-clean: distclean
	rm -fr .venv/ .tox/

docs: install-docs
	$(VENV)/bin/sphinx-build -a -W -n -b html -d $(SPHINX_BUILDDIR)/doctrees docs $(SPHINX_BUILDDIR)/html
	@echo
	@echo "Build finished. The HTML pages are in $(SPHINX_BUILDDIR)/html/index.html"
