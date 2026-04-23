class Meister < Formula
  desc "Local macOS maintenance — addressbook cleanup, contact dedup, storage insights"
  homepage "https://github.com/merados/meister"
  url "https://github.com/merados/meister/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_AT_RELEASE"
  license "MIT"
  head "https://github.com/merados/meister.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    cd "cli" do
      system "swift", "build",
             "--disable-sandbox",
             "-c", "release",
             "--arch", Hardware::CPU.arch.to_s
      bin.install ".build/#{Hardware::CPU.arch}-apple-macosx/release/meister"
    end
  end

  test do
    assert_match "meister", shell_output("#{bin}/meister --version")
    assert_match "AddressBook", shell_output("#{bin}/meister contacts scan --help")
  end
end
