cask "magicborder" do
  version "0.1.0"
  sha256 :no_check

  url "https://github.com/Tinnci/MagicBorder/releases/download/v#{version}/MagicBorder-macos-#{version}.dmg",
      verified: "github.com/Tinnci/MagicBorder/"
  name "MagicBorder"
  desc "Native macOS software KVM & clipboard bridge compatible with Mouse Without Borders"
  homepage "https://github.com/Tinnci/MagicBorder"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "MagicBorder.app"

  zap trash: [
    "~/Library/Preferences/com.tinnci.MagicBorder.plist",
    "~/Library/Saved Application State/com.tinnci.MagicBorder.savedState",
  ]
end
