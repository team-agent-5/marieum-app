Pod::Spec.new do |s|
  s.name             = 'duplex_audio'
  s.version          = '0.1.0'
  s.summary          = 'Recording and playback through one voice-processing audio engine.'
  s.homepage         = 'https://github.com/team-agent-5/marieum-app'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Marieum'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
