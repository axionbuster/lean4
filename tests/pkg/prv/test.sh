#!/usr/bin/env bash

rm -rf build
lake build 2>&1 | grep 'error: field.*private'
