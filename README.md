# Daily Playlist Cover Creator

A personal Ruby app to create daily playlist covers. The command-line application accepts source and destination folders plus a title as named parameters.

## Usage

Install the command into `~/.local/bin`:

```sh
bin/install
```

After installation, run it from any folder:

```sh
daily-playlist-cover-creator --source-folder /path/to/source/folder --destination-folder /path/to/destination/folder --title "Playlist Title"
```

Short switches are also supported:

```sh
daily-playlist-cover-creator -s /path/to/source/folder -d /path/to/destination/folder -t "Playlist Title" -p /path/to/playlist.txt
```

The optional `--playlist` or `-p` parameter accepts a playlist text file. When present, the app connects to Spotify, creates a public Spotify playlist using the playlist file name, searches for each nonblank line as a song query, and adds each found track to the new playlist.

The optional `--database` or `-db` parameter accepts a SQLite database file. When present, the app selects a random row from the `image_urls` table and reads the `image_name` column. It builds the source image path from the source folder, the first two characters of the image name as the first subfolder, the second two characters as the next subfolder, and then the full image name.

To use a specific source image instead of random selection, pass `--file` or `-f`:

```sh
daily-playlist-cover-creator -f /path/to/image.jpg -d /path/to/destination/folder -t "Playlist Title"
```

After each successful run, the application remembers the source folder or source file, destination folder, and title in `~/.daily_playlist_cover_creator_defaults.json`. If any of those options is missing on the next run, the prompt shows the remembered value in brackets and uses it when you press Enter. If no remembered value exists, the application prompts for it normally.

The application validates that the source folder exists and is a directory, creates the destination folder if it does not exist, and checks that the title is present. Under the destination folder, it creates a title-named subfolder such as `morning-focus`; all generated files for that run are stored there.

It selects a random image by choosing a random item from the source folder. If the item is an image file, it moves the file to the title-named destination subfolder after approval. If the item is a folder, it repeats that selection inside the folder until an image file is found. When `--file` is provided, the app skips random selection and uses that file directly.

After an image is selected, the app opens the original source image with the default application and asks you to approve it. Enter `y` or `yes` to continue, `q` to quit, or `d` to delete the selected source image. Any other answer starts another random selection. The image is moved to the destination only after you approve it.

Supported image extensions are `.gif`, `.jpg`, `.jpeg`, `.png`, and `.webp`.

The moved image keeps its original filename. If that filename already exists in the destination folder, the app appends a counter such as `cover-2.jpg`.

After you approve the source image, the app moves it to the destination. The 16:9 generation and 1:1 cover creation stages are currently disabled, so the process stops after the selected image is stored.

For a dry-run style smoke check, pass `--smoke`. In smoke mode, the approved source image is copied to the destination instead of moved, so the original file remains in the source folder.

When the process completes successfully, the app raises a macOS notification.

The GPT steps are currently commented out in the run flow. When enabled, they use global memories stored in `~/.daily_playlist_cover_creator_memories.json`.

Set `OPENAI_API_KEY` before running the app:

```sh
export OPENAI_API_KEY="your-api-key"
```

To use `--playlist`, create a Spotify app in the Spotify Developer Dashboard, add this redirect URI to the app settings, and set the app client ID:

```sh
http://127.0.0.1:4567/callback
```

```sh
export SPOTIFY_CLIENT_ID="your-spotify-client-id"
```

Then run the OAuth login once:

```sh
daily-playlist-cover-creator --spotify-login
```

The login opens Spotify in your browser, asks for `playlist-modify-public`, receives the callback locally, and saves a refresh token in `~/.daily_playlist_cover_creator_spotify.json`. After that, `--playlist` refreshes Spotify access automatically. You can still set `SPOTIFY_ACCESS_TOKEN` manually to override OAuth for a single shell session.

On each run, the app asks GPT for the latest available OpenAI Images API model and uses that model for image enhancement. If GPT cannot return a valid image model ID, the app falls back to `gpt-image-1.5`. You can override model selection with `OPENAI_IMAGE_MODEL`.

## Tests

```sh
ruby test/cli_test.rb
```
