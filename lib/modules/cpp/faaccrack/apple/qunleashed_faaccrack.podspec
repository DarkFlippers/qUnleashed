#
# Dart FFI pod for SubGHz rolling-code seed recovery. Compiles the unity
# forwarder (which #includes the library's C sources one level up). Referenced
# as a development pod from ios/Podfile and macos/Podfile.
#
Pod::Spec.new do |s|
  s.name             = 'qunleashed_faaccrack'
  s.version          = '0.0.1'
  s.summary          = 'FAAC SLH / Genius / BFT / Erreka seed recovery (FFI).'
  s.description      = <<-DESC
Recovers the per-installation seed of a rolling-code remote from a fixed code
and two or more consecutive hops, so the remote can be rebuilt as a
transmittable .sub rather than replayed. The search engine ships obfuscated; see
lib/modules/cpp/faaccrack/BUILD_NOTES.md.
                       DESC
  s.homepage         = 'https://github.com/mishamyte/qUnleashed'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'qUnleashed' => 'noreply@localhost' }

  s.source           = { :path => '.' }
  s.source_files     = 'qunleashed_faaccrack_unity.c'
  s.requires_arc     = false

  s.ios.dependency 'Flutter'
  s.ios.deployment_target = '12.0'
  s.osx.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.15'

  # HEADER_SEARCH_PATHS lets the #included sources find faaccrack.h, and the
  # hardnested directory is there for pthread_shim.h - which Apple never
  # actually reaches, since the shim is behind a _WIN32 guard, but the include
  # has to resolve for the file to preprocess.
  #
  # -Dmain= renames the engine's command-line entry point away; the CMake builds
  # pass the same thing.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'GCC_TREAT_WARNINGS_AS_ERRORS' => 'NO',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/.." "$(PODS_TARGET_SRCROOT)/../../hardnested"',
    'OTHER_CFLAGS' => '-O3 -w -Dmain=faaccrack_cli_main',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
