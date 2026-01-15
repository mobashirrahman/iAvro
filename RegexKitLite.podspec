Pod::Spec.new do |s|
  s.name = "RegexKitLite"
  s.version = "4.0"
  s.summary = "Lightweight Objective-C Regular Expressions using the ICU Library."
  s.homepage = "http://regexkit.sourceforge.net/RegexKitLite/"
  s.license = { :type => "BSD", :file => "LICENSE" }
  s.authors = { "John Engelhart" => "regexkitlite@gmail.com" }
  s.source = {
    :git => "https://github.com/zhangao0086/RegexKitLite-NoWarning.git",
    :tag => "1.1.0"
  }
  s.source_files = "RegexKitLite-4.0/RegexKitLite.{h,m}"
  s.libraries = "icucore"
  s.requires_arc = false
  s.osx.deployment_target = "10.7"
end
