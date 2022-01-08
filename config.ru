require_relative 'kensaku.rb'
require_relative 'hinagata.rb'
require 'cgi'
require 'uri'

Encoding.default_external = "utf-8"

URL = "https://www.city.yokohama.lg.jp/city-info/gyosei-kansa/joho/kokai/johokokaishinsakai/shinsakai/"

FileUtils.cp(Dir.glob("text/*.*"),"tmp")

class ToshinApp
  #初期設定

  # callメソッドはenvを受け取り、3つの値(StatusCode, Headers, Body)を配列として返す
  def call(env)
  	req     = Rack::Request.new(env)
    #p "req.request_method => " + req.request_method
    #p "req.query_string => " + req.query_string
    #p "req.url => " + req.url
    #p "req.script_name => " + req.script_name
    #p "req.fullpath => " + req.fullpath
    #p "req.path => " + req.path
    param = req.POST()
    header  = Hash.new
    kensu = 0
    if req.post? and req.path=="/report/search"
      #Postリクエストのとき、Pyramid.rbのmainを実行する。
      joken, j_str = main(param)
      #p "joken=>"+joken.to_s
      toshin = Toshin.new
      h = toshin.get_hinagata_data(joken)
      kensu = h.size
      #p "kensu => "+kensu.to_s
      if kensu>0
        res = []
        if joken.keys.include? :freeWord
          hinagata = HINAGATA
        else
          hinagata = HINAGATA.sub(/<!--freeWord_search_start-->.*<!--freeWord_search_end-->/m,"")
        end
        h.keys.sort_by{|bango| bango.match(/\d+/)[0].to_i}.reverse.each_with_index do |bango,i|
        	 p bango unless h[bango][:url]
           res[i] = hinagata
           .sub(/<--NO-->/,(i+1).to_s)
           .sub(/<--答申日-->/,h[bango][:toshinbi])
           .sub(/<--答申番号-->/,bango)
           .sub(/<--部会-->/,h[bango][:bukai])
           .sub(/<--実施機関-->/,h[bango][:jisshikikan])
           .sub(/<--件名-->/,h[bango][:kenmei])
           .sub(/<--URL-->/,URL+h[bango][:url])
           if joken.keys.include? :freeWord
             res[i].sub!(/<--該当部分-->/,h[bango][:matched_range])
           end
        end
        html = File.read("SearchResult.html").sub(/<--検索結果-->/,res.join("\n"))
      else
        html = File.read("SearchResult.html").sub(/<--検索結果-->/,"指定された条件に合致する答申は見つかりませんでした。　<input type='submit' value='戻る' class='btn btn-mini'>")
      end
      html.sub!(/<--検索条件-->/,JSON.generate(param))
      html.sub!(/<--結果件数-->/,kensu.to_s)
      html.sub!(/<--検索条件-->/,j_str.to_a.map{|j| j.join(" => ")}.join("<br>"))
      header["Content-Type"]   = 'text/html'
      response                 = html
      #Heroku環境では市サイトから取得したファイルはtmpフォルダに保存するほかないが、
      #ローカル環境で実行した場合はtmpフォルダから本来のnenreibetsuフォルダに移しておく。
      #そして折を見てHeroku環境にPushする。
      #temp_to_regular_folder if req.url.match(/localhost/)
    
    elsif req.post? and param.keys.include? "joken"
      header["Content-Type"] = 'text/html'
      response               = get_index(param)
    #elsif req.path.include? ".css" or req.path.include? ".js"
    #  header["Content-Type"] = get_type(req.path)
    #  p req.path
    #  response               = File.read(req.path[2,-1]) #左端の"/"をはずす。
    else
      header["Content-Type"] = 'text/html'        
      response               = File.read('index.html')
    end
    [ 200, header, [response] ]
  end
  def get_type(filename)
    case filename.match(/\.\w+$/)[0].downcase
    when ".html"        ;  "text/html"
    when ".pdf"         ;  "application/pdf"
    when ".png"         ;  "image/png"
    when ".jpg","jpeg"  ;  "image/jpeg"
    when ".gif"         ;  "image/gif"
    when ".mp3"         ;  "audio/mp3"
    else                ;  "application/octet-stream"
    end
  end
  def get_disposition(filename)
    case filename.match(/\.\w+$/)[0].downcase
    when ".html"         ;  "inline;"
    when ".pdf"          ;  "inline;"
    when ".jpg","jpeg"   ;  "inline;"
    when ".png"          ;  "inline;"
    when ".gif"          ;  "inline;"
    when ".mp3"          ;  "inline;"
    else                 ;  "attachment;"
    end
  end
end
use Rack::Static, :urls => ['/js','/css','/image','/tmp'], :root => '.'
#use Rack::Static, :urls => ['/index.html','/js','/css','/image','/tmp'], :root => '.'
#use Rack::Static, :urls => {'/'=>'index.html'}, :root => '.'

run ToshinApp.new
