//// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

Pod::Spec.new do |s|
  s.name             = 'MteRelay'
s.version          = '4.4.0'
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
