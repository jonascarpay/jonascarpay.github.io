source $stdenv/setup

set -exuo pipefail
cd $src

mkdir -p $out/posts
TMP=${TMPDIR:-$(mktemp -d)}

POSTS=$(find posts/ -type f | sort -r)

for post in $POSTS; do

  URL="${post%.md}.html"

  pandoc "$post" \
    -o "$out/$URL" \
    --standalone \
    --syntax-definition=static/nix-syntax.xml \
    -c ../style.css \
    --include-before-body=static/back.html \
    --include-after-body=static/back.html \
    --include-after-body=static/footer.html \
    --include-in-header=static/meta.html \
    --template=static/template.html5

  pandoc "$post" -t html --template=static/toc_entry -V url="$URL" >>"$TMP/toc.html"

  pandoc "$post" -t plain --template=static/rss_entry -V url="$URL" >>"$TMP/rss_body"
done

pandoc static/toc_header.html "$TMP/toc.html" \
  -o "$out/index.html" \
  --standalone \
  --metadata title="jonas's blog" \
  -c style.css \
  --include-after-body=static/footer.html

cat >"$out/rss.xml" <<EOM
<rss version="2.0">
	<channel>
		<title>jonas's blog</title>
		<link>https://jonascarpay.com</link>
		<description>jonas's blog</description>
$(cat $TMP/rss_body)
	</channel>
</rss>
EOM

cp static/style.css $out
cp static/CNAME $out
