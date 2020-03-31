#!/usr/bin/env sh
set -euo pipefail

git checkout master
MSG=$(git log -n 1 --format="format:%h %f")
RESULT=$(nix-build)
echo $RESULT
git checkout gh-pages
rm -rf *
cp -r $RESULT/* .
chmod u+w . -R
git add .
git commit -m "$MSG"
git push
git checkout master
