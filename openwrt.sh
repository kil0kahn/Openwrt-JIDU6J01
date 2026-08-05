#!/bin/bash
set -e

REPO_DIR=$(pwd)

sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk \
gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
python3-setuptools rsync swig unzip zlib1g-dev file wget ccache tree

git clone --branch v25.12.5 https://github.com/openwrt/openwrt.git
cd openwrt

# Symlink dl-cache from workspace top level
mkdir -p ../dl-cache
rm -rf dl
ln -s ../dl-cache dl

git checkout v25.12.5

git config --global user.email "ci@build.local"
git config --global user.name "CI Builder"

# Unshallow if clone was shallow so git revision ranges work cleanly
if [ -f .git/shallow ]; then
  echo "Unshallowing repo history..."
  git fetch --unshallow origin || true
fi

# Fetch the exact PR branch tip
echo "Fetching PR #23510..."
git fetch origin pull/23510/head:pr-23510 --force

# Apply ALL commits added in PR #23510 on top of v25.12.5
# --empty=drop automatically skips commits that result in no changes (fixes CI build failure)
echo "Applying PR commits..."
git cherry-pick --empty=drop -X theirs v25.12.5..pr-23510


echo "==============================adding initramfs-factory.ubi artifact to JIDU6101 and JIDU6J01=============================="
FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

for DEV in jiorouter_ax6000-jidu6101 jiorouter_ax6000-jidu6j01; do
  # Skip if this device already has the artifact (idempotent)
  if awk "/^define Device\/${DEV}\$/,/^endef/" "$FILOGIC_MK" | grep -q "initramfs-factory.ubi"; then
    echo "[$DEV] initramfs-factory.ubi already present, skipping"
    continue
  fi

  echo "[$DEV] adding initramfs-factory.ubi artifact"

  # Insert the artifact block before the sysupgrade line inside this device's block
  awk -v dev="$DEV" '
    $0 == "define Device/" dev { indev=1 }
    indev && /^  IMAGE\/sysupgrade\.bin := sysupgrade-tar \| append-metadata$/ {
      print "ifeq ($(IB),)"
      print "ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)"
      print "  ARTIFACTS := initramfs-factory.ubi"
      print "  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel"
      print "endif"
      print "endif"
      indev=0
    }
    { print }
  ' "$FILOGIC_MK" > "${FILOGIC_MK}.tmp" && mv "${FILOGIC_MK}.tmp" "$FILOGIC_MK"
done
echo "==============================finished adding initramfs-factory.ubi artifact=============================="


cat <<-EOF >> feeds.conf.default
src-git --root=feeds fantastic_packages https://github.com/fantastic-packages/packages.git;master
EOF

./scripts/feeds update -a
./scripts/feeds install -a

# Copy the device config in
cp "$REPO_DIR/${DEVICE_CONFIG}" .config

make defconfig

make -j$(nproc)

echo "Build completed successfully! Artifacts are located in bin/targets/mediatek/filogic/"
