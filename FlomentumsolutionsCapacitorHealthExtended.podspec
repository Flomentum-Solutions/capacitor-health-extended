require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'FlomentumsolutionsCapacitorHealthExtended'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  # Only include Swift/Obj-C source files that belong to the plugin
  s.source_files = 'ios/Sources/HealthPluginPlugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '16.0'
  s.dependency 'Capacitor', '>= 9.0.0-beta.0'
  # Match the Swift shipped with Xcode 27 (Capacitor 9)
  s.swift_version = '5.9'
end
