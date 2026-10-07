# Desktop test-host loader stall

The host stalled before app code. A copied host in `/tmp` ran successfully.
This is separate from the reproduced coordinator regression.
Full original sample: `/tmp/atoll-next-version-fixes/test-host-sample.txt`.

```text
Process:         Atoll [54913]
Path:            /Users/USER/Desktop/*/Atoll.app/Contents/MacOS/Atoll
Identifier:      Atoll
Parent Process:  launchd [1]
Date/Time:       2026-10-06 20:52:56.563 -0700
Launch Time:     2026-10-06 20:51:56.193 -0700
Physical footprint:         240K
      817 start  (in dyld) + 6596  [0x18925be24]
        817 dyld4::start(dyld4::KernelArgs*, void*, void*, unsigned long long)::$_1::operator()() const  (in dyld) + 320  [0x18925ca84]
          817 dyld4::prepare(dyld4::APIs&, mach_o::UnsafeHeader const*)  (in dyld) + 1428  [0x18925d034]
            817 dyld4::JustInTimeLoader::loadDependents(Diagnostics&, dyld4::RuntimeState&, dyld4::Loader::LoadOptions const&)  (in dyld) + 552  [0x18927ed44]
              817 dyld4::JustInTimeLoader::loadDependents(Diagnostics&, dyld4::RuntimeState&, dyld4::Loader::LoadOptions const&)  (in dyld) + 256  [0x18927ec1c]
                817 mach_o::Header::forEachLinkedDylib(void (mach_o::Header::DylibInfo const&, bool, bool&) block_pointer) const  (in dyld) + 196  [0x1892b8af8]
                  817 mach_o::Header::forEachLoadCommand(void (mach_o::Header::LoadCommandInfo const&, bool&) block_pointer, mach_o::Error*) const  (in dyld) + 228  [0x1892b7004]
                    817 invocation function for block in mach_o::Header::forEachLinkedDylib(void (mach_o::Header::DylibInfo const&, bool, bool&) block_pointer) const  (in dyld) + 112  [0x1892bbfe0]
                      817 invocation function for block in dyld4::JustInTimeLoader::loadDependents(Diagnostics&, dyld4::RuntimeState&, dyld4::Loader::LoadOptions const&)  (in dyld) + 684  [0x18927f0b0]
                        817 dyld4::Loader::getLoader(Diagnostics&, dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, bool)  (in dyld) + 1116  [0x189283db0]
                          817 dyld4::Loader::forEachPath(Diagnostics&, dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, void (char const*, dyld4::ProcessConfig::PathOverrides::Type, bool&) block_pointer)  (in dyld) + 332  [0x18928342c]
                            817 dyld4::ProcessConfig::PathOverrides::forEachPathVariant(CString, mach_o::Platform, bool, bool, bool&, void (char const*, dyld4::ProcessConfig::PathOverrides::Type, bool&) block_pointer) const  (in dyld) + 444  [0x189264bd4]
                              817 dyld4::ProcessConfig::PathOverrides::forEachInColonList(CString, CString, bool&, void (std::basic_string_view<char>, bool&) block_pointer)  (in dyld) + 156  [0x189263958]
                                817 invocation function for block in dyld4::ProcessConfig::PathOverrides::forEachPathVariant(CString, mach_o::Platform, bool, bool, bool&, void (char const*, dyld4::ProcessConfig::PathOverrides::Type, bool&) block_pointer) const  (in dyld) + 140  [0x189265438]
                                  817 dyld4::Loader::forEachResolvedAtPathVar(dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, dyld4::ProcessConfig::PathOverrides::Type, bool&, void (char const*, dyld4::ProcessConfig::PathOverrides::Type, bool&) block_pointer)  (in dyld) + 800  [0x189283914]
                                    817 invocation function for block in dyld4::Loader::getLoader(Diagnostics&, dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, bool)  (in dyld) + 3248  [0x189284e7c]
                                      817 dyld4::Loader::makeDiskLoader(Diagnostics&, dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, bool, unsigned int)  (in dyld) + 188  [0x189283180]
                                        817 dyld4::JustInTimeLoader::makeJustInTimeLoaderDisk(Diagnostics&, dyld4::RuntimeState&, char const*, dyld4::Loader::LoadOptions const&, bool, unsigned int)  (in dyld) + 152  [0x189281378]
                                          817 dyld4::SyscallDelegate::mapFileReadOnly(Diagnostics&, char const*, int*, unsigned long*, dyld4::FileID*, char*) const  (in dyld) + 100  [0x1892599b8]
                                            817 dyld4::open(char const*, int, int)  (in dyld) + 52  [0x189243b04]
                                              817 open_with_subsystem  (in dyld) + 60  [0x1892a181c]
                                                817 open  (in dyld) + 40  [0x18922c634]
                                                  817 __open  (in dyld) + 8  [0x1892300a8]
        __open  (in dyld)        817
```
