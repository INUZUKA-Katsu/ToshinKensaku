kensaku_logic = :ripgrep
case kensaku_logic
when :open3
  require_relative 'kensaku_with_ripgrep_via_Open3_and_precut.rb'
when :precut
  require_relative 'kensaku_with_ripgrep_and_precut.rb'
when :ripgrep
  require_relative 'kensaku_with_ripgrep.rb'
when :simple
  require_relative 'kensaku.rb'
end
require_relative 'hinagata.rb'
require_relative 'joho/soumu.rb'
require 'cgi'
require 'uri'
require 'time'
require './send_nifty_mail'

Encoding.default_external = "utf-8"

URL = "https://www.city.yokohama.lg.jp/city-info/gyosei-kansa/joho/kokai/johokokaishinsakai/shinsakai/"

#tmpフォルダに不足するファイルをダウンロードする.
S3Client.new.fill_tmp_folder

class TimerMiddleware
  def initialize(app)
    @app = app
  end
  def call(env)
    start_time = Time.now
    status, headers, response = @app.call(env)  # 次のミドルウェアまたはアプリへ
    elapsed_time = Time.now - start_time
    puts "Response Time: #{elapsed_time} sec"
    [status, headers, response]  # レスポンスを返す
  end
end
class AddNewData
  def initialize(app)
    @app = app
    @time_stamp = "#{__dir__}/tmp/search_new_pdf.txt"
  end
  def call(env)
    request = Rack::Request.new(env)
    if request.path == '/'
      begin
        if !File.exist?(@time_stamp) or ( Time.parse(File.read(@time_stamp))+24*60*60 < Time.now )
          pid = Process.spawn("ruby add_new_data.rb", out: STDOUT, err: STDERR)
          Process.detach(pid)
        end
      rescue => e
        puts "Error: #{e.message}"
      end
    end
    @app.call(env)  # 次のミドルウェアまたはアプリへレスポンスを返す
  end
end

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
    if (req.post? and req.path=="/report/search") or (req.get? and req.path=="/joho/yokohama")
    # 「答申データベース検索」画面で検索を実行したとき
    # または、「例規集、ほか各種検索」画面で「横浜市の答申を検索(DB検索)」を実行したときの処理
      if req.post?
        #「答申データベース検索」の検索実行の場合は、
        # kensaku.rb の postData_arrange でリクエストデータを取得する。
        joken, j_str = postData_arrange(param)
      else
        #「例規集、ほか各種検索」画面の「横浜市の答申を検索(DB検索)」の場合は、
        # kensaku.rb の getData_arrange でリクエストデータを取得する。
        joken, j_str = getData_arrange(req.query_string)
      end
      #p "joken => " + JSON.generate(joken)
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
    
    elsif req.post? and req.path=="/return" and param.keys.include? "joken"
    #検索結果画面から「戻る」ボタンで検索条件画面に戻るとき、フォームに前回の検索条件を設定して表示する。
      header["Content-Type"] = 'text/html'
      response               = get_index(param)
    #elsif req.path.include? ".css" or req.path.include? ".js"
    #  header["Content-Type"] = get_type(req.path)
    #  p req.path
    #  response               = File.read(req.path[2,-1]) #左端の"/"をはずす。
    elsif req.post? and req.path=="/kuni_toshin"
      p param.keys
      search_word = param["search_word"]
      url = param["url"]
      header["Content-Type"] = 'text/html'
      response               = get_text_range(url,search_word)

    elsif req.path=="/joho/soumu"
      key = URI.decode_www_form(req.fullpath)[0][1]
      p "key => " + key
      res_array = get_soumu_search_result(key)
      header["Content-Type"] = 'text/html'
      response               = File.read("joho/SearchResult.html").
                                 sub(/<--検索結果-->/,res_array.join("\n")).
                                 sub(/<--SearchWord-->/,key)

    elsif req.path=="/joho" or req.path=="/joho/" or req.path=="/joho/index.html"
      header["Content-Type"] = 'text/html'        
      response               = File.read('joho/index.html')

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

use AddNewData
use Rack::Static, :urls => ['/js','/css','/image','/tmp'], :root => '.'
use Rack::Static, :urls => {'/'=>'/index.html'}, :root => '.'
use TimerMiddleware
begin
  run ToshinApp.new
rescue => e
  send_nifty_mail( ([e.message]<<e.backtrace).join("\n") )
end