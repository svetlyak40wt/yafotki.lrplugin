#!/bin/sh

VERSION=$(head -1 YaFotki.README | sed 's/.*: //')
ARCHIVE="YaFotki-$VERSION.zip"

cd ..

[ -f "$ARCHIVE" ] && echo "File \"$ARCHIVE\" already exists. Please, remove it first." && exit 1

zip -r "$ARCHIVE" YaFotki.lrplugin -x YaFotki.lrplugin/.git/\*
