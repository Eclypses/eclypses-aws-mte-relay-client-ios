

Pod::Spec.new do |s|
  s.name             = 'MteRelay'
s.version          = '4.4.1'
  s.summary          = 'Eclypses MTE Relay client for iOS'
  s.description      = <<-DESC
                        Eclypses MTE Relay client library for iOS.
                        Provides encryption and relay capabilities for HTTP communication,
                        implemented with Swift wrappers around the MTE library.
                       DESC
  s.homepage         = 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios'
  s.license          = { :type => 'Commercial', :text => 'See LICENSE in repo' }
  s.author           = { 'Eclypses' => 'support@eclypses.com' }

  s.platform         = :ios, '14.0'
  s.swift_versions   = ['5.7', '5.8', '5.9']

  s.source           = { :git => 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git', :tag => s.version.to_s }

  # Include all Swift sources from these submodules
  s.source_files     = 'MteRelay/**/*.{swift,h}', 'Mte/**/*.{swift,h}', 'Core/**/*.{swift,h}', 'MKE/**/*.{swift,h}', 'Kyber/**/*.{swift,h}'

  # If you need to expose public headers
  s.public_header_files = 'Mte/**/*.h', 'Core/**/*.h', 'MKE/**/*.h', 'Kyber/**/*.h'

  # Prebuilt binary
  s.vendored_frameworks = 'Mte/mte.xcframework'
end
