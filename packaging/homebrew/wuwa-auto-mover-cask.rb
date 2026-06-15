cask "wuwa-auto-mover" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256"

  url "https://github.com/akalivaty/WuwaAutoMover/releases/download/v#{version}/WuwaAutoMover-#{version}.zip"
  name "WuwaAutoMover"
  desc "GUI and CLI for moving Wuthering Waves macOS resources to an external disk"
  homepage "https://github.com/akalivaty/WuwaAutoMover"

  app "WuwaAutoMover.app"
  binary "#{appdir}/WuwaAutoMover.app/Contents/MacOS/wuwa-auto-mover"
end
