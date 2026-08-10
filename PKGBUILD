# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=1.2.1
pkgrel=1
pkgdesc="Optional root-only RAPL reader for the Omarchy Activity Monitor plugin"
arch=('any')
url="https://github.com/stappmus/omarchy-activity-monitor"
license=('MIT')
depends=('bash' 'coreutils' 'sudo')
options=('!debug')
source=(
  'activity-stats'
  'stappmus-activity-monitor.sudoers'
  'README.md'
  'LICENSE'
)
sha256sums=(
  'a2d5b53cb35c2f22b3f318decd05a020d5430c09f9b76720e2d0f0a06a22d8a5'
  '0d65c92f6ebf96534d885ee4fc4c164dc3bfb0d54db088bbdc77c19ed7d263c8'
  'f2c7caf0a6995844e67c0f9c1a985e0dfb4fc2fa9b24a8a713c0eebf1001cbc4'
  'dd56ead2d3379b1d8298bbd1b905188b21894c46312ea4186b2afde9b03b3184'
)

check() {
  bash -n activity-stats
  grep -Fxq \
    '%wheel ALL=(root) NOPASSWD: /usr/lib/stappmus-activity-monitor/activity-stats --activity-process-power-reader' \
    stappmus-activity-monitor.sudoers
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf stappmus-activity-monitor.sudoers >/dev/null
  fi
}

package() {
  install -Dm755 activity-stats \
    "$pkgdir/usr/lib/stappmus-activity-monitor/activity-stats"
  install -Dm440 stappmus-activity-monitor.sudoers \
    "$pkgdir/etc/sudoers.d/stappmus-activity-monitor"
  install -Dm644 README.md \
    "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 LICENSE \
    "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
