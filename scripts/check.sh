#!/bin/sh
set -eu

python3 -m unittest discover -s tests -v
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
shellcheck scripts/*.sh image/*.sh image/runtime/*.sh
