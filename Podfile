source 'https://cdn.cocoapods.org/'
platform :osx, '11.0'

target 'Avro Keyboard'
pod 'RegexKitLite', :podspec => 'RegexKitLite.podspec'
pod 'FMDB', :git => 'https://github.com/ccgus/fmdb.git', :tag => '2.7.5'
# Auto-updates. Signed with Sparkle's own EdDSA (ed25519) keys, so this does
# not require an Apple Developer Program membership or a Developer ID cert.
pod 'Sparkle', '~> 2.9'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
      config.build_settings['ARCHS'] = 'x86_64 arm64'
    end
  end
end
