# Daily Playlist Cover Creator

A personal Ruby app to create daily playlist covers. The command-line application accepts source and destination folders plus a title as named parameters.

## Usage

```sh
bin/daily-playlist-cover-creator --source-folder /path/to/source/folder --destination-folder /path/to/destination/folder --title "Playlist Title"
```

Short switches are also supported:

```sh
bin/daily-playlist-cover-creator -s /path/to/source/folder -d /path/to/destination/folder -t "Playlist Title"
```

If any option is missing, the application prompts for it.

The application validates that the source folder exists and is a directory, creates the destination folder if it does not exist, and checks that the title is present. Under the destination folder, it creates a title-named subfolder such as `morning-focus`; all generated files for that run are stored there.

It selects a random image by choosing a random item from the source folder. If the item is an image file, it copies the file to the title-named destination subfolder. If the item is a folder, it repeats that selection inside the folder until an image file is found.

After an image is selected, the app copies it to the destination, opens the copied image with the default application, and asks you to approve it. Enter `y` or `yes` to continue. Any other answer removes that copied image and starts another random selection.

Supported image extensions are `.jpg`, `.jpeg`, `.png`, and `.webp`.

The copied image keeps its original filename. If that filename already exists in the destination folder, the app appends a counter such as `cover-2.jpg`.

After you approve the copied image, the app enhances it with GPT using the prompt below. It then asks GPT for a title, saves the enhanced image with that title, such as `cinematic-sunrise.png`, and opens the enhanced image with the default application.

Approved images are normalized to JPEG before GPT upload so unusual image encodings or color modes are less likely to be rejected by the image API.

If the enhanced image is not landscape, the app also asks GPT to generate a 16:9 landscape version, saves it with `-16x9` in the filename, and opens it with the default application.

Finally, the app uses the enhanced image, or the 16:9 version when present, to generate a 1:1 album cover. It uses the playlist title in the image prompt, saves the generated cover with the title as the filename, and opens it with the default application.

When the process completes successfully, the app raises a macOS notification.

The GPT steps use local memories stored in `.daily_playlist_cover_creator_memories.json` inside the title-named destination subfolder. Each successful run remembers recent playlist titles, enhanced titles, and generated files, then includes that context in future GPT image and title prompts.

Set `OPENAI_API_KEY` before running the app:

```sh
export OPENAI_API_KEY="your-api-key"
```

By default the app uses `gpt-image-1.5` for image enhancement and `gpt-5.2` for title suggestion. You can override those with `OPENAI_IMAGE_MODEL` and `OPENAI_TEXT_MODEL`.

The planned image enhancement prompt is:

```text
Apply cinematic enhancements to this image while preserving the original aspect ratio. Improve lighting, contrast, color grading, depth, sharpness, and overall visual polish. Keep the image composition faithful to the original. Do not add any text, letters, captions, logos, watermarks, or typography.
```

## Tests

```sh
ruby test/cli_test.rb
```
