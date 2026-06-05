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

To use a specific source image instead of random selection, pass `--file` or `-f`:

```sh
daily-playlist-cover-creator -f /path/to/image.jpg -d /path/to/destination/folder -t "Playlist Title"
```

After each successful run, the application remembers the source folder or source file, destination folder, and title in `~/.daily_playlist_cover_creator_defaults.json`. If any of those options is missing on the next run, the prompt shows the remembered value in brackets and uses it when you press Enter. If no remembered value exists, the application prompts for it normally.

The application validates that the source folder exists and is a directory, creates the destination folder if it does not exist, and checks that the title is present. Under the destination folder, it creates a title-named subfolder such as `morning-focus`; all generated files for that run are stored there.

It selects a random image by choosing a random item from the source folder. If the item is an image file, it moves the file to the title-named destination subfolder after approval. If the item is a folder, it repeats that selection inside the folder until an image file is found. When `--file` is provided, the app skips random selection and uses that file directly.

After an image is selected, the app opens the original source image with the default application and asks you to approve it. Enter `y` or `yes` to continue. Any other answer starts another random selection. The image is moved to the destination only after you approve it.

Supported image extensions are `.jpg`, `.jpeg`, `.png`, and `.webp`.

The moved image keeps its original filename. If that filename already exists in the destination folder, the app appends a counter such as `cover-2.jpg`.

After you approve the source image, the app moves it to the destination and enhances it with GPT using the prompt below. It saves the enhanced image using the original filename with `-enh`, such as `cover-enh.png`, and opens the enhanced image with the default application.

Approved images are normalized to JPEG before GPT upload so unusual image encodings or color modes are less likely to be rejected by the image API.

If the enhanced image is not landscape, the app also asks GPT to generate a 16:9 landscape version, saves it with `-16x9` in the filename, and opens it with the default application.

Finally, the app uses the enhanced image, or the 16:9 version when present, to generate a 1:1 album cover. It uses the playlist title in the image prompt, saves the generated cover with the title as the filename, and opens it with the default application.

When the process completes successfully, the app raises a macOS notification.

The GPT steps use global memories stored in `~/.daily_playlist_cover_creator_memories.json`. Each successful run remembers recent playlist titles, enhanced titles, and generated files, then includes that context in future GPT image and title prompts.

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

By default the app uses `gpt-image-1.5` for image enhancement and `gpt-5.2` for title suggestion. You can override those with `OPENAI_IMAGE_MODEL` and `OPENAI_TEXT_MODEL`.

The planned image enhancement prompt is:

```text
Apply cinematic enhancements to this image while preserving the original aspect ratio. Improve lighting, contrast, color grading, depth, sharpness, and overall visual polish. Keep the image composition faithful to the original. Do not add any text, letters, captions, logos, watermarks, or typography.
```

## Tests

```sh
ruby test/cli_test.rb
```
