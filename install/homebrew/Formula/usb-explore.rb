# Homebrew formula for usb-explore.
#
# Not published as a tap; install directly from a local clone:
#   brew install --formula ./install/homebrew/Formula/usb-explore.rb
#
# url/sha256 must be updated after every release — see "Releasing" in
# CONTRIBUTING.md and install/homebrew/update-formula.
class UsbExplore < Formula
  desc "Explore Linux USB disk images from macOS via Docker"
  homepage "https://github.com/1121citrus/usb-explore"
  url "https://github.com/1121citrus/usb-explore/archive/refs/tags/v1.6.1.tar.gz"
  sha256 "8d6f5acd8ce8cdc040dcf1a064818c2b4564d3c9d08ee6a8ad599e87a2de77a6"
  license "AGPL-3.0-or-later"
  head "https://github.com/1121citrus/usb-explore.git", branch: "main"

  depends_on :macos
  depends_on "bash" => :recommended

  def install
    bin.install "src/usb-explore" => "usb-explore"
  end

  def caveats
    <<~EOS
      usb-explore requires Docker Desktop to be running for all
      subcommands except capture and clean.

      The Docker image is pulled automatically on first use:
        #{HOMEBREW_PREFIX}/bin/usb-explore info

      To pre-pull the image now:
        docker pull 1121citrus/usb-explore:latest
    EOS
  end

  test do
    assert_match "usb-explore", shell_output("#{bin}/usb-explore --version")
    assert_match "usb-explore", shell_output("#{bin}/usb-explore --help")
  end
end
