#!/bin/bash

cp ./files/pre-commit ../.git/hooks/pre-commit
chmod +x ../.git/hooks/pre-commit
echo "git hooks: pre-commit installed"
