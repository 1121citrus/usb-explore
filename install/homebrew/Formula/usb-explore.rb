# Homebrew formula for usb-explore.
#
# Installation:
#   brew tap 1121citrus/usb-explore https://github.com/1121citrus/usb-explore
#   brew install usb-explore
#
# Or install directly from a local clone:
#   brew install --formula ./install/homebrew/Formula/usb-explore.rb
class UsbExplore < Formula
  desc "Explore Linux USB disk images from macOS via Docker"
  homepage "https://github.com/1121citrus/usb-explore"
  url "https://github.com/1121citrus/usb-explore/archive/refs/tags/v1.4.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
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
