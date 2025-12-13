require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapacitorHealthExtended'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  # Only include Swift/Obj-C source files that belong to the plugin
  s.source_files = 'ios/Sources/HealthPluginPlugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor',        '~> 8.0'
  s.dependency 'CapacitorCordova', '~> 8.0'
  # Match the Swift shipped with Xcode 26
  s.swift_version = '6.2'
end