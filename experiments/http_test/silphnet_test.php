<?php
// SilphNet HTTP-on-Android experiment - throwaway diagnostic endpoint.
//
// Purpose: find out whether a LOVE 11 mod on Android can reach a PLAIN
// http:// PHP endpoint at all. LOVE 11 has no TLS (no https://), which is
// why the original Gen1Online mod died on Android - but plain HTTP doesn't
// need TLS, and LuaSocket's http module (what the test mod uses) opens a
// raw socket directly rather than going through Android's own Java HTTP
// stack (HttpURLConnection/okhttp), which is specifically what Android's
// cleartext-traffic block targets. So this SHOULD work, the same reason
// raw TCP already does in the real SilphNet mod - but it hasn't been
// confirmed, hence this isolated, no-consequences test.
//
// Upload this file to your site root (e.g. public_html/silphnet_test.php)
// so it's reachable at http://yourdomain.com/silphnet_test.php - note
// PLAIN http, not https. If your host force-redirects everything to
// HTTPS, this test can't tell us anything useful until that's disabled
// for this one path (or tested on a subdomain without the redirect) -
// check by visiting the plain http:// URL in a normal desktop browser
// first and see whether it silently becomes https://.
//
// Safe to delete once the test is done - it holds no data, no DB
// connection, nothing sensitive.

header('Content-Type: text/plain');
echo "SilphNet HTTP test OK - server time: " . date('c') . "\n";
echo "Your request reached this PHP script over plain HTTP.\n";
