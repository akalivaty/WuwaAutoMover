class WuwaAutoMover < Formula
  desc "Move Wuthering Waves macOS resources to an external disk"
  homepage "https://github.com/akalivaty/WuwaAutoMover"
  url "https://github.com/akalivaty/WuwaAutoMover/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SOURCE_TARBALL_SHA256"
  license "MIT"

  depends_on xcode: :build

  def install
    system "swift", "build", "-c", "release", "--product", "wuwa-auto-mover"
    bin.install ".build/release/wuwa-auto-mover"
  end

  test do
    assert_match "WuwaAutoMover command line", shell_output("#{bin}/wuwa-auto-mover --help")
  end
end
