.SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

SCRIPT := scripts/install-codex.sh
INSTALL_DIR ?= $(HOME)/.local/bin
VERSION ?= latest
UNINSTALL_VERSION ?=

.PHONY: help latest status install uninstall lint config

ifeq ($(filter config,$(MAKECMDGOALS)),config)
  INSTALL_CMD_ARG = config
  STATUS_CMD_ARG = config
else
  INSTALL_CMD_ARG = $(VERSION)
  STATUS_CMD_ARG =
endif

help:
	@echo "codex installer"
	@echo ""
	@echo "Targets:"
	@echo "  latest      Fetch and print latest codex version"
	@echo "  status      Show codex executables on PATH and install dir"
	@echo "  status config  Show the repository config.toml"
	@echo "  install     Install codex to $(INSTALL_DIR)"
	@echo "  install config Install repository config.toml into ~/.codex/config.toml"
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
	@$(SCRIPT) --install-dir $(INSTALL_DIR) status $(STATUS_CMD_ARG)

install:
	@$(SCRIPT) --install-dir $(INSTALL_DIR) install $(INSTALL_CMD_ARG)

uninstall:
	@$(SCRIPT) --install-dir $(INSTALL_DIR) uninstall $(UNINSTALL_VERSION)

lint:
	@bash -n $(SCRIPT)

config:
	@:
