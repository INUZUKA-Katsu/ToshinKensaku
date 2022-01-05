require_relative 'kensaku.rb'
require_relative 'hinagata.rb'
require 'cgi'
require 'uri'
#require './sync_mp3.rb'

Encoding.default_external = "utf-8"

#make_midashi_json
FileUtils.cp(Dir.glob("text/*.*"),"tmp")

class ToshinApp
  #初期設定

  # callメソッドはenvを受け取り、3つの値(StatusCode, Headers, Body)を配列として返す
  def call(env)
  	req     = Rack::Request.new(env)

    #p "req.request_method => " + req.request_method
    #p "req.query_string => " + req.query_string
    #p "req.fullpath => " + req.fullpath
    #p "req.url => " + req.url
    #p "req.path => " + req.path
    #p "req.script_name => " + req.script_name

    header  = Hash.new
  	if req.post?
      #Postリクエストのとき、Pyramid.rbのmainを実行する。
  	  param = req.POST()
      joken = main(param)
      #p "joken=>"+joken.to_s
      toshin = Toshin.new
      h = toshin.get_hinagata_data(joken)
      if h.size>0
        res = []
        if joken.keys.include? :freeWord
          hinagata = HINAGATA
        else
          hinagata = HINAGATA.sub(/<!--freeWord_search_start-->.*<!--freeWord_search_end-->/m,"")
        end
        h.keys.sort_by{|bango| bango.match(/\d+/)[0].to_i}.reverse.each_with_index do |num,i|
        	 p num unless h[num][:url]
           res[i] = hinagata
           .sub(/<--NO-->/,(i+1).to_s)
           .sub(/<--答申日-->/,h[num][:toshinbi])
           .sub(/<--答申番号-->/,num)
           .sub(/<--部会-->/,h[num][:bukai].to_s)
           .sub(/<--実施機関-->/,h[num][:jisshikikan].to_s)
           .sub(/<--件名-->/,h[num][:kenmei].to_s)
           .sub(/<--URL-->/,URL+h[num][:url].to_s)
           if joken.keys.include? :freeWord
             res[i].sub!(/<--該当部分-->/,h[num][:matched_range])
           end
        end
        html = File.read("SearchResult.html").sub(/<--検索結果-->/,res.join("\n"))
      else
        html = File.read("SearchResult.html").sub(/<--検索結果-->/,"指定された条件に合致する答申は見つかりませんでした。")
      end
      header["Content-Type"]   = 'text/html'
      response                 = html
      #Heroku環境では市サイトから取得したファイルはtmpフォルダに保存するほかないが、
      #ローカル環境で実行した場合はtmpフォルダから本来のnenreibetsuフォルダに移しておく。
      #そして折を見てHeroku環境にPushする。
      #temp_to_regular_folder if req.url.match(/localhost/)
    else
      path = CGI.unescape(req.path())
      case path
      when '/index.html'
        header["Content-Type"] = 'text/html'        
        response               = File.read('/index.html')
      end
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
use Rack::Static, :urls => ['/index.html','/js','/css','/image','/tmp'], :root => '.'
use Rack::Static, :urls => {'/'=>'index.html'}, :root => '.'

run ToshinApp.new
