#!/bin/sh

VERSION=$(head -1 YaFotki.README | sed 's/.*: //')

cd ..

zip -r YaFotki-$VERSION.zip YaFotki.lrplugin -x YaFotki.lrplugin/.git/\*
