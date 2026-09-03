# Currency Swapper 2.2.0 maintenance port

This branch is a narrow runtime-compatibility port of the released
`v2.2.0` source (`83ef23d6ba78690e8144b80b4e7ebe499a467def`). It intentionally does not
pull behavior from the upstream development branch.

## Compatibility boundary

- Skyrim SE/AE runtime: **1.7.104.0 only**
- SKSE: **2.3.1**
- Address Library: binary **format 5** (`versionlib-1-7-104-0.bin`)
- CommonLibSSE-NG: Ensrick `ensrick/no-modal-fail-v7.1.0`, commit
  `90a64a4d65ce659a139137c968f42151bb6ecec9`

The CommonLib pin both parses format-5 address libraries and changes its fatal
reporter, when `COMMONLIBSSE_NO_MODAL_ERRORS` is enabled, to log, flush, and
terminate without opening a native message box. A pre-hook configuration error
returns `false` to SKSE. A failure after hook installation begins must fail
closed through the non-modal fatal path: returning and unloading the DLL could
leave an already-written trampoline targeting unloaded code.

## Source changes

- Migrated the CommonLib submodule from the release's format-2-only fork to the
  audited CommonLibSSE-NG 7.1.0 maintenance commit.
- Restricted the generated SKSE compatibility metadata and runtime checks to
  1.7.104.0.
- Migrated removed CommonLib APIs:
  - `TESDataHandler::merchantInventory` -> `GetMerchantInventory()`
  - `BarterMenu::root` -> `GetRuntimeData().root`
  - `TrainingMenu` runtime fields -> `GetRuntimeData()`
  - `Setting::GetSInt()` -> `GetInteger()`
- Added null checks around the merchant inventory list.
- Updated the vcpkg baseline and dependencies required by CommonLibSSE-NG 7.1.0.
- Corrected the vcpkg manifest's license identifier to match the repository's
  Apache-2.0 license.

## Verification

Build the release DLL, then verify all 18 trampoline call sites against the
actual 1.7.104 executable and format-5 address library:

```powershell
pwsh -NoProfile -File .\scripts\Test-HookSites.ps1 `
  -SkyrimExe 'C:\path\to\SkyrimSE.exe' `
  -AddressLibrary 'C:\path\to\versionlib-1-7-104-0.bin'
```

The verifier fails unless the address-library header identifies format 5 and
runtime 1.7.104.0, every required ID resolves, and every hook site still starts
with the `E8` call opcode expected by the plugin's guarded installers.

The CI artifact is a DLL/PDB overlay for the official Currency Swapper 2.2.0
package. Keep the official package's scripts and configuration files; replace
only its `SKSE/Plugins/CurrencySwapper.dll` with the built DLL.

## Licensing

Currency Swapper v2.2.0 and these changes remain under Apache-2.0. The linked
CommonLibSSE-NG source retains its own GPL-3.0-or-later license and modding
exception. See the respective license and exception files in the source trees.
