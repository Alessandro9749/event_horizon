---

# EventHorizon

EventHorizon is a universal archive extractor for Termux (Android).  
It can handle a wide variety of archive formats and works both as a standalone script or installed in your PATH.

---

## Features
- Supports multiple archive formats (zip, rar, tar.*, 7z, wim, lz4, gzip, bzip2, xz, zstd, etc.)
- Works on Termux with official packages
- Can check all archives in a folder or accept direct file paths
- Automatically checks for missing dependencies and offers to install them
- Standalone or installable in PATH for convenience

---

## Dependencies

EventHorizon relies on external Termux packages to handle different archive formats.  
The script automatically checks for missing dependencies and can install them using Termux's package manager (`pkg`).  
The user is responsible for approving the installation of any required packages.

---

## Installation

### Standalone Usage
1. Clone EventHorizon:

```bash
git clone --depth=1 https://github.com/Alessandro9749/event_horizon.git
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
Optional: Install in PATH for easy access

1. Make the PATH version executable:
```bash
chmod 755 event_horizon(path).sh
```
2. Move it to $PREFIX/bin:


```bash
mv event_horizon(path).sh $PREFIX/bin/event_horizon
```
3. Now you can run it from anywhere:
```bash
event_horizon
```
---

Usage Examples

Standalone

1. Move event_horizon.sh to the folder containing the archive:
```bash
mv event_horizon.sh /path/to/folder/
```
2. Run the script:
```bash
./event_horizon.sh
```
PATH Version

1. Copy the full path of the archive you want to decompress.


2. Run EventHorizon:
```bash
event_horizo
```
3. Paste the path when prompted and press Enter.

---
## Bug
Found a bug or have a suggestion?
Open an Issue here on GitHub and we’ll check it out! 🚀

---

## License

EventHorizon is released under the **EventHorizon Protective License**.  
See the `LICENSE` file for full details.

This license grants permission to use, copy, modify, and distribute EventHorizon 
while clearly stating that the author is not responsible for any consequences 
arising from its use.

