# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=1.0.0
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
  '7e506d767c9b1996529b83f8adf57d559d8c5bebe6780061c43198cb107e4d1d'
  '0d65c92f6ebf96534d885ee4fc4c164dc3bfb0d54db088bbdc77c19ed7d263c8'
  'b15d687ed8251008731c93a08abfc951a18f09b4de10a3a8852a4d9312290451'
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
