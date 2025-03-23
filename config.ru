kensaku_logic = :open3
case kensaku_logic
when :open3
  require_relative 'lib/kensaku_with_ripgrep_via_Open3_and_precut.rb'
when :precut
  require_relative 'lib/kensaku_with_ripgrep_and_precut.rb'
when :ripgrep
  require_relative 'lib/kensaku_with_ripgrep.rb'
when :simple
  require_relative 'lib/kensaku.rb'
end
require 'rack'
require 'cgi'
require 'uri'
require 'time'
require_relative 'lib/hinagata.rb'
require_relative 'lib/send_nifty_mail.rb'
require_relative 'lib/add_new_data.rb'
require_relative 'lib/set_range_text.rb'
require_relative 'joho/soumu.rb'

Encoding.default_external = "utf-8" #アプリ全体の設定

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

class ToshinApp
  #初期設定
  def initialize
    @loading_complete = false
    @loading_thread = nil
    start_file_loading
    @toshin = Toshin.new
    @logger = Logger.new(STDOUT)
    @running = true
    @updater_thread = start_background_updater
    at_exit { stop_background_updater }
  end
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
      p joken
      #p "joken => " + JSON.generate(joken)
      wait_for_loading #テキストファイルの転送と範囲テキストデータ作成の完了待ち
      h = @toshin.get_hinagata_data(joken)
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
           .sub(/<--URL-->/,DataProcessor::URL+h[bango][:url])
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
      header["content-type"]   = 'text/html'
      response                 = html
    
    elsif req.post? and req.path=="/return" and param.keys.include? "joken"
    #検索結果画面から「戻る」ボタンで検索条件画面に戻るとき、フォームに前回の検索条件を設定して表示する。
      header["content-type"] = 'text/html'
      response               = get_index(param)
    #elsif req.path.include? ".css" or req.path.include? ".js"
    #  header["content-type"] = get_type(req.path)
    #  p req.path
    #  response               = File.read(req.path[2,-1]) #左端の"/"をはずす。
    elsif req.post? and req.path=="/kuni_toshin"
      p param.keys
      search_word = param["search_word"]
      url = param["url"]
      header["content-type"] = 'text/html'
      response               = get_text_range(url,search_word)

    elsif req.path=="/joho/soumu"
      key = URI.decode_www_form(req.fullpath)[0][1]
      p "key => " + key
      res_array = get_soumu_search_result(key)
      header["content-type"] = 'text/html'
      response               = File.read("joho/SearchResult.html").
                                 sub(/<--検索結果-->/,res_array.join("\n")).
                                 sub(/<--SearchWord-->/,key)

    elsif req.path=="/joho" or req.path=="/joho/" or req.path=="/joho/index.html"
      header["content-type"] = 'text/html'        
      response               = File.read('joho/index.html')
    
    else
      header["content-type"] = 'text/html'        
      response               = File.read('index.html')
    end
    [ 200, header, [response] ]
  end
  def get_type(filename)
    case filename.match(/\.\w+$/)[0].downcase
    when ".html"        ;  "text/html"
    when ".pdf"         ;  "application/pdf"
    when ".png"         ;  "image/png"
    when ".svg"         ;  "image/svg"
    when ".ico"         ;  "image/ico"
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
  
  #答申テキストファイルを転送
  def start_file_loading
    p "Started loading text and deviding their! at #{Time.now}"
    @loading_thread = Thread.new do
      begin
        #tmpフォルダにファイルをダウンロードする.
        S3Client.new.fill_tmp_folder
        #範囲ごとの個別テキストファイルを作成
        SetRange.set_each_range_text
        @loading_complete = true
        p "Ended loading text and devided their! at #{Time.now}"
      rescue => e
        puts "Error during file loading: #{e.message}"
        @loading_complete = false # エラー時はfalseのままにする
      end
    end
  end
  #答申テキストファイルの転送完了まで待機
  def wait_for_loading
    # スレッドが存在し、実行中なら待機
    @loading_thread.join if @loading_thread&.alive?
  end
  #新規答申の確認･取込みのループ処理
  def start_background_updater
    Thread.new do
      while @running
        begin
          #1時間待機
          (60*60).times do
            sleep 1
            break unless @running
          end
          next unless @running
          new_files = DataProcessor.add_new_data(@logger,@toshin)  # メソッド呼び出し
          if new_files
            SetRange.set_each_range_text(new_files)
            @toshin = Toshin.new  # processed_dataを元に更新
            @logger.info("Toshin updated successfully")
          end
        rescue StandardError => e
          @logger.error("Background updater failed: #{e.message}")
          sleep 5
        end
      end
      @logger.info("Background updater stopped")
    end
  end
  #終了時にループ処理も終了
  def stop_background_updater
    @running = false
    @updater_thread.join
  end
end

use Rack::Static, 
      urls: ["/js", "/css","/image","/tmp","/favicon"], 
      root: "."

use Rack::Static, 
      urls: {"/"=>"index.html"},
      root: "."

use TimerMiddleware
begin
  run ToshinApp.new
rescue => e
  send_mail( ([e.message]<<e.backtrace).join("\n") )
end