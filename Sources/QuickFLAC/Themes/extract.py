import urllib.request
import json
import ssl
import time

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# The GitHub API endpoint for the frontend/static/themes folder
GITHUB_API_URL = "https://api.github.com/repos/monkeytypegame/monkeytype/contents/frontend/static/themes"


def get_theme_list():
    print("Fetching theme list...")
    req = urllib.request.Request(GITHUB_API_URL)
    req.add_header('User-Agent', 'Mozilla/5.0')

    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            data = json.loads(response.read().decode())

            # If GitHub returns a rate-limit error, it's usually a dictionary, not a list
            if isinstance(data, dict) and 'message' in data:
                print(f"GitHub API Error: {data['message']}")
                return []

            theme_files = [file for file in data if file['name'].endswith('.json') or file['name'].endswith('.css')]
            return theme_files
    except urllib.error.URLError as e:
        print(f"Error accessing GitHub API: {e}")
        return []


def parse_theme(file_data):
    raw_url = file_data['download_url']
    name = file_data['name']

    try:
        req = urllib.request.Request(raw_url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        with urllib.request.urlopen(req, context=ctx) as response:
            raw_content = response.read().decode('utf-8')

            # Check the extension to determine how to parse it
            if name.endswith('.json'):
                try:
                    return name.replace('.json', ''), json.loads(raw_content)
                except json.JSONDecodeError:
                    print(f"\n[!] Invalid JSON format in {name}")
                    return name, None
            elif name.endswith('.css'):
                # Return raw text for CSS
                return name.replace('.css', ''), {"raw_css": raw_content}
            else:
                return name, None

    except urllib.error.HTTPError as e:
        print(f"\n[!] HTTP Error downloading {name}: {e.code} {e.reason}")
        return name, None
    except Exception as e:
        print(f"\n[!] Failed to download/parse {name}: {str(e)}")
        return name, None


def main():
    themes_metadata = get_theme_list()

    if not themes_metadata:
        print("No themes found. You might be rate-limited by GitHub.")
        return

    print(f"Found {len(themes_metadata)} themes. Starting download...\n")

    all_themes = {}

    for i, file_data in enumerate(themes_metadata):
        print(f"[{i + 1}/{len(themes_metadata)}] Downloading {file_data['name']}...", end='\r')
        name, theme_data = parse_theme(file_data)

        if theme_data:
            all_themes[name] = theme_data

        time.sleep(0.5)

    print("\n\nSaving to monkeytype_all_themes.json...")
    with open('monkeytype_all_themes.json', 'w', encoding='utf-8') as f:
        json.dump(all_themes, f, indent=4)

    print("✅ Successfully downloaded and saved!")


if __name__ == "__main__":
    main()