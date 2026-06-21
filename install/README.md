# Install methods

Alternative installation paths beyond `bin/install`.

## Homebrew

```bash
brew install --formula ./install/homebrew/Formula/usb-explore.rb
```

The formula installs `src/usb-explore` to the Homebrew prefix. The
Docker image is pulled automatically on first use.

### Formula validation

`install/homebrew/test-formula` runs `brew style`, `brew audit`, and
optionally `brew install --HEAD` inside the `homebrew/brew` Docker
image. No Homebrew installation is needed on the host.

```bash
# Style + audit only (fast)
./install/homebrew/test-formula --skip-install

# Full validation including install
./install/homebrew/test-formula
```

## Manual PATH

No installation step — add the source directory to your shell PATH:

```bash
export PATH="$PWD/src:$PATH"
```

This works from a clone. The `usb-explore build` subcommand locates
the `Dockerfile` relative to the script's own directory, so building
from source works without any additional configuration.
