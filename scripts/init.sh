#!/bin/bash
set -euo pipefail

git config --global user.name "farfun"
git config --global user.email "1007530194@qq.com"
git submodule init
git submodule update
