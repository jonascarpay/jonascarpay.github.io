#!/usr/bin/env sh
set -euo pipefail

OUTDIR=${out:-output}
mkdir -p $OUTDIR/posts
TMP=${TMPDIR:-$(mktemp -d)}

echo "<div class=\"header\"> <a href=\"../index.html\">&larr; Posts</a> </div>" > $TMP/back.html
echo "<div class=\"footer\">Made with pandoc and duct tape</div>" > $TMP/footer.html
echo "<div class=\"footer\">Built on $(date +"%Y-%m-%d") at $(git rev-parse --short HEAD)</div>" > $TMP/tocfooter.html

for post in $(find posts/ -type f | sort -r); do
	pandoc $post -o $OUTDIR/${post%.md}.html --standalone -c ../style.css \
		--include-before-body=$TMP/back.html \
		--include-after-body=$TMP/back.html \
		--include-after-body=$TMP/footer.html
	pandoc $post -t markdown --template=static/toc_entry -V url="${post%.md}.html" >> $TMP/toc.md
done

pandoc static/indexheader.md $TMP/toc.md -o $OUTDIR/index.html --standalone -c style.css \
	--include-after-body=$TMP/tocfooter.html \
	--include-after-body=$TMP/footer.html
cp static/style.css $OUTDIR
