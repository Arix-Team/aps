#!/bin/bash

# aps.sh - App Center CLI
# Supports Linux (Ubuntu/Debian) and macOS (for testing)

API_URL="https://flathub.org/api/v2"

# Check dependencies
check_deps() {
    local missing_deps=0
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed." >&2
        missing_deps=1
    fi
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed." >&2
        missing_deps=1
    fi
    if [ $missing_deps -eq 1 ]; then
        echo "Please install missing dependencies." >&2
        exit 1
    fi
}

# Check if an app is installed via flatpak
is_installed() {
    local app_id=$1
    # Check if flatpak is installed
    if command -v flatpak &> /dev/null; then
        # Check if the app is in the list of installed apps
        # We use grep to look for the exact ID in the Application ID column
        # flatpak list --app --columns=application returns just the IDs
        if flatpak list --app --columns=application | grep -q "^${app_id}$"; then
            echo "true"
        else
            echo "false"
        fi
    else
        # If flatpak is not installed (e.g. macOS), we can't check, so assume false
        echo "false"
    fi
}

handle_search() {
    local page=1
    local query=""
    local category=""

    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" == page:* ]]; then
            page="${arg#page:}"
        elif [[ "$arg" == category:* ]]; then
            category="${arg#category:}"
        else
            query="$arg"
        fi
    done

    if [ -z "$query" ] && [ -z "$category" ]; then
        echo "Error: Search query or category is required." >&2
        exit 1
    fi

    local payload
    local filters="[]"

    if [ -n "$category" ]; then
        filters=$(jq -n --arg val "$category" '[{filterType: "main_categories", value: $val}]')
    fi

    if [ "$query" == "home" ]; then
        # Special case for "home" to fetch default/featured apps with empty query
        payload=$(jq -n --argjson p "$page" --argjson f "$filters" '{query: "", filters: $f, hits_per_page: 21, page: $p}')
    else
        # Construct JSON payload using jq to ensure proper escaping
        payload=$(jq -n --arg q "$query" --argjson p "$page" --argjson f "$filters" '{query: $q, filters: $f, hits_per_page: 21, page: $p}')
    fi

    # Fetch from Flathub API
    curl -s -X POST "${API_URL}/search?locale=en" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

handle_app_info() {
    local app_id="$1"
    if [ -z "$app_id" ]; then
        echo "Error: App ID is required." >&2
        exit 1
    fi

    # Fetch app info from Flathub API v2
    # This returns a clean JSON object with all app details
    local response
    # Try appstream endpoint first as it has more details like screenshots
    response=$(curl -s "${API_URL}/appstream/${app_id}")

    # Check if response is valid JSON (basic validation)
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        # Fallback to apps endpoint if appstream fails
        response=$(curl -s "${API_URL}/apps/${app_id}")
        if ! echo "$response" | jq -e . >/dev/null 2>&1; then
            echo "Error: Failed to fetch app info or invalid response." >&2
            echo "$response" >&2
            exit 1
        fi
    fi

    # Check if app is installed locally
    local installed
    installed=$(is_installed "$app_id")

    # Add 'installed' field to the JSON response
    echo "$response" | jq --argjson installed "$installed" '. + {installed: $installed}'
}

handle_app_install() {
    local app_id="$1"
    if [ -z "$app_id" ]; then
        echo "Error: App ID is required." >&2
        exit 1
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v flatpak &> /dev/null; then
        echo "Installing ${app_id}..."
        # Run flatpak install non-interactively
        flatpak install -y flathub "${app_id}"
    else
        echo "Demo: Installing ${app_id}..."
        # Simulate installation delay
        sleep 2
        echo "Successfully installed ${app_id} (Demo)"
    fi
}

handle_app_uninstall() {
    local app_id="$1"
    if [ -z "$app_id" ]; then
        echo "Error: App ID is required." >&2
        exit 1
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v flatpak &> /dev/null; then
        echo "Uninstalling ${app_id}..."
        # Run flatpak uninstall non-interactively
        flatpak uninstall -y "${app_id}"
    else
        echo "Demo: Uninstalling ${app_id}..."
        # Simulate uninstallation delay
        sleep 2
        echo "Successfully uninstalled ${app_id} (Demo)"
    fi
}

# Main execution
check_deps

if [ "$1" == "--search" ]; then
    shift
    handle_search "$@"
elif [ "$1" == "app" ]; then
    case "$2" in
        info)
            handle_app_info "$3"
            ;;
        install)
            handle_app_install "$3"
            ;;
        uninstall)
            handle_app_uninstall "$3"
            ;;
        *)
            echo "Usage: $0 app {info|install|uninstall} <app_id>" >&2
            exit 1
            ;;
    esac
else
    echo "Usage:" >&2
    echo "  $0 --search \"<query>\"" >&2
    echo "  $0 app info <app_id>" >&2
    echo "  $0 app install <app_id>" >&2
    echo "  $0 app uninstall <app_id>" >&2
    exit 1
fi
