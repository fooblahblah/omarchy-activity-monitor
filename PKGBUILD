# Maintainer: Kristoffer Haugland <stappmus at gmail dot com>

pkgname=omarchy-activity-monitor-power-helper
pkgver=1.3.0
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
  'd1df0875a4553c6c9b4f1af943f75444f3f6b74003d3129f7ad2fb7b913f0742'
  '0d65c92f6ebf96534d885ee4fc4c164dc3bfb0d54db088bbdc77c19ed7d263c8'
  '702af495829bd8155fb869000272d08d0a442098098ef3db177c35ddd7df2ba4'
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
