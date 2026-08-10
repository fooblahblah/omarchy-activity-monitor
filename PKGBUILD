# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=1.1.2
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
  'df140c15d2c35f7aa0fa6b01fe893b66505e11be32af9075c2267a7c303b2957'
  '0d65c92f6ebf96534d885ee4fc4c164dc3bfb0d54db088bbdc77c19ed7d263c8'
  '66a1ccb722e18ba8a9590f5c15cb7f1375a286a3ab89915d3b7173b1a30ede9d'
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
