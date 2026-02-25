---

# EventHorizon

EventHorizon is a universal archive extractor for Termux, Linux (Debian/Ubuntu/Arch-based).  
It supports multiple archive formats and can be used either as a standalone script or installed in your PATH.

**Note:** When using option (a) to select from found archives, EventHorizon searches specifically in the **current working directory** where you run the script.

## Features

- Supports zip, rar, tar, 7z, wim, lz4, gzip, bzip2, xz, zstd, and more
- Works on Termux with official packages, Debian/Ubuntu (apt), and Arch-based distros (pacman)
- Automatically checks for missing dependencies and prompts to install them
- Can be used standalone or installed in your PATH for convenience

## Dependencies

EventHorizon relies on external packages to handle different archive formats.  
- On Termux: installed via `pkg`  
- On Debian/Ubuntu: installed via `apt`  
- On Arch-based: installed via `pacman`

The user is prompted to approve installation of missing packages.

---

## Installation

### Standalone usage
1. Clone EventHorizon and enter the folder:

```bash
git clone --depth=1 https://github.com/Alessandro9749/event_horizon.git
cd event_horizon

```
2. Make it executable:


```bash
chmod 755 event_horizon.sh

```
3. Run it:


```bash
./event_horizon.sh

```
or
```bash
bash event_horizon.sh
```
### Install in PATH for easy access (recommended)

## Termux 
1. Clone the git as in the standalone one and make it executable:
```bash
git clone --depth=1 https://github.com/Alessandro9749/event_horizon.git
cd event_horizon
chmod 755 event_horizon.sh

```

2. Move it to $PREFIX/bin:
```bash
mv event_horizon.sh $PREFIX/bin/event_horizon

```
3. Now you can run it from anywhere:
```bash
event_horizon

```

## Debian/Ubuntu
1. Clone the git as in the standalone one and make it executable:
```bash
git clone --depth=1 https://github.com/Alessandro9749/event_horizon.git
cd event_horizon
chmod 755 event_horizon.sh

```

2. Move it to /usr/local/bin:
```bash
sudo mv event_horizon.sh /usr/local/bin/event_horizon

```
3. Now you can run it from anywhere:
```bash
event_horizon

```

## Arch-based
1. Clone the git as in the standalone one and make it executable:
```bash
git clone --depth=1 https://github.com/Alessandro9749/event_horizon.git
cd event_horizon
chmod 755 event_horizon.sh

```

2. Move it to /usr/local/bin:
```bash
sudo mv event_horizon.sh /usr/local/bin/event_horizon

```
3. Now you can run it from anywhere:
```bash
event_horizon

```

---

Usage Examples

1. Move event_horizon.sh to the folder containing the archive:
```bash
mv event_horizon.sh /path/to/folder/

```
2. Run the script:
```bash
./event_horizon.sh

```
or

1. Copy the full path of the archive you want to decompress.


2. Run EventHorizon:
```bash
event_horizon

```
3. Paste the path when prompted and press Enter.

---
## Bug
Found a bug or have a suggestion?
Open an Issue here on GitHub and we'll check it out! 

---

## License

EventHorizon is released under the **EventHorizon Protective License**.  
See the `LICENSE` file for full details.

This license grants permission to use, copy, modify, and distribute EventHorizon 
while clearly stating that the author is not responsible for any consequences 
arising from its use.
