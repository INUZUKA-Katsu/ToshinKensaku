#8時から22時までの間、10分おきに答申検索サイトをリクエストしてスリープに入るのを防止する。
#22時から8時まではユーザーのリクエストがあるまでスリープして課金時間を節約する。
require 'net/http'
require 'uri'

jst = 8
while (8..22)===jst do
  #`curl http://toshin-kensaku.herokuapp.com/`
  p Net::HTTP.get(URI.parse('http://toshin-kensaku.herokuapp.com/'))
  p Time.at(Time.now, in: "+09:00")
  sleep 10*60
  jst = Time.at(Time.now, in: "+09:00").hour
end
