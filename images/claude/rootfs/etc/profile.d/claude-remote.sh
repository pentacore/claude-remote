# Debian's /etc/profile resets PATH for login shells (SSH, IDE, `bash -l`); restore the image's tool paths.
export PATH=/usr/local/bin:/home/claude/.local/bin:/home/claude/.cargo/bin:/home/claude/go/bin:/opt/cargo/bin:/usr/local/go/bin:$PATH
export CARGO_HOME=/home/claude/.cargo RUSTUP_HOME=/opt/rustup PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
