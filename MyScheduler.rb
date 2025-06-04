#平日は8時30分から22時までの間、土日は12時30分から23時までの間、10分おきに答申検索サイトをリクエストしてスリープに入るのを防止する。
#それ以外の時間帯はユーザーのリクエストがあるまでスリープして課金時間を節約する。
require 'net/http'
require 'uri'

jst = Time.at(Time.now, in: "+09:00")
if jst.saturday? or jst.sunday?
  if ("12:30".."23:00")===jst.strftime("%H:%M")
    #`curl http://toshin-kensaku.herokuapp.com/`
    puts Net::HTTP.get(URI.parse('http://toshin-kensaku.herokuapp.com/'))
  end
else
  if ("08:30".."22:00")===jst.strftime("%H:%M")
    #`curl http://toshin-kensaku.herokuapp.com/`
    puts Net::HTTP.get(URI.parse('http://toshin-kensaku.herokuapp.com/'))
  end
end

#バッチ処理
if ("03:00".."03:20")===jst.strftime("%H:%M")
  require_relative 'lib/add_new_data'
end

# "Cloud Run"の答申検索
puts Net::HTTP.get(URI.parse('https://rack-app-806339164409.asia-northeast1.run.app/file_check'))