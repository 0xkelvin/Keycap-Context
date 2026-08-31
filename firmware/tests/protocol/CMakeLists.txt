# SPDX-License-Identifier: Apache-2.0
cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(keycap_protocol_tests)
target_sources(app PRIVATE
  src/main.c
  ../../src/protocol.c
  ../../src/gesture.c
  ../../src/lighting.c
  ../../src/line_reader.c
  ../../src/audio_bands.c
)
target_include_directories(app PRIVATE ../../src)
