require 'json'
require 'kconv'
require "net/https"
require 'open-uri'
require 'parallel'
require 'open3'
require_relative 's3_client'

STDOUT.sync = true

#答申データベース検索画面で検索した場合の処理
def postData_arrange(param)
  #p param
  joken = Hash.new
  j_str = Hash.new
  if param["searchQuery"]!=""
    joken[:freeWordRange] = ""
    joken[:freeWord] = param["searchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["searchType"]
    range = "答申全体"
  end
  if param["ketsuronSearchQuery"]!=""
    joken[:freeWordRange] = "ketsuron"
    joken[:freeWord] = param["ketsuronSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["ketsuronSearchType"]
    range = "審査会の結論"
  end
  if param["seikyuninSearchQuery"]!=""
    joken[:freeWordRange] = "seikyunin"
    joken[:freeWord] = param["seikyuninSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["seikyuninSearchType"]
    range = "審査請求人の意見"
  end
  if param["jisshikikanSearchQuery"]!=""
    joken[:freeWordRange] = "jisshikikan"
    joken[:freeWord] = param["jisshikikanSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["jisshikikanSearchType"]
    range = "実施機関の説明"
  end
  if param["shinsakaiSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakai"
    joken[:freeWord] = param["shinsakaiSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakaiSearchType"]
    range = "審査会の判断"
  end
  if param["shinsakailastSearchQuery"]!=""
    joken[:freeWordRange] = "shinsakailast"
    joken[:freeWord] = param["shinsakailastSearchQuery"].split(/\s+|　+/)
    joken[:freeWordType] = param["shinsakailastSearchType"]
    range = "審査会の判断の結論部分"
  end
  if joken[:freeWordType]=="and"
    j_str[range]= joken[:freeWord].map{|w| '"'+w+'"'}.join(" かつ ")
  elsif joken[:freeWordType]=="or"
    j_str[range]= joken[:freeWord].map{|w| '"'+w+'"'}.join(" 又は ")
  end
  
  if param["johoKokai"]=="on" and param["kojinjohoHogo"]==nil
    joken[:jorei] = "情報公開"
    j_str["条例"] = "情報公開"
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]=="on"
    joken[:jorei] = "個人情報"
    j_str["条例"] = "個人情報"
  elsif param["johoKokai"]==nil and param["kojinjohoHogo"]==nil
    joken[:jorei] = ""
    j_str["条例"] = "なし"
  end
  
  joken[:seikyu] = ""
  seikyu = []
  if param["kaijiSeikyu"]=="on"
    joken[:seikyu] += "開示請求"
    seikyu << "開示請求"
  end
  if param["teiseiSeikyu"]=="on"
    joken[:seikyu] += "訂正請求"
    seikyu << "訂正請求"
  end
  if param["teishiSeikyu"]=="on"
    joken[:seikyu] += "利用停止請求"
    seikyu << "利用停止請求"
  end
  j_str["請求"] = seikyu.join(",")
  
  bukai = []
  if param["bukai"]!=""
    joken[:bukai] = param["bukai"]
    bukai << joken[:bukai]
  end
  if param["bukaiSearchQuery"]!=""
    joken[:bukaiQuery] = param["bukaiSearchQuery"].split(/\s+|　+/)
    bukai += joken[:bukaiQuery]
  end
  j_str["部会"] = bukai.join(",") unless bukai==[]

  if param["iinSearchQuery"]!=""
    joken[:iinQuery] = param["iinSearchQuery"].split(/\s+|　+/)
    j_str["審査会委員"] = joken[:iinQuery].join(",")
  end
  
  kikan = []
  if param["jisshiKikan"]!=""
    joken[:kikan] = param["jisshiKikan"]
    kikan << joken[:kikan]
  end
  if param["jisshiaKikanQuery"]!=""
    joken[:kikanQuery] = param["jisshiaKikanQuery"].split(/\s+|　+/)
    kikan += joken[:kikanQuery]
  end
  j_str["実施機関"]=kikan.join(",") unless kikan==[]

  if param["reportDateFromYear"]!=""
    gen   = param["reportDateFromEra"]
    y     = param["reportDateFromYear"]
    m     = param["reportDateFromMonth"]
    d     = param["reportDateFromDate"]
    range = param["reportDateRange"]
    if gen=="heisei"
      yyyy = y.to_i+1988
      j_str["答申日"] = "平成#{y}年"
    else
      yyyy = y.to_i+2018
      j_str["答申日"] = "令和#{y}年"
    end
    if m==""
      yyyymm = yyyy.to_s+"01"
      j_str["答申日"]+="1月"
    else
      yyyymm = yyyy.to_s+("0"+m)[-2,2]
      j_str["答申日"]+="#{m}月"
    end
    if d==""
      yyyymmdd = yyyymm.to_s+"01"
      j_str["答申日"]+="1日"
    else
      yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
      j_str["答申日"]+="#{d}日"
    end
    if range=="kan" or range=="go"
      joken[:yyyymmdd] = {:from => yyyymmdd}
      j_str["答申日"]+=" 〜 "
    elsif range=="zen"
      joken[:yyyymmdd] = {:to => yyyymmdd}
      j_str["答申日"] = " 〜 " + j_str["答申日"]
    elsif range==""
      joken[:yyyymmdd] = yyyymmdd
    end
  end

  if param["reportDateToYear"]!=""
    range = param["reportDateRange"]
    # rangeが "〜" 以外のときは右側の日付が入力されていても無視する。
    if range=="kan"
      gen   = param["reportDateToEra"]
      y     = param["reportDateToYear"]
      m     = param["reportDateToMonth"]
      d     = param["reportDateToDate"]
      if gen=="heisei"
        yyyy = y.to_i+1988
        j_str["答申日"] += "平成#{y}年"
      else
        yyyy = y.to_i+2018
        j_str["答申日"] += "令和#{y}年"
      end
      if m==""
        yyyymm = yyyy.to_s+"12"
        j_str["答申日"]+="12月"
      else
        yyyymm = yyyy.to_s+("0"+m)[-2,2]
        j_str["答申日"]+="#{m}月"
      end
      if d==""
        yyyymmdd = yyyymm.to_s+"1"
        j_str["答申日"]+="1日"
      else
        yyyymmdd = yyyymm.to_s+("0"+d)[-2,2]
        j_str["答申日"]+="#{d}日"
      end
      joken[:yyyymmdd][:to] = yyyymmdd
    end
  end
  if param["reportNoFromNo"]!=""
  	num = param["reportNoFromNo"]
    range = param["reportNoRange"]
    
    if range=="go" or range=="kan"
      joken[:num]={:from => num}
      j_str["答申番号"] = "第#{num}号〜"
    
    elsif range=="zen"
      joken[:num]={:to => num}
      j_str["答申番号"] = "〜第#{num}号"
    else
      joken[:num]=num
      j_str["答申番号"] = "第#{num}号"
    end
  end
  if param["reportNoToNo"]!=""
  	num = param["reportNoToNo"]
    range = param["reportNoRange"]
    if range=="kan"
      joken[:num][:to]=num
      j_str["答申番号"] += "第#{num}号"
    end
  end
  [ joken, j_str ]
end
#「例規集、ほか各種検索」で検索した場合の処理
def getData_arrange(query_string)
  joken={}
  j_str={}
  key_word = Hash[URI.decode_www_form(query_string)]["key_word"]
  joken[:seikyu] = "開示請求"
  joken[:freeWordRange] = "shinsakai"
  joken[:freeWord] = key_word.split(/\s+|　+/)
  joken[:freeWordType]="and"
  j_str["審査会の判断"]=joken[:freeWord].map{|w| '"'+w+'"'}.join(" かつ ")
  j_str["請求"]="開示請求"
  [ joken, j_str ]
end

class Toshin
  attr_reader :midashi
  ROOT_DIR = File.expand_path('..', __dir__)
  TMP_DIR = File.join(ROOT_DIR, 'tmp')
  def initialize
    @s3 = S3Client.new
    @midashi = JSON.parse(@s3.read("bango_hizuke_kikan.json"), symbolize_names: true)
    @logger = Logger.new(STDOUT)
  end
  #フリーワード以外の条件から対象ファイルを絞り込む。
  def search(joken) #jokenはハッシュ
    selected = @midashi
    begin
      if joken.keys.include? :jorei
         selected = selected.select{|h|
           #p "h[:jorei].include?(joken[:jorei]) => " + h[:jorei] + " include? " + joken[:jorei]
           joken[:jorei].include?(h[:jorei])
         }
      end
      p :s1
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin
      if joken.keys.include? :seikyu and joken[:seikyu] != "開示請求訂正請求利用停止請求"
         selected = selected.select{|h|
           h[:seikyu] and h[:seikyu]!="" and joken[:seikyu].include?(h[:seikyu])
         }
      end
      p :s2
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin
      if joken.keys.include? :num
         if joken[:num].class==String
           selected = selected.select{|h| h[:num_array].include?(joken[:num])}
         elsif joken[:num].class==Hash
           j = joken[:num]
           if j.keys.size==2
             a = (j[:from]..j[:to]).to_a
             selected = selected.select{|h| (h[:num_array] & a).size>0 }
           elsif j.keys[0]==:from
             selected = selected.select{|h| j[:from].to_i <= h[:num_array].max.to_i }
           elsif j.keys[0]==:to
             selected = selected.select{|h| j[:to].to_i >= h[:num_array].min.to_i }
           end
         end
      end
      p :s3
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin      
      if joken.keys.include? :bango
         selected = selected.select{|h| h[:bango].include?(joken[:bango])}
      end
      p :s4
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin  
      if joken.keys.include? :yyyymmdd
         if joken[:yyyymmdd].class==String
           selected = selected.select{|h| h[:yyyymmdd].include?(joken[:yyyymmdd])}
         elsif joken[:yyyymmdd].class==Hash
           j = joken[:yyyymmdd]
           if j.keys.size==2
             selected = selected.select{|h| h[:yyyymmdd].between?(j[:from],j[:to])}
           elsif j.keys[0]==:from
             selected = selected.select{|h| j[:from] <= h[:yyyymmdd]}
           elsif j.keys[0]==:to
             selected = selected.select{|h| h[:yyyymmdd] <= j[:to]}
           end
         end
      end
      p :s5
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin
      if joken.keys.include? :toshinbi
         selected = selected.select{|h| h[:toshinbi].include?(joken[:toshinbi])}
      end
      p :s6
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin  
      if joken.keys.include? :kikan
         selected = selected.select{|h| h[:jisshikikan].include?(joken[:kikan])}
      end
      p :s7
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin
      if joken.keys.include? :kikanQuery
         joken[:kikanQuery].each do |k|
           selected = selected.select{|h| h[:jisshikikan].include?(k)}
         end
      end
      p :s8
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin  
      if joken.keys.include? :bukai
         selected = selected.select{|h| h[:bukai].include?(joken[:bukai])}
      end
      p :s9
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin
      if joken.keys.include? :bukaiQuery
         ary = []
         selected_ary = joken[:bukaiQuery].map{|bukai| selected.select{|h| h[:bukai].include? bukai}}
         selected_ary.each do |selected|
           ary =  ary | selected
         end
         selected = ary
      end
      p :s10
      p selected.size
    rescue =>e
      err_logger(e)
    end
    begin  
      if joken.keys.include? :iinQuery
         ary = []
         selected_ary = joken[:iinQuery].map{|iin| selected.select{|h| h[:iin].include? iin}}
         selected_ary.each do |selected|
           ary =  ary | selected
         end
         selected = ary
      end
    rescue =>e
      err_logger(e)
    end
    selected
  end
  def get_url(joken)
  	search(joken).map{|h| h[:url]}
  end
  def get_bango(joken="")
    if joken == ""
      @midashi.map{|h| h[:bango]}
    else
      search(joken).map{|h| h[:bango]}
    end
  end
  def get_toshinbi(bango)
    @midashi.find{|h| h[:bango]==bango}[:toshinbi]
  end
  def get_jisshikikan(bango)
    @midashi.find{|h| h[:bango]==bango}[:jisshikikan]
  end
  def get_bukai(bango)
    @midashi.find{|h| h[:bango]==bango}[:bukai]
  end
  def get_file_name(bango)
    @midashi.find{|h| h[:bango]==bango}[:file_name]
  end
  def get_kenmei(bango)
    @midashi.find{|h| h[:bango]==bango}[:kenmei]
  end
  def get_url(bango)
    @midashi.find{|h| h[:bango]==bango}[:url]
  end

  #########################################
  #   メイン関数（config.ruから呼び出される）
  #########################################
  def get_hinagata_data(joken)
    missing_files = nil
    if joken.keys.include? :freeWord
      selected, missing_files = freeWord_search(joken)
    else
      selected = search(joken)
    end
    res = Hash.new
    p "selected = freeWord_search(joken)"
    p 'selected.size: ' + selected.size.to_s
    selected.each do |h|
      bango = h[:bango]
      h.delete(:bango)
      h.delete(:yyyymmdd)
      h.delete(:file_name)
      h.delete(:iin)
      h.delete(:jorei)
      h.delete(:seikyu)
      res[bango] = h
    end
    [res, missing_files]   # config.ruに返す
  end

  def freeWord_search(joken)
    def ripgrep(file_name_array, word_array, type)
      def get_matching_files(search_word, files, missing_files=nil)
        stdout, stderr, status = Open3.capture3('rg', '--no-ignore', '--files-with-matches', '-l', search_word, *files)
        if status.success?      
          matching_file_path_array = stdout.split("\n")
        elsif status.exitstatus == 2
          errors = stderr.split("\n")
          critical_errors = errors.reject { |e| e.include?("No such file or directory") }
          if critical_errors.empty?           # "No such file or directory"以外のエラーはないとき
            matching_file_path_array = stdout.split("\n")
            missing_files = errors.map{|err| err.match(/答申[^a-z]+/)[0]}
          else  "No such file or directory"   # "No such file or directory"以外のエラーがあるとき
            matching_file_path_array = []
          end
        else
          matching_file_path_array = []
        end
        [matching_file_path_array, missing_files]
      end

      # ファイルパスを構築
      files = file_name_array.map { |file_name| "#{TMP_DIR}/#{file_name}" }

      if type == 'or'
        # OR検索: 単語を | で結合した正規表現で一度に検索
        search_terms = word_array.join('|')
        matching_file_path_array, missing_files = get_matching_files(search_terms, files)

      elsif type == 'and'
        if word_array.size == 1
          # 単語が1つの場合: 直接検索
          search_terms = word_array[0]
          matching_file_path_array, missing_files = get_matching_files(search_terms, files)
        else
          # 複数単語のAND検索: 各単語で順次フィルタリング
          matching_file_path_array = files.dup # 初期候補は全ファイル
          missing_files = nil
          word_array.each do |word|
            matching_file_path_array, missing_files = get_matching_files(word, matching_file_path_array, missing_files)
              break if matching_file_path_array.empty? # マッチがなくなれば終了
          end
        end
      end
      [matching_file_path_array, missing_files]
    end
    def reg_pattern(word_array)
      # 検索語が複数の時は、"[^\n]*(検索語1|検索語2|検索語3).*(検索語1|検索語2|検索語3).*?\n"
      # という正規表現をつくる。（scanで取得できるように全体を半角括弧で囲う。）
        "([^\n]{0,100}(#{word_array.join('|')})(.*(#{word_array.join('|')}))?[^\n]{0,100}\n?)"
    end
    #************** 答申のテキストから該当箇所を切り出す *****************
    def exec_search(str,word_array,type)
      #全角数字を半角に変換
      str = str.tr("０-９","0-9")

      #*** 各語句の前後200字を切り出し、つなげる ***
      begin
      #p "[^\n]{0,200}#{word_array.join('|')}[^\n]{0,200}\n?"
        range_array = str.scan(/#{reg_pattern(word_array)}/m).
                      map do |s|
                        s[0].gsub!(/#{word_array.join("|")}/m,'<strong>\&</strong>').chomp
                      end
        str = range_array.join("<br><br>")
        str
      rescue
        #p reg_pattern(word_array)
        #p str
      end
    end

    #***** ここから、検索の流れに入る。*****

    #*** 下準備 ***
    word_array,type = joken[:freeWord],joken[:freeWordType]
    #puts "range_joken : #{range_joken}"
    #ユーザーが正規表現を使いやすくする。”\”は取り扱いが難しいので"¥"が使えるようにする。
    word_array.map!{|w| w.gsub('¥',"\\")}
    #検索語句に半角括弧が含まれるとき、正規表現の特殊ではないと判断されるものはエスケープ処理する。
    word_array.map! do |w|
      if w.match(/\(|\)/)
        if w.match(/\(.*\|.*\)|\(.*\)[\?\*\+\{]/)
        #正規表現の一部と見なされるときはそのまま
          w
        else
        #正規表現半角括弧ではないと考えらるときは半角括弧をエスケープする。
          w.gsub( /\(/,'\(' ).gsub( /\)/,'\)' )
        end
      else
        w
      end
    end
    #検索語に含まれる数字をすべて半角に変換する。
    word_array.map!{|w| w.tr("０-９","0-9")}

    #******* フリーワード以外の条件でmidashi配列を絞り込む。*******
    selected = search(joken)
    puts "答申ファイル数は #{@midashi.size} 件"
    puts "search => 対象は #{selected.size} 件"
    
    #******* ripgrepで対象ファイルを絞り込む。*******************
    if joken[:freeWordRange]==""
      file_name_array = selected.map{|h| h[:file_name]}
    else
      #範囲条件があるとき
      file_name_array = selected.map{|h|
        if h[:file_name]
          h[:file_name].sub(/\.txt/,"#{joken[:freeWordRange]}.txt")
        else
          p "h[:file_name]=nil"
          p h
        end 
      }
    end
    file_path_array, missing_files = ripgrep(file_name_array, word_array, type)
    puts "ripgrep => 対象は #{file_path_array.size} 件"

    file_path_array.each{|path| p path if path.size>100}
    puts

    results = Parallel.map(file_path_array, in_processes: Etc.nprocessors) do |path|
      #p "処理中: PID: #{Process.pid}"
      retry_num = 0
      begin
        #path = "#{TMP_DIR}/#{h[:file_name]}"
        str = File.read(path).encode("UTF-8", :invalid => :replace)
      rescue
        if File.exist?(path)
          retry_num += 1
          if retry_num < 5
            p File.basename(path) + "の読み込みエラー ⇒ リトライします!(#{retry_num}回目)"
            retry
          else
            p File.basename(path) + "を読み込めませんでした!"
          end
        else
          p File.basename(path) + "の読み込みエラー ファイルがありません!"
        end
        str = " "
      end
      matched_range = exec_search(str,word_array,type)
      if matched_range
        #h.merge({:matched_range => matched_range})  # `merge` を使って新しいハッシュを返す
        file_name_origin = File.basename(path).sub(/(.*号(まで)?)(.+?)\.txt/,'\1.txt')
        begin
        selected.find{|h| h[:file_name] == file_name_origin}&.
                          merge({:matched_range => matched_range})
        rescue =>e
          p e.message
        end
      else
        nil
      end
    end
    File.write("parallel_result.json", JSON.generate(results)) #debug用
    return [results.compact,missing_files] # nilを除外
  end
end

#検索結果から検索画面に戻る際の処理
def get_index(param)
  str = File.read("index.html")
  return str unless param.keys.include? "joken"
  h = JSON.parse(param["joken"])
  ["johoKokai","kojinjohoHogo","kaijiSeikyu","teiseiSeikyu","teishiSeikyu"].each do |k|
    if h.keys.include? k
      str.sub!(/(#{k}.*)( checked="checked")?( class="checkbox">)/,'\1 checked="checked"\3')
    else
      str.sub!(/(#{k}.*?) checked="checked"/,'\1')
    end
  end
  h.keys.each do |k|
    case k
    when "searchType","ketsuronSearchType","seikyuninSearchType","jisshikikanSearchType","shinsakaiSearchType","shinsakailastSearchType"
      if h[k]=="or"
        #p k
        str.sub!(/("#{k}" value="and") checked="checked"/, '\1')
        str.sub!(/("#{k}" value="or")/, '\1 checked="checked"')
        #p str.match(/"#{k}" value="or".*/)[0]
      end
    when "bukai","jisshiKikan","reportDateFromEra","reportDateToEra","reportDateRange","reportNoRange"
      str.sub!(/.*#{k}.*?#{h[k]}"/m, '\0 selected') if h[k]!=""
    when
      str.sub!(/"#{k}"\s+value=""/, k+' value="'+h[k]+'"')
    end
  end
  str
end

#toshin=Toshin.new
# toshin.get_bango({:num => {:from => "1500",:to => "1700"},:iin=>"藤原"})
#h=toshin.get_hinagata_data({:num => {:from => "150",:to => "2500"}})
#h=toshin.get_hinagata_data({:freeWord => ["理由付記"],:freeWordType=>"and"})
#p h
#p h["答申第1442号から第1444号まで"]

 