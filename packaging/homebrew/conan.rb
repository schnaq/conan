# Homebrew cask for Conan, published via the schnaq/homebrew-tap repo
# (tap name: schnaq/tap). scripts/update-cask.sh rewrites the version and
# sha256 lines on each release and syncs this file into the tap.
#
# The token "conan" collides with homebrew-core's conan *formula* (the C++
# package manager), but casks in a custom tap are namespaced — install with:
#   brew install --cask schnaq/tap/conan
cask "conan" do
  version "0.4.1"
  sha256 "221ff34c01cb937f26907acaa1915cc2dcc313251d8968b129185cd5c3378bc5"

  url "https://github.com/schnaq/conan/releases/download/v#{version}/Conan-#{version}.dmg"
  name "Conan"
  desc "Menu-bar time tracker for parallel projects, layered on top of watson"
  homepage "https://github.com/schnaq/conan"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Conan self-updates via Sparkle; `brew upgrade` skips it unless --greedy.
  auto_updates true
  depends_on macos: :ventura

  app "Conan.app"

  zap trash: [
    "~/Library/Application Support/Conan",
    "~/Library/Preferences/com.schnaq.conan.plist",
  ]
end
