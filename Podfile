# Uncomment the next line to define a global platform for your project
platform :ios, '13.0'

# ignore all warnings from all pods
inhibit_all_warnings!

target 'wehe' do
  use_frameworks!
  pod 'IQKeyboardManagerSwift'
  pod 'SwiftyJSON'
  pod 'Alamofire', '~> 5.0'
  pod 'BlueSocket'
  pod 'BlueSSLService'
  pod 'NotificationBannerSwift'
  pod 'SwiftLint'
  pod 'LinearProgressBar'
  pod 'SideMenu', '~> 6.4.8'
  pod 'DropDown'
  pod 'NSData+FastHex'
  pod 'Starscream', '~> 4.0.0'

  target 'weheTests' do
    inherit! :search_paths
    # Pods for testing
  end

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
