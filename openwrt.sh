#!/bin/bash
set -e

REPO_DIR=$(pwd)

sudo apt update
sudo apt install -y \
    build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git \
    libncurses5-dev libssl-dev python3-setuptools \
    rsync swig unzip zlib1g-dev file wget ccache tree

git clone --depth=200 --branch v25.12.5 https://github.com/openwrt/openwrt.git
cd openwrt

mkdir -p ../dl-cache
rm -rf dl
ln -s ../dl-cache dl

git checkout v25.12.5

git config --global user.email "ci@build.local"
git config --global user.name "CI Builder"

echo "Fetching PR #23510..."
git fetch origin pull/23510/head:pr-23510 --force

echo "Cherry-picking Jio commits..."
git log pr-23510 \
    --oneline \
    --grep="jio\|jidu" \
    --regexp-ignore-case \
    --format="%H" |
tac |
grep -v "$(git log --format="%H" | head -100 | tr '\n' '\|' | sed 's/|$//')" |
xargs -r git cherry-pick -X theirs

echo "Updating feeds..."
./scripts/feeds update -a
./scripts/feeds install -a

echo "Generating vanilla config..."

cat > .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_jiorouter_ax6000-jidu6j01=y
EOF

make defconfig

cp .config /tmp/vanilla-jidu6j01.config

echo "Generating diff..."

diff \
    /tmp/vanilla-jidu6j01.config \
    "$REPO_DIR/${DEVICE_CONFIG}" \
    > /tmp/vanilla-diff.txt || true

echo
echo "Done."
echo
echo "Artifacts:"
echo "  /tmp/vanilla-jidu6j01.config"
echo "  /tmp/vanilla-diff.txt"

echo
echo "Diff summary:"
wc -l /tmp/vanilla-diff.txt || true
