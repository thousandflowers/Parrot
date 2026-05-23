cask "parrot" do
  version "0.9.1"
  sha256 "UPDATE_AFTER_NOTARIZED_RELEASE"

  url "https://github.com/thousandflowers/Parrot/releases/download/v#{version}/Parrot.dmg",
      verified: "github.com/thousandflowers/Parrot/"
  name "Parrot"
  desc "Grammar and style correction for every app on your Mac — offline, instant, no subscription"
  homepage "https://github.com/thousandflowers/Parrot"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Parrot.app"

  uninstall quit: "com.thousandflowers.parrot"

  zap trash: [
    "~/Library/Application Support/Parrot",
    "~/Library/Caches/com.thousandflowers.parrot",
    "~/Library/HTTPStorages/com.thousandflowers.parrot",
    "~/Library/Preferences/com.thousandflowers.parrot.plist",
    "~/Library/Saved Application State/com.thousandflowers.parrot.savedState",
  ]
end
