# Use current Debian stable (bookworm)
FROM debian:bookworm-slim

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install system dependencies required for Homebrew and statica
RUN apt-get update && apt-get install -y \
    bash \
    build-essential \
    curl \
    file \
    git \
    procps \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    sudo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*


# Create a non-root user for Homebrew (Homebrew doesn't like running as root)
RUN useradd -m -s /bin/bash linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Switch to linuxbrew user and install Homebrew
USER linuxbrew
WORKDIR /home/linuxbrew

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Set up Homebrew environment and add Ruby 3.3 to PATH
ENV PATH="/home/linuxbrew/.linuxbrew/opt/ruby@3.3/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# Install tools via Homebrew
RUN brew install \
    semgrep \
    jq \
    retire \
    trivy \
    lizard-analyzer \
    checkov \
    pmd \
    bearer/tap/bearer \
    ruby@3.3

# Link ruby@3.3 to make it the default
RUN brew link ruby@3.3

# Install Python tools via pipx
RUN pipx install sarif-tools && \
    pipx install semgrep-rules-manager

# Ensure pipx binaries are in PATH
ENV PATH="/home/linuxbrew/.local/bin:${PATH}"

# Set working directory
WORKDIR /statica

# Copy application files (will be owned by linuxbrew user)
COPY --chown=linuxbrew:linuxbrew . /statica/

# Install Ruby dependencies
RUN bundle config set without 'development' && \
    bundle install

# clean up
RUN brew cleanup -s && brew cleanup --prune=all && rm -rf "$(brew --cache)" \
    && pip cache purge


# Make statica executable
RUN chmod +x /statica/statica

# Add statica to PATH
ENV PATH="/statica:${PATH}"

# Set default command
CMD ["/bin/bash"]
