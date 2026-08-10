#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sudoers_file="$ROOT/stappmus-activity-monitor.sudoers"
launcher="$ROOT/activity-power-reader"
expected='%wheel ALL=(root) NOPASSWD: /usr/lib/stappmus-activity-monitor/activity-sampler --activity-process-power-reader'

[[ -f $sudoers_file ]] ||
  fail "activity process power installs its narrow sudoers rule"
[[ $(<"$sudoers_file") == "$expected" ]] ||
  fail "activity process power sudoers rule permits only the exact collector command"
[[ $(wc -l <"$sudoers_file") -eq 1 ]] ||
  fail "activity process power sudoers rule contains only one allowance"
if command -v visudo >/dev/null 2>&1; then
  visudo -cf "$sudoers_file" >/dev/null ||
    fail "activity process power sudoers rule is not valid sudoers syntax"
fi
pass "activity process power sudoers rule permits only the exact collector command"

[[ -x $launcher ]] ||
  fail "activity process power launcher is not executable"
grep -Fxq 'exec sudo -n /usr/lib/stappmus-activity-monitor/activity-sampler --activity-process-power-reader' "$launcher" ||
  fail "activity process power launcher does not invoke the exact guarded command"
if grep -Eq '\$@|\$\*' "$launcher"; then
  fail "activity process power launcher forwards arbitrary command arguments"
fi
if "$launcher" unexpected >/dev/null 2>&1; then
  fail "activity process power launcher accepts command arguments"
fi
pass "activity process power launcher preserves the exact sudoers command"
