# Copyright (c) 2026 Max Lv <max.c.lv@gmail.com>
#
# Licensed under the MIT License. See LICENSE file in the project root for details.

.PHONY: all framework clean

all: framework

framework:
	cd Go/mihomo-bridge && $(MAKE) ios

framework-arm64:
	cd Go/mihomo-bridge && $(MAKE) ios-arm64

clean:
	cd Go/mihomo-bridge && $(MAKE) clean
