

Pod::Spec.new do |s|
  s.name             = 'MteRelay'
  s.version          = '4.4.2'
  s.summary          = 'Eclypses MTE Relay client for iOS'
  s.description      = <<-DESC
                        Eclypses MTE Relay client library for iOS.
                        Provides encryption and relay capabilities for HTTP communication,
                        implemented with Swift wrappers around the MTE library.
                       DESC
  s.homepage         = 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios'
  s.license          = { :type => 'MIT', :text => 'See LICENSE in repo' }
  s.author           = { 'Eclypses' => 'support@eclypses.com' }

  s.platform         = :ios, '14.0'
  s.swift_versions   = ['5.7', '5.8', '5.9']

  s.source           = { :git => 'https://github.com/Eclypses/eclypses-aws-mte-relay-client-ios.git', :tag => s.version.to_s }

  # Main relay interface
  s.subspec 'MteRelay' do |ss|
    ss.source_files = 'MteRelay/**/*.{swift,h}'
    ss.dependency 'MteRelay/Mte'
    ss.dependency 'MteRelay/Core'
    ss.dependency 'MteRelay/MKE'
    ss.dependency 'MteRelay/Kyber'
  end

  # Binary + wrapper
  s.subspec 'Mte' do |ss|
    ss.source_files        = 'Mte/**/*.{swift,h}'
    ss.public_header_files = 'Mte/**/*.h'
    ss.vendored_frameworks = 'Mte/mte.xcframework'
  end

  s.subspec 'Core' do |ss|
    ss.source_files = 'Core/**/*.swift'
    ss.dependency 'MteRelay/Mte'
  end

  s.subspec 'MKE' do |ss|
    ss.source_files = 'MKE/**/*.swift'
    ss.dependency 'MteRelay/Core'
  end

  s.subspec 'Kyber' do |ss|
    ss.source_files = 'Kyber/**/*.swift'
    ss.dependency 'MteRelay/Mte'
    ss.dependency 'MteRelay/Core'
  end
end
