#!/usr/bin/env bash
set -euo pipefail

OUTDIR=${out:-output}
mkdir -p "$OUTDIR/posts"
TMP=${TMPDIR:-$(mktemp -d)}

POSTS=$(find posts/ -type f | sort -r)

for post in $POSTS; do

	URL="${post%.md}.html"

	pandoc "$post" \
		-o "$OUTDIR/$URL" \
		--standalone \
		-c ../style.css \
		--include-before-body=static/back.html \
		--include-after-body=static/back.html \
		--include-after-body=static/footer.html
	pandoc "$post" -t html --template=static/toc_entry -V url="$URL" >> "$TMP/toc.html"

	pandoc "$post" -t plain --template=static/rss_entry -V url="$URL" >> "$TMP/rss_body"
done

pandoc static/toc_header.html "$TMP/toc.html" \
	-o "$OUTDIR/index.html" \
	--standalone \
	--metadata title="jonas' blog" \
	-c style.css \
	--include-after-body=static/footer.html

cat > "$OUTDIR/rss.xml" << EOM
<rss version="2.0">
	<channel>
		<title>jonas' blog</title>
		<link>https://jonascarpay.com</link>
		<description>jonas' blog</description>
$(cat $TMP/rss_body)
	</channel>
</rss>
EOM

cp static/style.css "$OUTDIR"
cp static/CNAME "$OUTDIR"
