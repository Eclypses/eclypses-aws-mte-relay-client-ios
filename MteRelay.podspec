Pod::Spec.new do |s|
  s.name         = 'MteRelay'
  s.version      = '4.4.3'
  s.summary      = 'Eclypses MTE Relay Client for iOS'
  s.description  = 'Swift wrapper and client for the Eclypses MTE Relay, including the precompiled Mte static library.'
  s.homepage     = 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios'
  s.license      = { :type => 'MIT' }
  s.authors      = { 'Eclypses' => 'support@eclypses.com' }

  s.platform     = :ios, '16.0'
  s.swift_version = '5.9'

  s.source = { :git => "https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git", :tag => "4.4.3" }

  # All your Swift source files and internal C header files are listed here.
  s.source_files = [
  '**/*.swift',
  'Mte/include/*.h']

  s.vendored_frameworks = 'Mte/mte.xcframework'
  
  s.preserve_paths = 'Mte/include', 'Mte/mte.xcframework'

  s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      
      'HEADER_SEARCH_PATHS' => '$(inherited) ' \
                               '"${PODS_TARGET_SRCROOT}/Mte/include" ' \
                               '"${BUILT_PRODUCTS_DIR}/${TARGET_NAME}.framework/Headers"',

      'OTHER_LDFLAGS' => '-ObjC',
    }
end
