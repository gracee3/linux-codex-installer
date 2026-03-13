.SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

SCRIPT := scripts/install-codex.sh
INSTALL_DIR ?= $(HOME)/.local/bin
VERSION ?= latest
UNINSTALL_VERSION ?=

.PHONY: help latest status install uninstall lint

help:
	@echo "codex installer"
	@echo ""
	@echo "Targets:"
	@echo "  latest      Fetch and print latest codex version"
	@echo "  status      Show codex executables on PATH and install dir"
	@echo "  install     Install codex to $(INSTALL_DIR)"
	@echo "  uninstall   Uninstall codex from $(INSTALL_DIR)"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION           Version to install (default: latest)"
	@echo "  UNINSTALL_VERSION Version to uninstall or 'all' (default: current only)"
	@echo "  INSTALL_DIR       Install directory override"
	@echo ""
	@echo "Examples:"
	@echo "  make latest"
	@echo "  make status"
	@echo "  make install VERSION=0.114.0"
	@echo "  make uninstall UNINSTALL_VERSION=all"
	@echo "  make install INSTALL_DIR=~/bin"

latest:
	@$(SCRIPT) latest

status:
	@$(SCRIPT) --install-dir $(INSTALL_DIR) status

install:
	@$(SCRIPT) --install-dir $(INSTALL_DIR) install $(VERSION)

uninstall:
	@$(SCRIPT) --install-dir $(INSTALL_DIR) uninstall $(UNINSTALL_VERSION)

lint:
	@bash -n $(SCRIPT)
