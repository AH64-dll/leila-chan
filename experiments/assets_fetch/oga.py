"""OpenGameArt helper. search: list CC0 results; info: files+license of a page."""
import re, sys, urllib.request, urllib.parse, html
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0"}
def get(u):
    import time
    for attempt in range(4):
        try:
            time.sleep(2)
            return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=40).read().decode("utf8", "ignore")
        except Exception as e:
            print("  retry", attempt, e, file=sys.stderr); time.sleep(8)
    return ""
def search(q, kind):  # kind: 12 music, 13 sfx ; license tid 4 = CC0
    u = ("https://opengameart.org/art-search-advanced?keys=" + urllib.parse.quote(q) +
         f"&field_art_type_tid%5B%5D={kind}&field_art_licenses_tid%5B%5D=4&sort_by=count&sort_order=DESC")
    page = get(u)
    return list(dict.fromkeys(re.findall(r'<a href="/content/([^"]+)">([^<]+)</a>', page)))[:8]
def info(slug):
    p = get("https://opengameart.org/content/" + slug)
    files = [f for f in re.findall(r'https://opengameart.org/sites/default/files/[^"]+', p)
             if not re.search(r'/(css|js|styles)/|\.(png|jpe?g|gif)$', f)]
    lic = re.findall(r'field-name-field-art-licenses.*?<div class="field-items">(.*?)</div></div>', p, re.S)
    lic = re.sub(r"<[^>]+>", " ", lic[0]) if lic else "?"
    return sorted(set(files)), " ".join(lic.split())
if __name__ == "__main__":
    if sys.argv[1] == "search":
        kind = sys.argv[2]
        for q in sys.argv[3:]:
            print(f"## {q}")
            for slug, title in search(q, kind): print(f"  {slug} | {html.unescape(title)}")
    else:
        for s in sys.argv[2:]:
            f, l = info(s); print(f"== {s} [{l}]"); [print("  ", x) for x in f]
