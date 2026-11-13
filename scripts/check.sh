#!/bin/sh
set -eu

python3 -m unittest discover -s tests -v
tofu -chdir=tofu fmt -check -recursive
tofu -chdir=tofu validate
shellcheck scripts/*.sh image/*.sh image/runtime/*.sh
