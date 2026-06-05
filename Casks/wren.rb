cask "wren" do
  version "0.9.1"
  sha256 :no_check

  url "https://github.com/thousandflowers/Wren/releases/latest/download/Wren.dmg"
  name "Wren"
  desc "On-device inline completion for every app on your Mac — offline, instant, no subscription"
  homepage "https://github.com/thousandflowers/Wren"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Wren.app"

  uninstall quit: "com.thousandflowers.wren"

  # NOTE: deliberately does NOT zap "~/Library/Application Support/Parrot" — that directory
  # (model files) is shared with the Parrot app; removing it on a Wren uninstall would delete
  # Parrot's data too. Only wren-specific paths are zapped.
  zap trash: [
    "~/Library/Caches/com.thousandflowers.wren",
    "~/Library/HTTPStorages/com.thousandflowers.wren",
    "~/Library/Preferences/com.thousandflowers.wren.plist",
  ]
end
