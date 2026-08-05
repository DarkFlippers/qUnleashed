#
# Dart FFI pod for the host-side hardnested attack. Compiles the unity forwarder
# (which #includes the shared C sources one level up). Referenced as a
# development pod from ios/Podfile and macos/Podfile.
#
Pod::Spec.new do |s|
  s.name             = 'qunleashed_hardnested'
  s.version          = '0.0.1'
  s.summary          = 'Host-side MIFARE Classic hardnested key recovery (FFI).'
  s.description      = <<-DESC
Ciphertext-only hardnested attack (Proxmark3-derived, via ChameleonUltraGUI),
built as a Dart FFI library. Bitflip tables are embedded and decompressed by the
bundled minlzlib.
                       DESC
  s.homepage         = 'https://github.com/mishamyte/qUnleashed'
  s.license          = { :type => 'GPLv3' }
  s.author           = { 'qUnleashed' => 'noreply@localhost' }

  s.source           = { :path => '.' }
  s.source_files     = 'qunleashed_hardnested_unity.c'
  s.requires_arc     = false

  s.ios.dependency 'Flutter'
  s.ios.deployment_target = '12.0'
  s.osx.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.15'

  # HEADER_SEARCH_PATHS lets the #included engine sources find their headers;
  # OTHER_CFLAGS force-includes hn_namespace.h (crapto1 symbol renaming, so this
  # framework coexists with qunleashed_mfkey32's crapto1 in the app binary).
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'GCC_TREAT_WARNINGS_AS_ERRORS' => 'NO',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/.." "$(PODS_TARGET_SRCROOT)/../hardnested" "$(PODS_TARGET_SRCROOT)/../minlzlib" "$(PODS_TARGET_SRCROOT)/../pm3"',
    'OTHER_CFLAGS' => '-O3 -include "$(PODS_TARGET_SRCROOT)/../hn_namespace.h"',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
