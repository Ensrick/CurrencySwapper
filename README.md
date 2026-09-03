# Currency Swapper

The `port/1.7.104-no-modal` branch is a maintenance port of the released
Currency Swapper 2.2.0 source for Skyrim SE/AE 1.7.104.0 and Address Library
format 5. See [ENSRICK-PORT.md](ENSRICK-PORT.md) for its exact compatibility
boundary, changes, verification, artifact use, and licensing notes.

## Building
### Requirements:
* CMake
* VCPKG
  * Add the root to an environment variable called `VCPKG_ROOT`.
* Visual Studio (with desktop C++ development)
---
### Instructions:
```
git clone --branch port/1.7.104-no-modal https://github.com/Ensrick/CurrencySwapper.git
cd CurrencySwapper
git submodule update --init --recursive
cmake --preset vs2022-windows-vcpkg-release
cmake --build --preset Release
```
---
### Automatic deployment to MO2:
You can automatically deploy to MO2's mods folder by defining an Environment Variable named SKYRIM_MODS_FOLDER and pointing it to your MO2 mods folder. It will create a new mod with the appropriate name. After that, simply refresh MO2 and enable the mod.
