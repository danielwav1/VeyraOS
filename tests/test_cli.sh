#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "CLI"

commands="help version info sys checkup desktop update clean repair logs network theme about report"

out=$(veyra help); rc=$?
expect_eq "help exits 0" 0 "$rc"
for c in $commands; do expect_contains "help lists '$c'" "$out" "  $c "; done

out=$(veyra); rc=$?
expect_eq "no arguments shows help" 0 "$rc"
expect_contains "no arguments output is the usage text" "$out" "Usage: veyra"

want="$(tr -d '[:space:]' < "$ROOT/VERSION")"
out=$(veyra version)
expect_contains "version shows the number" "$out" "VeyraOS $want"
expect_contains "version names the edition" "$out" "Live"
expect_eq "version --short" "$want" "$(veyra version --short)"

out=$(veyra info); rc=$?
expect_eq "info exits 0" 0 "$rc"
expect_contains "info names the system" "$out" "VeyraOS 0.3 Live"
expect_contains "info shows the kernel" "$out" "$(uname -r)"

out=$(veyra sys); rc=$?
expect_eq "sys exits 0" 0 "$rc"
expect_contains "sys shows kernel release" "$out" "$(uname -r)"
expect_contains "sys shows architecture" "$out" "$(uname -m)"
expect_contains "sys shows memory" "$out" "Available"

err=$(veyra frobnicate 2>&1 >/dev/null); rc=$?
expect_eq "unknown command exits 2" 2 "$rc"
expect_contains "unknown command is reported" "$err" "unknown command 'frobnicate'"
expect_contains "unknown command points to help" "$err" "veyra help"

err=$(env PATH=/nonexistent NO_COLOR=1 /bin/bash "$CLI" network 2>&1 >/dev/null); rc=$?
expect_eq "network without 'ip' exits 3" 3 "$rc"
expect_contains "missing tool is named" "$err" "ip"
expect_contains "missing tool gets a package hint" "$err" "iproute2"

err=$(env PATH=/nonexistent NO_COLOR=1 /bin/bash "$CLI" logs 2>&1 >/dev/null); rc=$?
expect_eq "logs without journalctl exits 3" 3 "$rc"

err=$(veyra logs --lines abc 2>&1 >/dev/null); rc=$?
if command -v journalctl >/dev/null; then expect_eq "logs rejects a non-numeric line count" 2 "$rc"; else skip "logs argument check" "journalctl missing"; fi

out=$(veyra checkup); rc=$?
if (( rc == 0 || rc == 1 )); then pass "checkup returns a valid status ($rc)"; else fail "checkup status" "got $rc"; fi
expect_contains "checkup prints a summary" "$out" "Summary:"
expect_contains "checkup recognises VeyraOS identity" "$out" "os-release identifies VeyraOS"

out=$(veyra desktop); rc=$?
expect_eq "desktop exits 0" 0 "$rc"
expect_contains "desktop has an appearance section" "$out" "Appearance"

if command -v apt-get >/dev/null; then
    out=$(veyra clean </dev/null 2>&1); rc=$?
    expect_eq "clean without a terminal changes nothing and exits 0" 0 "$rc"
    out=$(veyra repair </dev/null 2>&1); rc=$?
    if (( rc == 0 || rc == 1 )); then pass "repair without a terminal never prompts ($rc)"; else fail "repair status" "got $rc"; fi
else
    skip "clean/repair" "apt-get missing"
fi

tmp=$(mktemp -d)
mkdir -p "$tmp/themes"
cp "$ROOT"/desktop/themes/profiles/*.theme "$tmp/themes/"
out=$(VEYRA_SHARE_DIR="$tmp" veyra theme list); rc=$?
expect_eq "theme list exits 0" 0 "$rc"
expect_contains "theme list shows veyra-dark" "$out" "veyra-dark"
expect_contains "theme list shows veyra-light" "$out" "veyra-light"
err=$(VEYRA_SHARE_DIR="$tmp" veyra theme set nope 2>&1 >/dev/null); rc=$?
expect_eq "theme set with unknown name exits 2" 2 "$rc"
err=$(VEYRA_SHARE_DIR="$tmp" veyra theme set 2>&1 >/dev/null); rc=$?
expect_eq "theme set without a name exits 2" 2 "$rc"

VEYRA_REPORT_DIR="$tmp" veyra report >/dev/null; rc=$?
expect_eq "report exits 0" 0 "$rc"
rpt=$(ls "$tmp"/veyra-report-*.txt 2>/dev/null | head -n 1)
if [[ -n $rpt ]]; then
    expect_eq "report file is private (600)" 600 "$(stat -c %a "$rpt")"
    body=$(cat "$rpt")
    host=$(uname -n)
    if (( ${#host} >= 3 )); then expect_not_contains "report hides the hostname" "$body" "$host"; fi
    expect_not_contains "report hides the home path" "$body" "$HOME/"
    expect_contains "report contains release data" "$body" "VeyraOS"
else
    fail "report file was not written"
fi
printf 'host test 192.168.1.20 aa:bb:cc:dd:ee:ff\n' | bash -c 'source <(sed -n "/^regex_escape()/,/^collect_report()/p" "$0" | sed "\$d"); anonymize' "$CLI" > "$tmp/anon.txt" 2>/dev/null
expect_contains "anonymizer masks IPv4" "$(cat "$tmp/anon.txt")" "x.x.x.x"
expect_contains "anonymizer masks MAC" "$(cat "$tmp/anon.txt")" "xx:xx:xx:xx:xx:xx"
rm -rf "$tmp"

finish
