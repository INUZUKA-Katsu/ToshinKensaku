#平日は8時30分から22時までの間、土日は12時30分から23時までの間、10分おきに答申検索サイトをリクエストしてスリープに入るのを防止する。
#それ以外の時間帯はユーザーのリクエストがあるまでスリープして課金時間を節約する。
require 'net/http'
require 'uri'

jst = Time.at(Time.now, in: "+09:00")
if jst.saturday? or jst.sunday?
  if ("12:30".."23:00")===jst.strftime("%H:%M")
    #`curl http://toshin-kensaku.herokuapp.com/`
    p Net::HTTP.get(URI.parse('http://toshin-kensaku.herokuapp.com/'))
  end
else
  if ("08:30".."22:00")===jst.strftime("%H:%M")
    #`curl http://toshin-kensaku.herokuapp.com/`
    p Net::HTTP.get(URI.parse('http://toshin-kensaku.herokuapp.com/'))
  end
end
