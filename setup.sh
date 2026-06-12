#!/bin/bash

# Exit on any error
set -e

echo "--- GUARDA System Setup Script ---"

DESIRED_VERSION="1.17.1"

# Detect operating system
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_FAMILY="$ID_LIKE"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_ID="macos"
    else
        OS_ID="unknown"
    fi
}

detect_os

# Check if Elixir is already installed and matches the desired version
if command -v elixir >/dev/null 2>&1; then
    CURRENT_VERSION=$(elixir --version | grep -oE "Elixir [0-9.]+" | awk '{print $2}')
    if [ "$CURRENT_VERSION" == "$DESIRED_VERSION" ]; then
        echo "Elixir $DESIRED_VERSION is already installed. Skipping system installation."
        SKIP_INSTALL=true
    fi
fi

if [ "$SKIP_INSTALL" != true ]; then
    case "$OS_ID" in
        ubuntu|debian)
            echo "Detected Debian/Ubuntu system."

            # 1. Cleanup any broken Erlang Solutions repo to allow apt update
            echo "Checking for broken Erlang Solutions repository..."
            if [ -f /etc/apt/sources.list.d/erlang-solutions.list ]; then
                echo "Removing existing Erlang Solutions list to avoid 502 errors..."
                sudo rm -f /etc/apt/sources.list.d/erlang-solutions.list
            fi

            # 2. Update and install basic dependencies
            echo "Updating package lists and installing system dependencies..."
            sudo apt update
            sudo apt install -y wget unzip libssl-dev automake autoconf libncurses5-dev gcc make software-properties-common inotify-tools

            # 3. Add RabbitMQ Erlang PPA
            echo "Adding RabbitMQ Erlang PPA..."
            sudo add-apt-repository ppa:rabbitmq/rabbitmq-erlang -y
            sudo apt update

            # 4. Install Erlang/OTP
            echo "Installing Erlang/OTP..."
            sudo apt install -y erlang-base erlang-dev erlang-public-key erlang-ssl erlang-crypto erlang-syntax-tools erlang-asn1 erlang-inets erlang-os-mon erlang-parsetools erlang-runtime-tools erlang-xmerl

            # 5. Download and Install Elixir
            echo "Downloading Elixir $DESIRED_VERSION..."
            ELIXIR_ZIP="elixir-otp-26.zip"
            wget "https://github.com/elixir-lang/elixir/releases/download/v$DESIRED_VERSION/$ELIXIR_ZIP"

            echo "Extracting Elixir to /usr/local/lib/elixir..."
            sudo rm -rf /usr/local/lib/elixir
            sudo mkdir -p /usr/local/lib/elixir
            sudo unzip -q "$ELIXIR_ZIP" -d /usr/local/lib/elixir
            rm "$ELIXIR_ZIP"

            # 6. Create symbolic links
            echo "Setting up symbolic links..."
            sudo ln -sf /usr/local/lib/elixir/bin/elixir /usr/local/bin/elixir
            sudo ln -sf /usr/local/lib/elixir/bin/elixirc /usr/local/bin/elixirc
            sudo ln -sf /usr/local/lib/elixir/bin/iex /usr/local/bin/iex
            sudo ln -sf /usr/local/lib/elixir/bin/mix /usr/local/bin/mix
            ;;

        macos)
            echo "Detected macOS."
            echo "Please install Elixir via Homebrew:"
            echo "  brew install elixir"
            echo ""
            echo "After installation, re-run this script."
            exit 1
            ;;

        fedora|rhel|centos)
            echo "Detected Fedora/RHEL/CentOS."
            echo "Please install Elixir via dnf:"
            echo "  sudo dnf install elixir erlang"
            echo ""
            echo "After installation, re-run this script."
            exit 1
            ;;

        arch|manjaro)
            echo "Detected Arch Linux."
            echo "Please install Elixir via pacman:"
            echo "  sudo pacman -S elixir"
            echo ""
            echo "After installation, re-run this script."
            exit 1
            ;;

        *)
            echo "Unsupported OS: $OS_ID"
            echo "Please install Elixir $DESIRED_VERSION manually from:"
            echo "  https://elixir-lang.org/install.html"
            echo ""
            echo "After installation, re-run this script."
            exit 1
            ;;
    esac
fi

# 7. Initialize Elixir Environment
echo "Updating Hex and Rebar..."
mix local.hex --force
mix local.rebar --force

# 8. Project Deployment
echo "Cleaning old project artifacts..."
rm -rf _build deps

echo "Fetching project dependencies..."
mix deps.get

echo "--- Setup Complete ---"
echo "Verifying installation:"
elixir --version

echo ""
echo "Success! GUARDA is now set up and dependencies are fetched."
echo "You can now start the server with: mix phx.server"
